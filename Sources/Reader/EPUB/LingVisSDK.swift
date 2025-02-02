//
//  LingVisSDK.swift
//

import Foundation
import WebKit
import R2Shared


class LingVisSDK: NSObject, WKScriptMessageHandler {
  private static var app = ""
  private static var token = ""
  private static var gotToken = true
  private static var currLang = ""
  private static var updating = false
  private static var updatingInternal = false
  public static var willChangeLanguage: ((Publication) -> ChangeLanguageParams)? = nil
  public static var didChangeLanguage: ((Result<String, Error>) -> Void)? = nil
  private var webView: WKWebView
  private var bookId: String
  
  struct ChangeLanguageParams {
    var l2 = ""
    var l1 = ""
    var proceed = true
  }
  
  class func prepare(app: String) {
    LingVisSDK.app = app
    _ = LingVisSDK.shared
  }
  
  private static var _shared: LingVisSDK?
  class var shared: LingVisSDK {
    get {
      if LingVisSDK._shared == nil {
        let wk = WKWebView()
        let url = Bundle.main.url(forResource: "poly-core", withExtension: "html", subdirectory: "")!
        wk.loadFileURL(url, allowingReadAccessTo: url)
        LingVisSDK._shared = LingVisSDK(webView: wk, bookId: "")
      }
      return LingVisSDK._shared!
    }
  }

  init(webView: WKWebView, bookId: String) {
    self.webView = webView
    self.bookId = bookId
    super.init()
    webView.configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
    addScript(webView: webView, name: "poly-core")
    let controller = webView.configuration.userContentController
    controller.add(WeakWKScriptMessageHandler(delegate: self), name: "lingVisSDK")
  }
  
  class func getHook(publication: Publication) -> ((_: WKWebView) -> AnyObject)? {
    var lang = publication.metadata.languages.first ?? ""
    lang = lang.components(separatedBy: "-")[0]
    if (lang != "" && lang != currLang) {
      var l1 = ""
      var proceed = true
      if willChangeLanguage != nil {
        let params = willChangeLanguage!(publication)
        proceed = params.proceed
        if params.l2 != "" {
          lang = params.l2
        }
        if params.l1 != "" {
          l1 = params.l1
        }
      }
      if !proceed { return nil }
      LingVisSDK.updatingInternal = true
      LingVisSDK.updateSettings(l2: lang, l1: l1, level: "", completion: { result in
        LingVisSDK.updatingInternal = false
        switch result {
          case .success:
            LingVisSDK.updating = false
          case .failure:
            break
        }
        if didChangeLanguage != nil {
          didChangeLanguage!(result)
        }
      })
    }
    return {
      (webView: WKWebView) -> AnyObject in
        let id = publication.metadata.identifier ?? ""
        let bookId = publication.metadata.title + ":" + id
        return LingVisSDK(webView: webView, bookId: bookId)
    }
  }
  
  private func addScript(webView: WKWebView, name: String) -> Void {
    let script = Bundle.module.url(forResource: "\(name)", withExtension: "js", subdirectory: "").flatMap { try? String(contentsOf: $0) }!
    let controller = webView.configuration.userContentController
    controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
  }
  
  private func escape(str: String?) -> String {
    return LingVisSDK.escape(str: str)
  }
  
  private class func escape(str: String?) -> String {
    if str == nil { return "" }
    var res = str!
    // see https://github.com/joliss/js-string-escape/blob/master/index.js
    res = res.replacingOccurrences(of: "\\", with: "\\\\")
    res = res.replacingOccurrences(of: "'", with: "\\'")
    res = res.replacingOccurrences(of: "\"", with: "\\\"")
    res = res.replacingOccurrences(of: "\n", with: "\\n")
    res = res.replacingOccurrences(of: "\r", with: "\\\r")
    res = res.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
    res = res.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    return res
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    if message.name != "lingVisSDK" { return }
    guard let msg = message.body as? String else { return }
    if msg == "ready:" {
      start()
    } else if msg.starts(with: "token:") {
      let idx = msg.index(msg.startIndex, offsetBy: 6)
      let parts = String(msg[idx...]).components(separatedBy: "|")
      LingVisSDK.token = parts[1]
      LingVisSDK.gotToken = true
      if parts[0].count > 0 {
        invokeCallback(callbackId: parts[0], arg: parts[1], error: parts[2])
      }
    } else if msg.starts(with: "callback:") {
      let idx = msg.index(msg.startIndex, offsetBy: 9)
      let str = String(msg[idx...])
      let parts = str.components(separatedBy: "|")
      invokeCallback(callbackId: parts[0], arg: parts[1], error: parts[2])
    }
  }
  
