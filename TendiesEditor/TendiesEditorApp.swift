import SwiftUI

// App 入口（SwiftUI 生命周期，不用 AppDelegate / SceneDelegate）。
// 整个界面就是一个全屏 WKWebView，见 WebView.swift。
@main
struct TendiesEditorApp: App {
    var body: some Scene {
        WindowGroup {
            GeometryReader { geo in
                WebView()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
            }
        }
    }
}
