//
//  LingVisSDK.swift
//  R2Navigator
//

import Foundation
import WebKit
import R2Shared


class LingVisSDK: NSObject, WKScriptMessageHandler {
  private static var app = ""
  private static var token = ""
  private static var gotToken = true
  private var webView: WKWebView
  private var bookId: String
  
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
  
  class func getHook(publication: Publication) -> (_: WKWebView) -> AnyObject {
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
    if msg == "ready" {
      start();
    } else if msg.starts(with: "token:") {
      let index1 = msg.index(msg.startIndex, offsetBy: 6)
      LingVisSDK.token = String(msg[index1...])
      LingVisSDK.gotToken = true
    } else if msg.starts(with: "error:") {
      let index1 = msg.index(msg.startIndex, offsetBy: 6)
      let alert = UIAlertController(title: "Error", message: String(msg[index1...]), preferredStyle: UIAlertController.Style.alert)
      alert.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
      UIApplication.shared.keyWindow?.rootViewController?.present(alert, animated: true, completion: nil)
    }
  }
  
  @objc
  private func start() {
    if !LingVisSDK.gotToken {
      perform(#selector(start), with: nil, afterDelay: 0.2)
      return;
    }
    let appStr = escape(str: LingVisSDK.app)
    let bookIdStr = escape(str: bookId)
    if bookId.count == 0 {
      LingVisSDK.gotToken = false
    }
    webView.evaluateJavaScript("lingVisSdk.polyReadiumSignIn('\(LingVisSDK.token)', '', '', '\(appStr)', '\(bookIdStr)')")
  }
  
  class func signIn(email: String, password: String, newAccount: Bool) {
    LingVisSDK.gotToken = false
    LingVisSDK._shared!.webView.evaluateJavaScript("lingVisSdk.polyReadiumSignIn('', '\(escape(str: email))', '\(escape(str: password))', '', '', \(newAccount))")
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
