# c001apk for iOS (`swift-c001apk`)

原生 **iOS 27 SwiftUI / Swift 6** 酷安第三方客户端，以原生系统交互体验、高帧率异步渲染与 Liquid Glass 视觉语言为核心，完整实现酷安社区核心浏览、互动、风控适配与本地增强能力。

> 如果觉得项目对你有帮助，欢迎 Star 支持，也欢迎加入交流群反馈问题与建议。

---

## 作者与交流

- **作者**：AsrielXuwu
- **邮箱**：[asrielxuwu@outlook.com](mailto:asrielxuwu@outlook.com)
- **Telegram 交流群**：[https://t.me/swift_c001apk](https://t.me/swift_c001apk)
- **GitHub 仓库**：[AsrielXuwu/swift-c001apk](https://github.com/AsrielXuwu/swift-c001apk)

---

## 致谢与参考项目

本项目的协议实现、客户端功能体系与交互细节深度参考并致谢以下开源项目：

- [TG-Twilight/c001apk](https://github.com/TG-Twilight/c001apk) — 功能原型、社区交互与设备标识思路参考
- [frisk1127/c001apk-Revived](https://github.com/frisk1127/c001apk-Revived) — 协议行为、风控规避逻辑与页面模板解析参考
- [Mora-han/coolapk-for-mac](https://github.com/Mora-han/coolapk-for-mac) — 纯 Swift 酷安协议层设计与请求签名参考
- [bggRGjQaUbCoE/c001apk-flutter](https://github.com/bggRGjQaUbCoE/c001apk-flutter) — 上游开源项目与卡片结构参考

---

## 功能特性

### 原生交互与视觉体验
- **iOS 27 Liquid Glass 界面**：基于系统原生 `TabView`（含独立 `.search` 搜索入口与 iPad 自适应侧栏）、`NavigationStack` 与 `GlassEffectContainer` 独立悬浮胶囊分页条，克制搭配页面缩放转场（Zoom Transition）。
- **深色模式与 OLED 纯黑支持**：提供独立深色层级表面对比度与可选 **OLED 纯黑深色背景**开关。
- **动态卡叠封面与堆叠图组**：支持水平堆叠图片卡片滑动、长按原地浮起菜单、点按无损放大查看。

### 完整社区浏览与互动
- **首页多分类与可定制标签**：动态、热门、话题、数码、酷图、应用、头条等全分类支持，子分类切换与列表/页内排序无缝生效。
- **关注流与本机关注**：全部合并时间线、关注用户、关注话题，支持游客与登录用户共用的**本机悄悄关注**与云端关注区分。
- **刷动态（SwipeDeck）**：全屏图文动态卡片左右滑动浏览、作者头像点击跳转主页并支持转场动画。
- **话题 / 数码产品 / 应用 / 看看号 / 收藏夹 / 通用模板页**：
  - 统一实体顶部卡片与子分类条架构，纵向滚动时顶部卡片平滑收起并融入导航栏。
  - 动态提取服务端 `sortSelectCard`（如讨论默认/最新/热度、机主/好评/差评）至右上角原生菜单，支持页内无跳转切换排序。
- **全类型动态与长文详情**：
  - 支持普通动态、图文长文、**问答（问题详情分页回答排序 + 回答卡片直达原问题）**、投票展示、二手交易链接/价格、热评预览、楼中楼详情（页内独立看图不退出弹层）、点赞/转发列表页内连续跳转。
  - 支持列表摘要首屏零闪烁进入详情页，并基于会话缓存减少重复请求与重复完整性校验。
- **发动态 / 回复 / 转发与私信**：
  - 支持多图上传、官方表情面板、`@用户` 与 `#话题#` 选择；支持私信聊天与图片发送。
- **全屏看图器（MediaViewer）**：
  - 支持 **HDR 高动态范围** 与 SDR 切换、**Live Photo 实况图片播放与原件保存**，兼容图像 EXIF 方向信息。
- **离线导出与本地过滤**：
  - 支持帖子/文章导出为 Markdown 或图片 Base64 内嵌离线 HTML。
  - 内置本机内容过滤规则、自动图片磁盘缓存上限清理机制。

### 账号、风控与协议层
- **多账号 Keychain 管理 & 游客模式**：支持网页登录 cookie 捕获、人机验证 WebView 放行并阻断外部 App 跳转。
- **数盟设备标识与协议参数**：支持 `ShuzlmID` 自动获取、官方信息块导入以及协议参数可视化查看。

---

## 项目结构

```text
swift-c001apk/
├── project.yml                      # XcodeGen 工程配置
├── Packages/CoolapkKit/             # 纯 Swift 6 协议、模型与 HTML 解析核心包
│   ├── Sources/CoolapkKit/
│   │   ├── Auth/                    # 凭证、令牌签名与设备标识构造
│   │   ├── Content/                 # 酷安 HTML 富文本、表情与链接解析
│   │   ├── Models/                  # Feed、问答、数码产品、社交与消息模型
│   │   └── Network/                 # API 客户端与服务端卡片模板映射
│   └── Tests/CoolapkKitTests/       # 协议解析与身份签名单元测试
└── C001APK/                         # iOS 27 SwiftUI 客户端主工程
    ├── App/                         # 应用入口、路由状态与根导航容器
    ├── Components/                  # 通用动态卡片、堆叠图组、胶囊导航与媒体网格
    ├── Services/                    # 图片缓存管线、设置持久化、过滤与更新检查
    └── Features/                    # 首页、关注、刷动态、动态详情、消息、个人主页等模块
```

---

## 构建与测试

### 环境要求
- macOS + Xcode 27+ (iOS 27 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（本地生成 `.xcodeproj`）

### 本地构建与单元测试

```bash
# 运行 CoolapkKit 核心包单元测试
swift test --package-path Packages/CoolapkKit

# 生成 Xcode 工程并打开
xcodegen generate
open C001APK.xcodeproj
```

### 云端构建（GitHub Actions）

仓库内置 [`.github/workflows/build.yml`](.github/workflows/build.yml)：
1. 自动运行 `CoolapkKit` 单元测试（`swift test`）。
2. 通过 XcodeGen 生成工程并编译 `Release` 真机归档。
3. 导出未签名安装包 `C001APK-iOS27-unsigned.ipa` 与 SHA-256 校验文件并上传至 Actions Artifacts。

---

## 免责声明与开源协议

- 本项目仅供学习、研究与个人交流使用，与酷安官方（Coolapk）无任何隶属或授权关系。
- 请勿将本项目用于任何违反酷安服务条款或法律法规的用途。
- 项目核心实现遵循 **GNU AGPL v3** 开源精神构建；如对代码进行了修改与二次分发，请保留原作者与参考项目署名并同样以开源形式发布。
