import SwiftUI
import WebKit

// 全屏 WKWebView：只加载 Bundle 里的 index.html，不发任何网络请求
// （index.html 自身引用的 JSZip CDN 除外，见 README 的离线说明）。
struct WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // JavaScript 默认就是开的，这里显式写明，免得以后 SDK 默认变了。
        config.preferences.javaScriptEnabled = true
        // 本地文件访问：index.html 在 Bundle 里，导出 .tendies 时
        // JS 要读写内存里的图片数据，不走网络、不走沙盒外文件。
        config.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // loadFileURL 的读权限只给 index.html 所在的 Bundle 目录。
        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 静态页面，不需要刷新。
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {}
}
