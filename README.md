# 交互壁纸编辑器（iPad 版）

所有用户看得见的文案都用中文；代码里的英文标识符、文件名、路径不改。
App 显示名：**交互壁纸编辑器**（`Info.plist` 里 `CFBundleDisplayName`）。

这不是空壳：装好后在 iPad 上能完整走通——选图 → 编辑 → 导出 .tendies → 分享出去用 Pocket Poster / Nugget 装锁屏。

## 完整使用流程（真机上就是这条线）

1. **选图**：编辑器里点选图，iPad 弹出系统相册选图框，选背景图和前景图。
   前提是 `Info.plist` 里有相册权限说明（已加，全中文，见下面）。
2. **编辑**：横屏三栏编辑——左边图层、中间画布、右边检查器。
   背景和前景都能在画布里拖动、双指捏合缩放，另有大小、左右、上下、旋转、透明度滑杆；
   锁屏 / 解锁 / 睡眠三态可预览切换，循环动画、文字、渐变、形状、液态玻璃、粒子、陀螺仪视差都在。
3. **导出**：点“导出 .tendies”，网页内原有导出逻辑原样跑（JSZip 在本地打包，见下面），
   生成 .tendies 后由原生层接管下载，不会悄悄失败。
4. **分享装机**：导出完成后自动弹出系统分享单，可存到“文件”、隔空投送，
   或直接用 Pocket Poster / Nugget 打开，装到 iPhone / iPad 锁屏。
   装好后重点看：解锁上移、三态透明度、循环动画、视差层级（人物要在锁屏时钟前面）。

## 关键参数

- App 名：`TendiesEditor`，显示名：交互壁纸编辑器
- Bundle ID：`com.tendies.editor`（占位，用户重签时会改）
- 只支持 iPad：工程里 `TARGETED_DEVICE_FAMILY = 2`，`Info.plist` 里 `UIRequiresFullScreen = true`
  （不开分屏 / Slide Over，保证三栏布局不被压窄）
- 方向：横屏优先，也允许竖屏；UI 按横屏三栏设计
- 最低系统：iPadOS 16.0
- Swift 5.0，入口是 SwiftUI（不用 AppDelegate / SceneDelegate），全屏 WKWebView 见 `WebView.swift`

## 1. 相册权限（已改）

`TendiesEditor/Info.plist` 已加，全中文文案：

- `NSPhotoLibraryUsageDescription`：需要访问相册，以便你在编辑器里选择背景图和前景图，制作交互壁纸。
- `NSPhotoLibraryAddUsageDescription`：需要保存到相册，以便把做好的壁纸图片或导出的文件保存到你的相册里。

网页里的 `<input type="file" accept="image/*">` 由 WKWebView 原生接管，
iPad 上弹出的是系统相册选图框，不是网页里自己弹的框，这样才能拿到相册原图。
不要把选图改成自定义 JS 弹框。

## 2. 导出下载接管（已改，不是假按钮）

WKWebView 默认不支持 blob 下载，不处理就会悄悄失败。
`TendiesEditor/WebView.swift` 里已用 `WKNavigationDelegate` + `WKDownloadDelegate` 接管：

- 未知 MIME 类型（.tendies / zip / blob 下载）走 `.download`，不是直接打开；
- 响应变成下载后由 `WKDownloadDelegate` 决定目标：系统临时目录 + 建议文件名（就是 xxx.tendies）；
- 下载完成弹系统分享单（`UIActivityViewController`），iPad 上按 popover 方式弹出，
  已给 `sourceView` / `sourceRect`，不会因此闪退；
- 下载失败弹中文提示“导出失败，请再点一次导出 .tendies”，不悄悄失败。

网页内原有导出逻辑（JSZip 打包、生成 blob、触发下载）原样保留，
原生层只是把浏览器做不了的下载和分享那一步补上。

## 3. 离线 JSZip（已改，没有 CDN 兜底）

JSZip 已从 CDN 换成本地文件，断网也能导出：

- 本地文件：`TendiesEditor/jszip.min.js`（v3.10.1，97,630 字节，文件头可核对版本号）
- `TendiesEditor/index.html` 里第 10 行已改成 `<script src="./jszip.min.js"></script>`，
  全文已查过，没有再引用 cdnjs 或其他 CDN 地址，也没有 CDN 兜底；
  剩下两个 `http://www.apple.com/CoreAnimation/1.0` 只是生成 CAML 里的 XML 命名空间字符串，不是联网加载。
