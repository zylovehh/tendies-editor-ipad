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
// 2. 导出下载（旧路径，保留）：WKWebView 默认不支持 blob 下载，不拦截就会悄悄失败。
//    下面用 WKNavigationDelegate + WKDownloadDelegate 接管：未知 MIME 类型走
//    .download，下载完成存到临时目录，再弹系统分享单（UIActivityViewController），
//    用户可存到“文件”、隔空投送、或直接用 Pocket Poster / Nugget 打开。
//    网页内原有导出逻辑（JSZip 打包 .tendies、生成 blob、触发下载）原样保留，
//    这里只是把浏览器做不了的那一步在原生层补上，不是假按钮。
// 3. 导出消息桥（新路径，tendiesExport）：网页侧导出后会尝试
//    webkit.messageHandlers.tendiesExport.postMessage，分块发 base64 编码的
//    .tendies 数据；如果 App 没注册这个桥，网页会退回“分享 / 保存到文件”和
//    “重新下载”按钮那条路。本文件注册了这个桥，两种导出路径都要能走，
//    互不冲突：走桥的导出不再经过 WKDownloadDelegate，走下载的导出不受桥影响。
//    注意：网页侧分块字段的精确约定（见下面“桥接约定（假设）”）在本机无法
//    向网页侧最新版核对，因为网页版本身由另一个系统负责、这里不碰它。
//    下面实现按宽容解析写，兼容几种合理字段名，但真机上仍需与网页侧逐项对齐。
// 4. 手势：编辑器画布的拖动、双指捏合由网页内 pointer 事件处理，
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
        // 本地文件访问靠下面 loadFileURL 的 allowingReadAccessTo（Bundle 目录）实现，
        // 不再用 setValue 私有键：WKWebViewConfiguration 在新系统上对这两个键不是 KVC 兼容，
        // 启动时直接抛异常闪退，之前 iPhone 点开闪退最可能就是这两行。
        // 原生消息桥必须在 loadFileURL 之前注册，否则网页加载时发的第一条
        // 消息会因为桥还没注册而丢掉。名字必须 exactly 是 tendiesExport，
        // 网页侧按这个名字找，拼写差一个字母网页就会判定桥不存在而走回退路。
        config.userContentController.add(context.coordinator, name: "tendiesExport")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // 画布手势不被滚动视图抢走：编辑器面板自身的滚动不受影响，
        // 画布元素在网页里已用 touch-action: none 接管拖动和捏合。
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        // 原版 CAPlayground 静态导出：用 cap:// 本地协议跑，不用 file://。
        // file:// 下 /_next/ 这种绝对路径读不到包里文件，cap:// 全部走下面的
        // WKURLSchemeHandler，按路径从 Bundle 的 caplayground/ 目录取文件，
        // /editor/任何新项目号都回落到 editor/demo.html，客户端再按 URL 里的
        // 真实项目号从 localStorage 取项目，路由才不会 404。
        config.setURLSchemeHandler(context.coordinator, forURLScheme: "cap")
        if let url = URL(string: "cap://app/projects.html") {
            webView.load(URLRequest(url: url))
        } else if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 横屏全屏关键：不要用启动时的 UIScreen 尺寸，始终铺满父视图（窗口）。
        // SwiftUI 的 UIViewRepresentable 在旋转时不会自动改 frame，这里强制跟父视图走。
        if let parent = uiView.superview, uiView.frame != parent.bounds {
            uiView.frame = parent.bounds
            uiView.scrollView.frame = uiView.bounds
        }
        uiView.scrollView.contentInset = .zero
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler, WKURLSchemeHandler {
        // MARK: - cap:// 本地协议：把静态导出文件从 Bundle 里喂给 WKWebView
        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url else {
                urlSchemeTask.didFailWithError(NSError(domain: "cap", code: -1, userInfo: nil))
                return
            }
            // Next 客户端路由取 RSC 数据：静态包里没有新项目号的 RSC，直接 404，
            // 让客户端路由退回整页导航，整页导航再由下面 /editor/ 回落处理。
            if let q = url.query, q.contains("_rsc") {
                if let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil) {
                    urlSchemeTask.didReceive(resp); urlSchemeTask.didFinish()
                }
                return
            }
            var path = url.path
            if path.isEmpty || path == "/" { path = "/projects.html" }
            let base = Bundle.main.url(forResource: "caplayground", withExtension: nil)
            func serve(_ rel: String, status: Int = 200) {
                guard let b = base else { return }
                let file = b.appendingPathComponent(rel)
                guard let data = try? Data(contentsOf: file) else {
                    if let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil) {
                        urlSchemeTask.didReceive(resp); urlSchemeTask.didFinish()
                    }
                    return
                }
                let ext = (rel as NSString).pathExtension.lowercased()
                let mime: String
                switch ext {
                case "html": mime = "text/html"
                case "js": mime = "text/javascript"
                case "css": mime = "text/css"
                case "json": mime = "application/json"
                case "png": mime = "image/png"
                case "jpg", "jpeg": mime = "image/jpeg"
                case "svg": mime = "image/svg+xml"
                case "woff2": mime = "font/woff2"
                case "woff": mime = "font/woff"
                case "txt": mime = "text/plain"
                case "ico": mime = "image/x-icon"
                case "mp4": mime = "video/mp4"
                case "webp": mime = "image/webp"
                default: mime = "application/octet-stream"
                }
                if let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime, "Content-Length": String(data.count)]) {
                    urlSchemeTask.didReceive(resp); urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
                }
            }
            let rel = String(path.dropFirst())
            if rel.hasSuffix(".html") || rel.contains(".") {
                // 有扩展名的直接取文件；/editor/demo.html、/_next/...、图片、字体都走这里
                serve(rel); return
            }
            if path.hasPrefix("/editor/") { serve("editor/demo.html"); return }
            if let b = base, FileManager.default.fileExists(atPath: b.appendingPathComponent(rel + ".html").path) { serve(rel + ".html"); return }
            serve("index.html")
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
        // decideDestinationUsing 里记下的下载目标，downloadDidFinish 时用它弹分享单。
        // WKDownload 本身不对外暴露目标路径，所以必须自己记一份。
        private var pendingDownloadURL: URL?

        // MARK: - tendiesExport 桥接约定（假设，需真机对齐）
        //
        // 以下约定是 App 侧的假设，不是已与网页侧核对过的事实：
        // 假设 A：每条 postMessage 的 body 是一个字典（或 JSON 字符串），字段为：
        //   type: "start" | "chunk" | "end" | "error" | "complete"（缺 type 时按 chunk 处理）
        //   id / exportId: 本次导出的标识，缺省为 "default"，用于区分连续两次导出
        //   index: 本块序号，从 0 开始；total: 总块数（可选，end 块为准）
        //   isLast / last: true 表示这是最后一块，收到后即拼包
        //   filename: 建议文件名，如 "wallpaper.tendies"，缺省为 "wallpaper.tendies"
        //   data / chunk / base64: 本块的 base64 字符串（可含换行，解码时忽略空白）
        // 假设 B：块按 index 排序拼包，同一 index 重复发只保留第一次收到的（去重），
        //   拼包时 index 必须连续（0..<total 或 0...lastIndex），缺块即报错不拼包。
        // 假设 C：拼好的数据就是 .tendies 文件本身（zip 格式），文件头应为 PK\x03\x04；
        //   不是 zip 头的数据会被当作导出失败处理，不会直接拿去分享。
        // 假设 D："start" 表示一次新导出开始，会丢弃同 id 未完成旧传输；"error" 带
        //   message 字段时直接弹中文提示并丢弃该传输；"complete" 且 data 为完整
        //   base64 时直接按单块拼包分享。
        // 宽容处理：字段名、type 缺省、字符串 body（先按 JSON 解析）都做了兼容，
        //   但如果网页侧实际约定与上面不同（例如字段叫 part/partIndex、或用
        //   二进制 ArrayBuffer 而不是 base64 字符串），真机上就会对不上，
        //   需要按网页侧实际代码把下面解析处逐项改对，不要在交付里说成已对齐。
        private struct ExportTransfer {
            var filename: String
            var chunks: [Int: Data] = [:]
            var lastIndex: Int?
            var total: Int?
        }

        private var exportTransfers: [String: ExportTransfer] = [:]

        // MARK: - WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // 消息回调可能不在主线程，状态读写和弹框统一回主线程，避免竞态。
            DispatchQueue.main.async { [weak self] in
                self?.handleTendiesExport(message.body)
            }
        }

        private func handleTendiesExport(_ body: Any) {
            // 1) 字符串 body：先尝试按 JSON 解析，解析失败则当作整包 base64 单块处理。
            if let text = body as? String {
                if let jsonData = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData),
                   let dict = json as? [String: Any] {
                    handleTendiesExportDict(dict)
                } else {
                    // 整包 base64，没有分块元数据，只能按单次完整文件处理。
                    finalizeBridgeExport(id: "default", filename: "wallpaper.tendies", chunks: [0: text])
                }
                return
            }
            guard let dict = body as? [String: Any] else {
                showBridgeError("导出数据格式不对，请再点一次“导出 .tendies”。")
                return
            }
            handleTendiesExportDict(dict)
        }

        private func handleTendiesExportDict(_ dict: [String: Any]) {
            let id = (dict["id"] as? String) ?? (dict["exportId"] as? String) ?? "default"
            let type = (dict["type"] as? String)?.lowercased() ?? "chunk"

            if type == "error" {
                exportTransfers.removeValue(forKey: id)
                let detail = (dict["message"] as? String) ?? ""
                showBridgeError(detail.isEmpty
                    ? "导出失败，请再点一次“导出 .tendies”。"
                    : "导出失败：\(detail)")
                return
            }

            if type == "start" {
                // 新导出开始，丢弃同 id 未完成的旧传输，避免旧块混进新包。
                exportTransfers.removeValue(forKey: id)
                return
            }

            let filename = sanitizedFilename(
                (dict["filename"] as? String) ?? (dict["name"] as? String)
            )
            let base64 = (dict["data"] as? String)
                ?? (dict["chunk"] as? String)
                ?? (dict["base64"] as? String)

            // complete：data 即整包，直接拼包分享，不走分块。
            if type == "complete" {
                guard let base64 = base64 else {
                    showBridgeError("导出数据不完整，请再点一次“导出 .tendies”。")
                    return
                }
                finalizeBridgeExport(id: id, filename: filename, chunks: [0: base64])
                return
            }

            // chunk / end：需要 data 和 index（end 块若缺 index，视为最后一块，
            // 但仍需 data；若连 data 都没有且已有块，则按“结束信号”处理）。
            let index = (dict["index"] as? Int)
                ?? (dict["part"] as? Int)
                ?? (dict["partIndex"] as? Int)
            let total = (dict["total"] as? Int) ?? (dict["totalChunks"] as? Int)
            let isLast = (dict["isLast"] as? Bool) ?? (dict["last"] as? Bool) ?? false

            if base64 == nil, !(type == "end" && !exportTransfers[id].isNil) {
                showBridgeError("导出数据不完整，请再点一次“导出 .tendies”。")
                exportTransfers.removeValue(forKey: id)
                return
            }

            // 分块必须带序号才能排序：有数据、无序号、又不是最后一块时，
            // 无法放进顺序里，宁可报错丢弃，也不要悄悄丢块拼出坏包。
            if base64 != nil, index == nil, !isLast {
                exportTransfers.removeValue(forKey: id)
                showBridgeError("导出数据不完整，缺少分块序号，请再点一次“导出 .tendies”。")
                return
            }

            var transfer = exportTransfers[id] ?? ExportTransfer(filename: filename)
            transfer.filename = filename
            if let total = total { transfer.total = total }
            if let base64 = base64, let index = index {
                // 去重：同一 index 只保留第一次收到的块，重复块直接忽略。
                if transfer.chunks[index] == nil,
                   let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                    transfer.chunks[index] = data
                } else if transfer.chunks[index] == nil {
                    // base64 解码失败：这块数据本身坏了，整包不能拼，直接报错丢弃。
                    exportTransfers.removeValue(forKey: id)
                    showBridgeError("导出数据解码失败，请再点一次“导出 .tendies”。")
                    return
                }
                if isLast { transfer.lastIndex = index }
            } else if isLast {
                // end 信号无 index：最后一块序号即当前已收最大序号。
                transfer.lastIndex = transfer.chunks.keys.max()
            }
            exportTransfers[id] = transfer

            let shouldFinalize = isLast || type == "end"
            if shouldFinalize {
                exportTransfers.removeValue(forKey: id)
                finalizeBridgeChunks(transfer)
            }
        }

        private func finalizeBridgeExport(id: String, filename: String, chunks: [Int: String]) {
            var decoded: [Int: Data] = [:]
            for (index, base64) in chunks {
                guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
                    showBridgeError("导出数据解码失败，请再点一次“导出 .tendies”。")
                    return
                }
                decoded[index] = data
            }
            finalizeBridgeChunks(ExportTransfer(filename: filename, chunks: decoded, lastIndex: 0, total: 1))
        }

        private func finalizeBridgeChunks(_ transfer: ExportTransfer) {
            // 确定应有块数：total 优先，其次 lastIndex+1，否则按已收块数推断。
            let expectedCount: Int
            if let total = transfer.total {
                expectedCount = total
            } else if let last = transfer.lastIndex {
                expectedCount = last + 1
            } else {
                expectedCount = transfer.chunks.count
            }
            guard expectedCount > 0 else {
                showBridgeError("导出数据为空，请再点一次“导出 .tendies”。")
                return
            }
            // 连续性检查：0..<expectedCount 必须每块都有，缺任何一块都不拼包。
            var assembled = Data()
            for index in 0..<expectedCount {
                guard let chunk = transfer.chunks[index] else {
                    showBridgeError("导出数据不完整，缺少第 \(index + 1) 块，请再点一次“导出 .tendies”。")
                    return
                }
                assembled.append(chunk)
            }
            // .tendies 本质是 zip 包，文件头应为 PK\x03\x04；不是则当失败处理，
            // 不要把一包坏数据拿去分享给用户装机。
            let zipMagic: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
            guard assembled.count >= 4,
                  Array(assembled.prefix(4)) == zipMagic else {
                showBridgeError("导出的数据不是有效的壁纸包，请再点一次“导出 .tendies”。")
                return
            }
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(transfer.filename)
            do {
                try? FileManager.default.removeItem(at: dest)
                try assembled.write(to: dest, options: .atomic)
            } catch {
                showBridgeError("壁纸文件保存失败，请再点一次“导出 .tendies”。")
                return
            }
            presentShareSheet(for: dest, deleteAfterSharing: true)
        }

        private func sanitizedFilename(_ raw: String?) -> String {
            guard let raw = raw, !raw.isEmpty else { return "wallpaper.tendies" }
            // 只取最后一段，去掉路径分隔符，防止网页给的路径写到别处。
            let name = raw.split(separator: "/").last.map(String.init) ?? raw
            let clean = name.split(separator: "\\").last.map(String.init) ?? name
            return clean.isEmpty ? "wallpaper.tendies" : clean
        }

        // MARK: - WKDownloadDelegate（旧下载路径，保留不动）

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
            presentShareSheet(for: url, deleteAfterSharing: true)
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

        // MARK: - 分享单与提示（桥和下载两条路共用）

        private func presentShareSheet(for url: URL, deleteAfterSharing: Bool) {
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.excludedActivityTypes = [.assignToContact]
            if deleteAfterSharing {
                // 分享完成（或取消）后再删临时文件：分享单回调时系统已完成复制 /
                // 隔空投送交接，删临时文件不会打断分享；不删则临时目录会越积越多。
                sheet.completionWithItemsHandler = { _, _, _, _ in
                    try? FileManager.default.removeItem(at: url)
                }
            }
            present(sheet)
        }

        private func showBridgeError(_ message: String) {
            let alert = UIAlertController(
                title: "导出失败",
                message: message,
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

// Swift 可选链在 Dictionary 上没有 isNil 成员，这里补一个小工具，
// 仅供上面 end 信号无 data 时判断“该传输是否已存在”。
private extension Optional {
    var isNil: Bool { self == nil }
}
