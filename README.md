# c001apk for iOS

原生 iOS 27 SwiftUI 酷安第三方客户端，完整移植 [TG-Twilight/c001apk](https://github.com/TG-Twilight/c001apk) 的全部功能，并参考 [Mora-han/coolapk-for-mac](https://github.com/Mora-han/coolapk-for-mac) 的纯 Swift 协议层实现。

## 特性亮点

- **iOS 27 原生 Liquid Glass 设计**：严格遵守 [iOS 27 UI 设计规范](docs/design/iOS27-UI-Design-Spec.md)，采用系统原生 `TabView`（含 `.search` 独立搜索栏与 iPad 自适应侧栏）、`NavigationStack`、原生 `List`/`Form`，仅在浮动看图控制栏与轻提示处克制使用 `.glassEffect()`，内容层零冗余装饰。
- **异步解耦与高性能滚动**：`CoolapkClient` 与 `ImagePipeline` 采用 Swift `actor` 隔离，结合 `ImageIO` 按需降采样、`NSCache` 富文本缓存与 `sessionGeneration` 请求代际取消机制。
- **完整社区功能**：
  - 首页多分类定制（动态 / 热门 / 话题 / 数码 / 酷图 / 应用 / 头条）与卡片体系
  - 关注流（全部合并时间线 / 关注用户 / 关注话题 / 本机悄悄关注，支持游客本机关注）
  - 动态与图文长文详情、评论排序、只看楼主、酷币表情评论自动折叠、楼中楼、作者置顶/删评
  - 发动态 / 转发 / 回复（多图上传、官方表情面板、`@用户` 与 `#话题#` 选择）
  - 通知中心与私信聊天（文字、阿里云 OSS 图片发送、图片 302 解析、消息删除）
  - 全屏看图器：**HDR 高动态范围支持**（带“我不想看 HDR”开关）、**Live Photo 实况播放与原件保存**
  - **帖子/文章保存**：Markdown 与图片 Base64 内嵌离线 HTML 导出
  - **本机内容过滤（屏蔽傻逼内容）**：标准 / 严格两档、作者/话题/距离共现词组、个人规则、订阅更新与例外管理
  - **多账号与风控**：Keychain 多账号切换与游客模式、图形验证码 / 网页登录、人机验证 WebView 放行、数盟设备标识（`ShuzlmID` 自动获取与官方复制导入）

## 云端编译（GitHub Actions）

仓库已配置 [`.github/workflows/build.yml`](.github/workflows/build.yml)（基于 `xcode-27` runner）：
1. 自动运行 `CoolapkKit` 单元测试 (`swift test`)。
2. 通过 `XcodeGen` (`project.yml`) 生成工程并编译 `Release` 真机包。
3. 打包产出未签名 `C001APK-iOS27-unsigned.ipa` 与 SHA-256 校验文件并上传至 Actions Artifacts。

> 如需在本地 macOS (Xcode 27+) 构建：运行 `xcodegen generate` 后打开 `C001APK.xcodeproj` 编译即可。
