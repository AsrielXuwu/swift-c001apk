# C001APK iOS 原生移植架构与功能设计文档

- **日期**：2026-11-26
- **目标平台**：iOS 27.0+（iPhone & iPad 自适应），Xcode 27 SDK
- **UI 规范基准**：[iOS 27 & Xcode 27 UI 设计规范](../../design/iOS27-UI-Design-Spec.md)
- **参考来源**：
  - 功能全集参考：`TG-Twilight/c001apk`（Flutter）
  - Swift 协议与模型参考：`Mora-han/coolapk-for-mac`（SwiftUI + `CoolapkKit`）

---

## 1. 设计目标与非目标

### 目标
1. 100% 移植 `TG-Twilight/c001apk` 的核心浏览、社交、账号、设备协议、媒体（HDR / Live Photo）、本地内容过滤、内容导出、私信与通知功能至原生 iOS 27 SwiftUI。
2. 借助 `Mora-han/coolapk-for-mac` 已验证的纯 Swift 酷安协议层（`CoolapkToken v1/v2/v3`、`BCrypt`、`API` 模型体系），重构并扩充为完全跨平台（iOS 27 / macOS 测试兼容）的 SwiftPM 模块，支持离线单元测试。
3. 严守 Apple iOS 27 Liquid Glass 设计规范，无冗余自定义控件与视觉噪点，保持 120Hz 丝滑滚动与完整异步解耦。
4. 在无本地 macOS 环境下，通过 `XcodeGen` + GitHub Actions（`xcode-27` runner）一次通过编译、核心库单测并输出未签名 `.ipa`（供自签安装）。

### 非目标
- 不保留 Flutter 跨平台抽象及 Android 专属功能（如本地 APK 安装更新检测、Android App Links）。
- 不引入第三方重型 UI/网络库（全栈使用 Swift 标准库 + `Foundation` / `CryptoKit` / `SwiftUI` / `WebKit` / `PhotosUI` / `ImageIO` / `SwiftData` 或轻量 JSON 本地存储）。

---

## 2. 架构方案对比与选型

| 方案 | 描述 | 优缺点 | 结论 |
| --- | --- | --- | --- |
| **方案 A：单 Target 扁平工程** | 所有网络、模型、持久化、UI 放在一个 Xcode App Target | 初期少建几个 `Package.swift`，但无 Mac 时核心算法与模型很难用 `swift test` 独立测试，UI 与网络边界易耦合 | ❌ 放弃 |
| **方案 B：三层模块化架构（推荐）** | `Packages/CoolapkKit`（纯 Swift 协议/加密/解析/导出/过滤核心，零 UI 依赖）+ `App` 层（iOS 27 SwiftUI + Keychain/磁盘缓存/PhotosUI/WKWebView） | 网络与业务逻辑完全脱离 UI、严格异步 `actor` 隔离；Core 算法（Token、HTML 解析、内容过滤、Markdown/HTML 导出、数盟编解码）可在 CI 直接跑 `swift test` 强验证；`XcodeGen` 管理工程零漂移 | ✅ **采用** |
| **方案 C：引入大量外部 SPM 依赖** | 引入 Alamofire、Kingfisher、SwiftSoup 等第三方库 | 增加 CI 网络拉取失败风险、Swift 6 / Xcode 27 并发兼容隐患与编译时长 | ❌ 放弃（零第三方依赖） |

---

## 3. 模块划分与核心职责