  typealias CallbackFunc = (String, String) -> Void
  
  private var callbacks: Dictionary = [String: CallbackFunc]()
  
  private func addCallback(callback: @escaping CallbackFunc) -> String {
    let uuid = UUID().uuidString
    callbacks[uuid] = callback
    return uuid
  }
  
  private func invokeCallback(callbackId: String, arg: String, error: String) {
    let callback = callbacks[callbackId]
    if callback == nil { return }
    callbacks.removeValue(forKey: callbackId)
    callback!(arg, error)
  }
  
  @objc
  private func start() {
    if !LingVisSDK.gotToken || LingVisSDK.updating {
      perform(#selector(start), with: nil, afterDelay: 0.2)
      return
    }
    let appStr = escape(str: LingVisSDK.app)
    let bookIdStr = escape(str: bookId)
    if bookId.count == 0 {
      LingVisSDK.gotToken = false
    }
    webView.evaluateJavaScript("lingVisSdk.polyReadiumSignIn('', '\(LingVisSDK.token)', '', '', '\(appStr)', '\(bookIdStr)')")
  }
  
  enum Error: Swift.Error, CustomStringConvertible {
      case customError(message: String)
      var description: String {
          switch self {
            case .customError(message: let message): return message
          }
      }
  }

  class func signIn(email: String, password: String, newAccount: Bool, completion: @escaping (Result<String, Error>) -> Void) {
    let main = LingVisSDK._shared!
    let callback = main.addCallback(callback: {
      (arg: String, error: String) -> Void in
      if error.count > 0 {
        completion(.failure(.customError(message: error)))
      } else {
        completion(.success(""))
      }
    })
    let appStr = escape(str: LingVisSDK.app)
    main.webView.evaluateJavaScript("lingVisSdk.polyReadiumSignIn('\(callback)', '', '\(escape(str: email))', '\(escape(str: password))', '\(appStr)', '', \(newAccount))")
  }
  
  class func getSettings(completion: @escaping (Result<String, Error>) -> Void) {
    let main = LingVisSDK._shared!
    let callback = main.addCallback(callback: {
      (arg: String, error: String) -> Void in
      if error.count > 0 {
        completion(.failure(.customError(message: error)))
      } else {
        completion(.success(arg))
      }
    })
    main.webView.evaluateJavaScript("lingVisSdk.polyReadiumGetSettings('\(callback)')")
  }

  class func updateSettings(l2: String, l1: String, level: String, completion: @escaping (Result<String, Error>) -> Void) {
    let main = LingVisSDK._shared!
    let callback = main.addCallback(callback: {
      (arg: String, error: String) -> Void in
      if !LingVisSDK.updatingInternal  {
        LingVisSDK.updating = false
      }
      if error.count > 0 {
        completion(.failure(.customError(message: error)))
      } else {
        if l2 != "" {
          LingVisSDK.currLang = l2
        }
        completion(.success(arg))
      }
    })
    if l2 != "" {
      LingVisSDK.updating = true
    }
    main.webView.evaluateJavaScript("lingVisSdk.polyReadiumUpdateSettings('\(callback)', '\(l2)', '\(l1)', '\(level)')")
  }
  
}

#if !SWIFT_PACKAGE
extension Bundle {
    static let module = Bundle(for: LingVisSDK.self)
}
#endif

class WeakWKScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
  
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }
  
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            self.delegate?.userContentController(userContentController, didReceive: message)
    }
}