- `project.pbxproj` 里已给它加了 `PBXFileReference` + `PBXBuildFile`，
  并放进了 `Resources` 构建阶段，和 `index.html` 同一级，打包时会进 Bundle，
  WebView 用 `loadFileURL` 的读权限（Bundle 目录）能读到。

## 4. 最终版 HTML 占位说明（重要：现在这个不是最终版）

目前 `TendiesEditor/index.html` 还是 **v8 副本**，不是最终版。
网页版全中文复刻版（按 CAPlayground 截图做的那版）还在解决导出资源问题，
等它解决完，替换路径就是只换下面这一个文件：

```
TendiesEditor/index.html
```

要求：文件名必须还是 `index.html`，放在 `TendiesEditor/` 目录里。
文件名和目录不变时，`project.pbxproj` 不用改，推上去重新编译即是最终 IPA。
**不要把 v8 说成最终版**——v8 只是先用来验证工程能编通的占位。

换最终版时顺带核对两件事：最终版 HTML 里也不能再引 CDN（JSZip 已本地化，
最终版如果又引了 CDN，要同样换成本地 `./jszip.min.js` 再编）；最终版的导出
文件名和 blob 下载逻辑不变，原生下载接管不用改。

## 5. iPad 适配（已落实）

- 只支持 iPad、横屏三栏优先、全屏 WKWebView（见关键参数）。
- 画布拖动、双指捏合由网页内 pointer 事件处理，WKWebView 的滚动视图不拦截画布手势；
  右侧检查器自身的滚动仍正常。`scrollView.bounces` 已关，避免回弹干扰拖动。
- 键盘：网页里的文字输入框由 WKWebView 原生键盘处理，不需要 App 另外写键盘逻辑。
- 所有用户看得见的文案用中文：App 显示名、权限说明、导出失败提示、分享单都是中文；
  代码标识符、文件名、路径保持英文。

## 编译（GitHub Actions 的 Mac 机，未签名）

1. 在用户 GitHub 账号下新建一个仓库，把本目录全部文件推上去（包括 `.github/workflows/build-ipa.yml`）；
2. 在仓库的 Actions 里跑“编译未签名 IPA”（推到 main 也会自动跑）；
3. 跑完在 Artifacts 里下载 `TendiesEditor-unsigned-ipa`，得到 `TendiesEditor-unsigned.ipa`；
4. 用户自己用 AltStore / SideStore / 其他签名方式签名安装到 iPad 上。

本地编译命令（有 Mac / Xcode 时，和 Actions 里同一条）：

```sh
xcodebuild -project TendiesEditor.xcodeproj -scheme TendiesEditor \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

## 未验证的事项（明说，不要说成已验证能用）

- 本机是 Linux，没有 Xcode，**没有本地验证过这个工程能编过**。
  最终验证靠 GitHub Actions 第一次构建的日志：如果报 `project.pbxproj` 引用错、
  Swift 语法错或 scheme 找不到，按日志里那一行改。
  尤其注意：`WKDownloadDelegate` 的下载接管、`UIActivityViewController` 的 iPad popover、
  系统相册选图框这三处，只有真机能最终验证，静态自查只能保证引用和语法层面没错。
- AppIcon 目前是空占位（`AppIcon.appiconset/Contents.json` 里没有图片），
  编译能过，但装机后图标是默认占位；要正式图标再补 1024×1024 的图进该目录。
- 没有 LaunchScreen：启动时会短暂黑屏再出 WebView，不影响使用，如需正式启动页再补。
- 真机验证清单（用户装机后逐项测，缺一不可才算真正能用）：
  1. 选图：能打开系统相册，背景图和前景图都能选进画布；
  2. 编辑：拖动、双指捏合、滑杆、三态切换、动画预览都跟手；
  3. 导出分享：点导出能弹出分享单，.tendies 能存到“文件”或隔空投送；
  4. 装机：用 Pocket Poster / Nugget 装锁屏后，解锁上移、三态透明度、循环动画、视差层级都正常。