```text
swift-c001apk/
├── project.yml                         # XcodeGen 工程清单（iOS 27.0+）
├── .github/workflows/build.yml         # xcode-27 CI：swift test + xcodebuild 未签名 IPA
├── docs/
│   ├── design/iOS27-UI-Design-Spec.md  # iOS 27 UI 与液态玻璃规范
│   └── superpowers/specs/...           # 本架构设计文档
├── Packages/
│   └── CoolapkKit/                     # 纯 SwiftPM 核心包（无 UIKit/AppKit 硬依赖）
│       ├── Package.swift               # swift-tools-version: 6.2, iOS 27 / macOS 测试兼容
│       ├── Sources/CoolapkKit/
│       │   ├── Auth/
│       │   │   ├── BlowfishTables.swift
│       │   │   ├── BCrypt.swift
│       │   │   ├── CoolapkToken.swift  # v1/v2/v3 token & X-App-Device
│       │   │   ├── TokenTableV3.swift
│       │   │   ├── SzlmDuidClient.swift# 数盟 DUID 编解码与主动获取协议
│       │   │   └── OfficialDeviceIdentity.swift # 官方“复制 OAID”文本解析验证
│       │   ├── Network/
│       │   │   ├── CoolapkClient.swift # actor 并发隔离、Cookie/validate 凭证、567/403 风控识别、multipart/OSS
│       │   │   ├── API.swift           # 全量接口封装（信息流/详情/评论/私信/通知/搜索/发布/互动/发现）
│       │   │   ├── APIError.swift      # 含 captchaChallenge(url/token) 结构化错误
│       │   │   └── JSON.swift          # 容错弱类型 JSON 包装（Sendable）
│       │   ├── Models/
│       │   │   ├── FeedModels.swift    # FeedItem, ReplyItem, FeedArticlePart, Vote/Question, MediaItem(HDR/Live)
│       │   │   ├── SocialModels.swift  # UserProfile, UserBrief, TopicItem, ProductItem, AppItem, DyhItem, CollectionItem, EventItem
│       │   │   ├── MessageModels.swift # NotificationBadge, NotificationItem, MessageThread, ChatMessage
│       │   │   ├── HomeTabConfig.swift # 首页 Tab 自定义顺序/显隐配置
│       │   │   └── AccountModels.swift # SavedAccount（多账号快照模型）
│       │   ├── Content/
│       │   │   ├── FeedHTMLParser.swift# 酷安 HTML -> 跨平台 RichTextNode / Markdown / 纯文本
│       │   │   ├── EmojiCatalog.swift  # 官方表情名映射表
│       │   │   ├── ContentFilterEngine.swift # 标准/严格/作者/话题/文本距离匹配/个人规则引擎
│       │   │   ├── BuiltinFilterRules.swift  # 内置过滤规则集与订阅 JSON 解析校验
│       │   │   └── ContentExport.swift # Markdown 与离线内嵌 Base64 HTML 导出构建器
│       └── Tests/CoolapkKitTests/      # 完整离线单元测试（Token、JSON、过滤、导出、数盟编解码）
└── C001APK/                            # iOS 27 原生 App Target
    ├── App/
    │   ├── C001APKApp.swift            # 入口、全局状态注入、深浅色与强调色设置
    │   ├── AppState.swift              # @MainActor @Observable 全局会话/多账号/角标/设置/路由中心
    │   ├── AppRouter.swift             # 统一站内路由（coolmarket://, /feed/, /u/, /t/, /product/, /apk/, /dyh/, /collection/, /event/, /page）
    │   └── RootTabView.swift           # iOS 27 原生 5-Tab + iPad 自适应分栏
    ├── Services/
    │   ├── AccountStore.swift          # Keychain 安全存储多账号 Token + 游客模式 + sessionGeneration
    │   ├── SettingsStore.swift         # AppStorage / JSON 偏好持久化
    │   ├── LocalFollowStore.swift      # 本机关注 / 悄悄关注持久化
    │   ├── BlacklistStore.swift        # 用户/话题黑名单 + ContentFilterService 订阅更新
    │   ├── HistoryAndFavStore.swift    # 本机浏览历史与本地收藏（支持游客）
    │   ├── ImagePipeline.swift         # actor 磁盘+内存缓存 + ImageIO 降采样 + HDR/Live Photo 媒体下载器
    │   ├── ExportCoordinator.swift     # 离线 HTML 图片抓取、编码、UIActivityViewController / Files 导出
    │   └── RichTextRenderer.swift      # 富文本 AttributedString + 缓存 + 表情图文混排
    ├── Features/
    │   ├── Onboarding/                 # 首次使用引导（隐私说明、外观/屏蔽档位/发布偏好、可选数盟获取）
    │   ├── Home/                       # 首页频道、动态流、所有卡片视图（轮播/图标/榜单/商品/酷图/应用）
    │   ├── Follow/                     # 关注流（全部/关注用户/话题/本地悄悄关注）
    │   ├── Messages/                   # 通知中心 + 私信会话列表 + ChatView（发送文字/图片/重试/删除）
    │   ├── FeedDetail/                 # 动态/图文长文详情 + 评论/置顶/折叠酷币/楼中楼/点赞转发清单/发布回复
    │   ├── Compose/                    # 发动态 / 转发 / 评论编辑器（表情面板、相册选图上传、@用户、#话题#）
    │   ├── Discover/                   # 专题/轮播页、话题、数码产品、应用详情、看看号、活动、收藏夹、酷图瀑布流
    │   ├── Search/                     # iOS 27 Search Tab、热搜、历史、联想、分类结果
    │   ├── Profile/                    # 我的/他人主页、粉丝/关注列表、账号管理、本地收藏、历史记录
    │   ├── Auth/                       # 账密登录（含图形验证码）+ WKWebView 网页登录 + 验证码放行 Sheet
    │   ├── MediaViewer/                # 全屏看图（捏合缩放、HDR 动态范围开关、Live Photo 播放与相册原件保存）
    │   └── Settings/                   # 分组设置、外观、阅读、媒体、内容屏蔽管理、黑名单、数盟设备标识、协议参数、缓存清理、关于与版本检查
    └── Resources/
        ├── Emoji/                      # 来自 coolapk-for-mac 的官方酷安表情 PNG 资源
        ├── Assets.xcassets/            # AppIcon 与品牌强调色
        └── Info.plist                  # 相册写入权限提示（NSPhotoLibraryAddUsageDescription）等
```

