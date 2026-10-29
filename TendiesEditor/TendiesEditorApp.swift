import SwiftUI

// App 入口：整个界面就是一个全屏 WKWebView，见 WebView.swift。
// 之前用 GeometryReader + .frame(geo) 会在启动时按竖屏尺寸定住，导致横屏后右侧留黑条。
// 现在直接让 WebView 铺满窗口并忽略安全区，尺寸由系统窗口决定，不再用启动时的 UIScreen 尺寸。
@main
struct TendiesEditorApp: App {
    var body: some Scene {
        WindowGroup {
            WebView()
                .ignoresSafeArea(.all, edges: .all)
        }
    }
}
