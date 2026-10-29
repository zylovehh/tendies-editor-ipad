import SwiftUI

// App 入口（SwiftUI 生命周期，不用 AppDelegate / SceneDelegate）。
// 整个界面就是一个全屏 WKWebView，见 WebView.swift。
@main
struct TendiesEditorApp: App {
    var body: some Scene {
        WindowGroup {
            WebView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        }
    }
}