---

## 4. `TG-Twilight/c001apk` 全功能移植清单

| 功能模块 | `c001apk` 原有能力 | iOS 27 原生实现方式 |
| --- | --- | --- |
| **核心信息流与首页 Tab** | 自定义首页 Tab 顺序/显隐；推荐(`indexV8`)、头条(`headline`)、热门、话题、数码、酷图、应用；轮播/图标网格/榜单/商品/直播/胶囊条等卡片 | `HomeTabConfiguration` + `API.homeFeed/headlineFeed/pageFeed/appIndex/coolPic`；支持下拉刷新、分批加载、双击回顶 |
| **关注与悄悄关注** | 线上关注人 + 关注话题合并流；本机“悄悄关注”（长按用户主页关注按钮加入，游客可用本机关注） | `FollowView` 分段切换；`LocalFollowStore` 独立存储本机名单与管理页 |
| **动态/长文详情与评论** | 正文/长文分段/转发/问答/投票；评论排序(`lastupdate_desc`/`dateline_desc`/`popular`)、只看楼主、置顶/取消置顶、删除、酷币表情自动折叠、楼中楼、点赞/转发列表 | `FeedDetailView` + `ReplyThreadSheet` + `DisclosureGroup` 酷币折叠 + `EngagementListView` |
| **发帖与评论** | 发动态（文字+多图上传）、转发动态、回复动态/评论、表情面板、`@用户` 与 `#话题#` 搜索插入 | `ComposeSheet`（`PhotosPicker` 选图 + 压缩上传 + 官方表情网格键盘 + `@`/`#` 自动联想） |
| **通知与私信聊天** | 未读角标轮询；回复/赞/@/粉丝通知；私信会话列表；聊天记录、发文字、发图（OSS 准备与上传）、发送中/失败重试、撤回/删除、查看大图（`/v6/message/showImage` 302 重定向解析） | `MessagesView` + `ChatThreadView`（原生底部输入栏 + 异步发送队列 + 删除/重发菜单） |
| **发现与垂类页** | 话题(`topic`)、数码(`product`)、应用(`apk`)、看看号(`dyh`)、收藏夹(`collection`)、活动(`event`)、专题(`carousel/page`)、酷图(`coolpic`) | 统一 `AppRoute` 枚举驱动 `NavigationStack` 路由推送 |
| **搜索** | 热搜词、本地搜索历史、联想词、全站分类搜索（动态/用户/话题/应用/看看号） | iOS 27 `TabRole.search` 原生搜索页 + `0.35s` 防抖联想 + 分段结果 |
| **多账号与登录/风控** | 账密登录（含图形验证码与 hash）、网页登录抓 Cookie、多账号切换、游客模式、会话代际(`sessionGeneration`)隔离、403/人机验证 WebView 放行（缓存 `validate` proof） | `Keychain` 存储凭证、`WKWebView` 监听登录与风控放行 Cookie、切换账号自动取消旧请求并重置视图状态 |
| **HDR 与 Live Photo** | 识别 HDR/实况素材、大图支持 HDR 显示与“我不想看 HDR”开关、实况自动播一次/手动循环、保存原件 | `Image.dynamicRange(.high/.standard)` + `PHLivePhotoView` + `PHPhotoLibrary` 组合写入实况原件 |
| **帖子/文章保存导出** | 抓取最多 3 条置顶/热门评论（排除黑名单与过滤项），导出 `.md` 或内嵌 Base64 图片的离线 `.html`，缺失图片提示确认 | 纯 Swift `ContentExport` + `ExportCoordinator` 后台并发抓取图片并校验解码，唤起系统 `ShareLink` / 文件导出 |
| **内容屏蔽（屏蔽傻逼内容）** | 默认关闭；标准/严格两档；作者/话题/文本距离共现匹配/个人规则；订阅更新（GitHub rules.json）；静默过滤列表、详情页支持例外与临时查看；用户与话题黑名单 | `ContentFilterEngine`（可单元测试）+ `BlacklistStore` + 设置页完整规则管理 UI |
| **设备标识与协议参数** | 主动获取数盟 ID（`auni.telecome.cn` 编解码与频率冷却限制）、粘贴解析官方酷安 5 次点击复制的 `ShuzlmID:`、自定义协议参数（UA/Version/Code/Device） | `SzlmDuidClient` + `OfficialDeviceIdentity` + `DeviceIdentityView` + `ProtocolParamsView` |
| **设置、历史、收藏、引导** | 首次使用引导、本地浏览历史开关与列表、本地/账号收藏、外观主题色与深浅色、阅读字号缩放、媒体自动加载策略、缓存大小统计与清理、GitHub Release 版本检查 | 全套原生 `Form` / `List(.insetGrouped)` 设置页与异步缓存清理 |

