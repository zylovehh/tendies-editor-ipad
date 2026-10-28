# 交互壁纸编辑器（iPad 版）

所有用户看得见的文字都用中文；代码里的英文标识符、文件名、路径不改。

# TendiesEditor（iPad 版交互壁纸编辑器 App）

一个最小的 WKWebView 套壳 App：全屏打开 Bundle 里的 `index.html`，不发任何网络请求，编辑器完全在本地跑（图片只在内存，导出 `.tendies` 在本机打包）。

## 关键参数

- App 名：`TendiesEditor`
- Bundle ID：`com.tendies.editor`（占位，用户重签时会改）
- 只支持 iPad：工程里 `TARGETED_DEVICE_FAMILY = 2`，`Info.plist` 里 `UIRequiresFullScreen = true`
- 方向：横屏优先，也允许竖屏；UI 按横屏三栏设计
- 最低系统：iPadOS 16.0（iPadOS 18.7.8 和 iPadOS 27 都能装）
- Swift 5.0，入口是 SwiftUI（不用 AppDelegate / SceneDelegate）

## 换最终版 index.html 的路径（只改这一个文件，不动工程）

网页版按 CAPlayground 截图复刻的最终版改完后，替换这里：

```
TendiesEditor/index.html
```

要求：文件名必须还是 `index.html`，放在 `TendiesEditor/` 目录里。文件名和目录不变时，`project.pbxproj` 不用改，推上去直接重新编译就能拿到新包。

## 离线说明（JSZip 目前还是 CDN，先保持原样）

当前 `TendiesEditor/index.html` 是手写校验过的 v8 副本，里面引用了 CDN：

```
https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js
```

也就是说：现在这个版本**导出 .tendies 时需要联网加载 JSZip**，离线会失败。先保持原样编第一版验证工程能通；换最终版时一并换成本地 JSZip，做法是：

1. 把 `jszip.min.js` 下载到 `TendiesEditor/jszip.min.js`；
2. 把 `index.html` 里的上面那行 CDN 地址改成 `./jszip.min.js`；
3. 在 `project.pbxproj` 里给 `jszip.min.js` 加一个 `PBXFileReference` + `PBXBuildFile`，并把它放进 `Resources` 构建阶段（和 `index.html` 同一级），否则打包进不了 Bundle，WebView 读不到。

## 编译（GitHub Actions 的 Mac 机，未签名）

1. 在用户 GitHub 账号下新建一个仓库，把本目录全部文件推上去（包括 `.github/workflows/build-ipa.yml`）；
2. 在仓库的 Actions 里跑 `Build unsigned IPA`（推到 main 也会自动跑）；
3. 跑完在 Artifacts 里下载 `TendiesEditor-unsigned-ipa`，得到 `TendiesEditor-unsigned.ipa`；
4. 用户自己用 AltStore / SideStore / 其他签名方式签名安装到 iPad 上。

本地编译命令（有 Mac / Xcode 时，和 Actions 里同一条）：

```sh
xcodebuild -project TendiesEditor.xcodeproj -scheme TendiesEditor \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

## 未验证的事项（明说）

- 本机是 Linux，没有 Xcode，**没有本地验证过这个工程能编过**。最终验证靠 GitHub Actions 第一次构建的日志：如果报 `project.pbxproj` 引用错、Swift 语法错或 scheme 找不到，按日志里那一行改。
- AppIcon 目前是空占位（`AppIcon.appiconset/Contents.json` 里没有图片），编译能过，但装机后图标是默认占位；要正式图标再补 1024×1024 的图进该目录。
- 真机安装、三态 / 动画 / 视差在 iPad 上的效果，仍需用户在 iPad 上实测后反馈。
