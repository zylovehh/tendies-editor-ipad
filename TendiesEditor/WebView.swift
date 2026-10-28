import SwiftUI
import UIKit
import WebKit

// 全屏 WKWebView：只加载 Bundle 里的 index.html，编辑器完全离线跑。
// （JSZip 已换成本地 TendiesEditor/jszip.min.js，不走 CDN，断网也能导出。）
//
// 关键点，缺一不可：
// 1. 选图：网页里的 <input type="file" accept="image/*"> 由 WKWebView 原生接管，
//    iPad 上会弹出系统相册选图框（PHPicker），不需要 App 自己再写一个选图器，
//    前提是 Info.plist 里有 NSPhotoLibraryUsageDescription（已加，全中文文案）。
//    不要用自定义 JS 弹框代替系统选图框，那样拿不到相册原图。
// 2. 导出下载：WKWebView 默认不支持 blob 下载，不拦截就会悄悄失败。
//    下面用 WKNavigationDelegate + WKDownloadDelegate 接管：未知 MIME 类型走
//    .download，下载完成存到临时目录，再弹系统分享单（UIActivityViewController），
//    用户可存到“文件”、隔空投送、或直接用 Pocket Poster / Nugget 打开。
//    网页内原有导出逻辑（JSZip 打包 .tendies、生成 blob、触发下载）原样保留，
//    这里只是把浏览器做不了的那一步在原生层补上，不是假按钮。
// 3. 手势：编辑器画布的拖动、双指捏合由网页内 pointer 事件处理，
//    WKWebView 的滚动视图不拦截画布手势；UIRequiresFullScreen = true
//    已在 Info.plist 里打开，避免 iPad 分屏 / Slide Over 把三栏压窄，
//    也避免系统边缘手势和编辑器拖动抢手势。右侧检查器自身的滚动仍正常。
struct WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // JavaScript 默认就是开的，这里显式写明，免得以后 SDK 默认变了。
        config.preferences.javaScriptEnabled = true
        // 本地文件访问：index.html 在 Bundle 里，JSZip 也是本地文件，
        // 导出 .tendies 时 JS 要读写内存里的图片数据，不走网络。
        config.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // 画布手势不被滚动视图抢走：编辑器面板自身的滚动不受影响，
        // 画布元素在网页里已用 touch-action: none 接管拖动和捏合。
        webView.scrollView.bounces = false
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

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        // decideDestinationUsing 里记下的下载目标，downloadDidFinish 时用它弹分享单。
        // WKDownload 本身不对外暴露目标路径，所以必须自己记一份。
        private var pendingDownloadURL: URL?

        // 未知 MIME 类型（.tendies、zip、blob 下载）不直接打开，改走下载流程。
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if !navigationResponse.canShowMIMEType {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        // 响应变成下载后，把下载代理交给自己，后续走 decideDestination / didFinish。
        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        // 下载目标：系统临时目录 + 建议文件名（编辑器给的就是 xxx.tendies）。
        // 先删同名旧文件，避免“文件已存在”导致下载失败。
        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let name = suggestedFilename.isEmpty ? "wallpaper.tendies" : suggestedFilename
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            pendingDownloadURL = dest
            completionHandler(dest)
        }

        // 下载完成：弹系统分享单。iPad 上分享单必须是 popover，
        // 必须给 sourceView / sourceRect，否则会直接闪退。
        func downloadDidFinish(_ download: WKDownload) {
            guard let url = pendingDownloadURL else { return }
            pendingDownloadURL = nil
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.excludedActivityTypes = [.assignToContact]
            present(sheet)
        }

        // 下载失败：弹中文提示，不要悄悄失败让用户以为导出成功了。
        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            pendingDownloadURL = nil
            let alert = UIAlertController(
                title: "导出失败",
                message: "壁纸文件没有下载下来，请再点一次“导出 .tendies”。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "知道了", style: .default))
            present(alert)
        }

        // 从当前 key window 的根控制器往上找到最顶层控制器再 present，
        // 分享单和提示框都走这一路，避免 SwiftUI 里拿不到 presenter。
        private func present(_ controller: UIViewController) {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
            else { return }
            while let presented = top.presentedViewController {
                top = presented
            }
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(
                    x: top.view.bounds.midX, y: top.view.bounds.midY,
                    width: 0, height: 0
                )
                popover.permittedArrowDirections = []
            }
            top.present(controller, animated: true)
        }
    }
}