---

## 5. 异步解耦与并发安全设计

1. **`CoolapkClient`（`actor`）**：管理 `URLSession`（禁用系统缓存以防 Token/Cookie 冲突）、设备码、Token v3 20 分钟缓存、`validate` 验证码凭证、会话代际（`sessionGeneration`）。所有请求在后台执行，支持自动重签一次（针对 1005 过期）。
2. **UI 状态隔离（`@MainActor @Observable`）**：每个列表/详情持有一个轻量 Controller/ViewModel，分页请求使用 `Task` 句柄，视图消失或切换账号时自动 `cancel()`；数据映射与富文本解析先在后台构造好不可变模型再交付主线程刷新。
3. **图片与内存管理**：`ImagePipeline`（`actor`）限制内存缓存上限（例如 120MB）与磁盘缓存上限（500MB），列表单元格根据显示尺寸用 `ImageIO` 降采样，监听 `UIApplication.didReceiveMemoryWarningNotification` 自动释放内存缓存与 `RichTextRenderer` 缓存。

---

## 6. GitHub Actions 无 Mac 编译方案（`xcode-27`）

- **Workflow 文件**：`.github/workflows/build.yml`
- **Runner**：`xcode-27`
- **构建流程**：
  1. `actions/checkout` 检出代码。
  2. 运行 `CoolapkKit` 纯 Swift 单元测试：`swift test --package-path Packages/CoolapkKit`。
  3. 检查/安装 `xcodegen`（如 runner 未预装则通过 `brew install xcodegen`），执行 `xcodegen generate` 生成 `C001APK.xcodeproj`。
  4. 执行真机无签名构建：
     ```bash
     xcodebuild build \
       -project C001APK.xcodeproj \
       -scheme C001APK \
       -configuration Release \
       -destination 'generic/platform=iOS' \
       -derivedDataPath build/DerivedData \
       CODE_SIGN_IDENTITY="" \
       CODE_SIGNING_REQUIRED=NO \
       CODE_SIGNING_ALLOWED=NO
     ```
  5. 从 `build/DerivedData/Build/Products/Release-iphoneos/C001APK.app` 组装 `Payload/C001APK.app`，校验 arm64 二进制与 `Info.plist` 存在后压缩为 `C001APK-iOS27-unsigned.ipa`，生成 `.sha256` 并上传为 Workflow Artifact。
