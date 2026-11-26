# C001APK for iOS — iOS 27 & Xcode 27 UI 设计规范

> 本文档为本项目所有界面与交互的强制性设计基准。在编写任何 SwiftUI 视图代码之前，必须严格遵守本规范中的所有层级、材质、排版、组件选型与禁止项。

---

## 1. 设计总则与核心目标

1. **纯净原生（Apple HIG First）**：全面拥抱 Xcode 27 / iOS 27 SDK 原生控件与系统默认行为（`TabView`、`NavigationStack`、`NavigationSplitView`、`List`、`.searchable`、`.toolbar`、`.sheet`、`.confirmationDialog`、`ContentUnavailableView`），**禁止重新发明系统已有控件**。
2. **克制的液态玻璃（Liquid Glass Discipline）**：遵循 Apple iOS 27 液态玻璃规范——**液态玻璃只属于功能/导航控制层（Chrome Layer），绝不进入内容层（Content Layer）**。
3. **社区高可读排版（参考 Telegram iOS / MNGA / minibili）**：
   - 信息流、评论区、设置页以“内容优先、高信噪比、低装饰噪点”为核心。
   - **Telegram iOS**：紧凑清晰的头像/昵称/元数据行、无冗余边框的列表分隔、原生沉浸式图片浏览、干脆的底部输入条与操作栏。
   - **MNGA**：论坛级高密度文本阅读、清晰楼层/引述与楼中楼层级、可调阅读字号、作者标识与简洁过滤入口。
   - **minibili**：克制的品牌色点缀、流畅无卡顿的多图九宫格与视频/实况角标、干净的分段切换器与卡片结构。
4. **零冗余视觉污染**：严禁自定义渐变背景、毛玻璃卡片套娃、自定义悬浮球乱飞、多余的阴影堆叠或自绘导航栏。

---

## 2. iOS 27 液态玻璃（Liquid Glass）使用规范

### 2.1 自动接管的系统层（Zero-Override Zone）

在 Xcode 27 / iOS 27 SDK 下，以下组件由系统自动以 Liquid Glass 渲染，**禁止**添加 `.background(...)`、`.toolbarBackground(.visible, ...)` 或自定义遮罩覆盖其材质：

- 底部 `TabView`（以及 iPadOS `.tabViewStyle(.sidebarAdaptable)` 侧边栏）
- `NavigationStack` 顶部导航栏与大标题折叠过渡
- `.toolbar` 内的 `ToolbarItem` / `ToolbarItemGroup` / `ToolbarOverflowMenu`
- `.searchable` 搜索栏及取消/提交形态变化
- `.sheet` / `.popover` / `.confirmationDialog` / `.alert`

### 2.2 允许显式使用 `.glassEffect` 的极少数场景

仅允许在以下**悬浮控制层**使用系统原生 `.glassEffect()` 与 `GlassEffectContainer`：

| 场景 | 允许的 API | 说明 |
| --- | --- | --- |
| 首页发布主悬浮按钮（仅在允许发布且非“不写东西”模式时） | `.glassEffect(.regular.interactive(), in: .circle)` 或原生 `.toolbar` Primary Action | 建议优先放于右上角或右下角单一安全区锚点，随滚动收起或依托系统工具栏，禁止遮挡正文交互 |
| 全屏看图器顶/底部工具与实况/HDR 切换胶囊 | `GlassEffectContainer` + `.glassEffect(.regular.interactive(), in: .capsule)` | 轻点画面自动显隐，不遮挡图片主体 |
| 轻提示（Toast / 简短状态条） | `.glassEffect(.regular, in: .capsule)` | 顶部或底部短暂浮现 1.8s，不阻塞用户点击 |

### 2.3 严格禁止项（Anti-Patterns）

- ❌ **禁止**在 `List` Row、信息流 `FeedCard`、评论行、设置项背景使用 `.glassEffect()` 或半透明渐变底框（长列表大量实时折射会导致掉帧且破坏层级）。
- ❌ **禁止**在内容区叠加全局壁纸、纹理背景或自定义装饰性渐变色块。
- ❌ **禁止**自绘 TopBar / BottomBar 替代 `NavigationStack` 与 `TabView`。
- ❌ **禁止**对玻璃控件大面积重染色（仅主强调动作使用系统 `.tint(.accentColor)`）。

---

## 3. 色彩与材质系统（Color & Semantic Palette）

完全以 Apple 动态语义色为骨架，仅保留克制的酷安品牌绿色作为功能强调色（AccentColor）：

| 语义角色 | 用途 | 规范取值 |
| --- | --- | --- |
| **Accent / Brand** | 激活态、链接、关注按钮、主操作（支持设置中切换主题色或跟随默认酷安绿） | 默认 `#0FB860`（酷安绿），通过 Asset Catalog `AccentColor` 或 SwiftUI `.tint(...)` 注入，同时支持用户在外观设置切换预设主题色 |
| **Canvas Background** | 页面主画布 | `Color(.systemBackground)`（列表区）/ `Color(.systemGroupedBackground)`（分组设置与卡片容器页） |
| **Secondary Surface** | 嵌套引述块、转发卡片、轻量标签底色 | `Color(.secondarySystemBackground)` / `Color(.secondarySystemGroupedBackground)` |
| **Primary / Secondary Text** | 正文 / 时间、设备小尾巴、计数 | `Color.primary` / `Color.secondary` / `Color(.tertiaryLabel)` |
| **Separator** | 信息流列表与楼层分隔线 | 原生 `Divider()` 或 `List` 默认分隔线（`0.5pt` 系统分隔色） |
| **Semantic Status** | 点赞（红 `Color.pink` 或 `.red`）、收藏（琥珀 `.orange` / `.yellow`）、错误（`.red`） | 仅在激活状态图标与数字上染色，未激活态一律 `.secondary` |

深浅色模式完全依赖系统自动适配，支持设置项覆盖（跟随系统 / 始终浅色 / 始终深色，通过根视图 `.preferredColorScheme(...)` 实现）。

---

## 4. 排版与 Dynamic Type（Typography & Density）

全部采用系统字体（SF Pro / PingFang SC）与语义字号层级，并支持设置中的阅读字号缩放倍率（`0.85x ~ 1.35x`）：

| 层级 | 基准样式 | 用途 | 约束 |
| --- | --- | --- | --- |
| **页面标题** | `.largeTitle` / `.headline`（导航栏内联） | 频道标题、用户昵称 | 系统默认折叠动效 |
| **文章标题** | `.title3.weight(.semibold)` | 图文长文、资讯标题、话题名 | 最多 2–3 行（列表态） |
| **正文主体** | `.body`（默认 `16pt` × 用户字号倍率） | 动态正文、长文段落 | 行距 `4pt`，段落间距 `8pt`，支持表情内联与可点击 `@用户` / `#话题#` / 链接 |
| **次级文本 / 转发引述** | `.subheadline` | 转发原动态内容、摘要、热门热评预览 | 最多 3 行折叠（信息流态） |
| **元数据行** | `.footnote` / `.caption` | 时间、IP 属地、机型小尾巴、点赞/评论/转发计数 | 数字使用 `.monospacedDigit()` 防止点赞瞬间抖动 |
| **微徽章** | `.caption2.weight(.medium)` | 楼主标签、置顶标签、HDR / LIVE 角标 | 胶囊或小圆角矩形，低饱和底色 |

---

## 5. 全局信息架构与导航层级（Navigation & Tabs）

参照 Telegram iOS / MNGA / Apple 原生 App Store 的 5 段式极简底栏，采用 iOS 27 原生 `TabView`：

### 5.1 根级 `TabView` 结构（iPhone 底部液态玻璃 TabBar；iPad 自动适配侧边栏 `.tabViewStyle(.sidebarAdaptable)`）

1. **首页（`Tab("首页", systemImage: "house")`）**
   - 顶部分类：使用原生工具栏 / 滚动边缘下方的紧凑分段胶囊切换（如：推荐 / 头条 / 热榜 / 话题 / 数码 / 酷图 / 应用，支持用户在设置中自定义排序与显隐）。
   - 支持**双击首页 Tab** 或点击顶部栏快速平滑滚回顶部并刷新。
   - 右上角工具栏：`发布动态`（`square.and.pencil`，受“不写东西”设置控制）、`通知中心`（`bell` 或直接集成到消息 Tab，保持零冗余）。
2. **关注（`Tab("关注", systemImage: "person.2")`）**
   - 顶部紧凑来源切换：**全部内容**（关注用户 + 关注话题按时间归并去重）/ **关注用户** / **#关注话题** / **本机悄悄关注**（支持游客模式直接启用本地关注）。
3. **消息（`Tab("消息", systemImage: "bubble.left.and.bubble.right")`）**
   - 原生未读角标 `.badge(unreadCount)`。
   - 顶部分段切换：**私信** / **回复与评论** / **@我的** / **收到的赞** / **新增粉丝**。
   - 点击私信会话进入 Telegram 风格原生聊天页（底部贴合键盘的液态玻璃输入栏 + 发图 + 发送失败重试/删除）。
4. **我的（`Tab("我的", systemImage: "person.crop.circle")`）**
   - 顶部简洁账号卡（已登录显示头像、昵称、Lv 等级经验条、酷安号、获赞/关注/粉丝快捷入口；未登录显示游客态提示与“登录 / 添加账号”入口）。
   - `InsetGrouped` 原生分组列表：
     - 账号切换（多账号管理、游客模式切换）
     - 我的动态 / 我的收藏 / 浏览历史 / 我的点赞
     - 发现入口（看看号订阅、酷图、榜单）
     - 本机关注管理（悄悄关注）
     - 内容屏蔽（“屏蔽傻逼内容”规则管理、用户/话题黑名单）
     - 设置（外观与导航、阅读与评论、图片与媒体、关注、内容屏蔽、浏览与隐私、存储与更新、协议与数盟设备标识、关于）
5. **搜索（`Tab("搜索", systemImage: "magnifyingglass", role: .search)`）**
   - 严格使用 iOS 27 `TabRole.search`，在底栏自动分离为右侧独立的液态玻璃搜索图标，点击直接展开原生 `.searchable` 交互！
   - 搜索前展示：本地搜索历史（支持清空/单删）+ 酷安实时热搜词云/列表。
   - 输入防抖（`0.35s`）联想词，提交后显示原生分栏结果：**综合 / 动态 / 话题 / 用户 / 应用 / 看看号**。

> 注：iPadOS / 横屏大屏分栏阅读模式（`readingMode`：自动 / 开启 / 关闭）：在详情阅读或宽屏下使用原生 `NavigationSplitView`（列表在左/右可切换阅读窗格，正文限制最大阅读宽度 `760pt` 居中显示）。

---

## 6. 核心页面组件规范

### 6.1 信息流卡片（`FeedRowView`）— 简洁无边框列表范式

抛弃厚重的浮雕卡片嵌套，参考 **Telegram / MNGA** 列表规范：
- **表面**：纯系统背景色 + `0.5pt` 极细底部分隔线（分组卡片列表在 `InsetGrouped` 模式下使用系统默认圆角分组；信息流主时间线采用通栏轻量分隔 + 充足内边距 `16pt` 水平 / `12pt` 垂直，消除“盒子套盒子”的视觉疲劳）。
- **四段式纵向结构**：
  1. **作者栏**：`36pt` 圆形头像 + 昵称（`.subheadline.weight(.semibold)`）+ 时间/IP 属地/机型信息（`.caption.foregroundStyle(.secondary)`）+ 右侧紧凑 `...` 原生 `Menu`（收藏、复制链接、导出 Markdown/HTML、临时查看/加入屏蔽、举报/拉黑）。
  2. **正文区**：若含 `messageTitle` 则先显示半粗标题；正文渲染酷安富文本（内联表情 PNG、蓝色可点击 `#话题#`、`@用户`、链接）；超过 6 行或长文在信息流中优雅截断并展示“全文”。
  3. **媒体与关联区（按需出现，最多一种）**：
     - **图片九宫格**：1 张图按原图宽高比自适应（限高防撑爆，右上角极简胶囊标示 `LIVE` / `HDR` / `GIF`）；2–4 张用 2 列；5–9 张用 3 列，`4pt` 间距，`10pt` 连续圆角；超过 9 张在末格显示 `+N`。
     - **转发卡片**：`10pt` 圆角 `.secondarySystemBackground` 轻量底色，含原作者名 + 文本 + 缩略图。
     - **关联实体条**（话题 / 数码产品 / 应用 / 问答 / 投票）：紧凑单行横条（左侧 `40pt` 圆角图标 + 标题/副标题 + 右箭头）。
     - **热评预览（可选）**：单条极简 `.secondarySystemBackground` 引述条（“热评 · 作者：内容”）。
  4. **交互底栏**：左对齐或三等分极简图标+等宽数字（点赞、评论、转发/分享），无多余文字标签，触控热区 `>= 44×36pt`，点击点赞触发 `.sensoryFeedback(.impact(flexibility: .soft), trigger: ...)`。

### 6.2 首页特殊卡片（`HomeCards`）

- **轮播横幅（Carousel）**：`16:9` 或 `2.2:1` 连续圆角 `14pt`，原生 `TabView(.page)` 或横向 `ScrollView(.horizontal)` + `.scrollTargetBehavior(.viewAligned)`，不加多余外框。
- **图标网格 / 横滑（IconGrid / IconScroll）**：标准 `44pt` 圆角图标 + 1 行 `.caption` 标题，不堆砌描述文字。
- **应用 / 产品 / 话题卡**：采用统一原生列表行结构（左侧 `48pt` 图标，右侧标题+评分/热度副标题+轻量操作胶囊）。

### 6.3 动态与图文详情页（`FeedDetailView`）

- 顶部导航栏：作者头像昵称紧凑呈现（随标题滚出主视口后切换显示）+ 关注按钮 + 右上角 `Menu`（保存为 Markdown / 保存为离线 HTML / 浏览器打开 / 复制原文 / 内容屏蔽规则）。
- 正文区域：
  - 普通动态：完整高清图文 + 设备小尾巴 + 发布/修改时间 + 投票组件 / 问答入口 / 点赞用户头像行（点击可看点赞列表与转发列表）。
  - 图文长文（`feedArticle`）：按 `articleParts` 顺序交错渲染文字段落（支持小标题/加粗/链接/表情）与全宽配图。
- 评论区：
  - 置顶分节头部（切换排序：**默认/最新回复 `lastupdate_desc`** / **时间倒序 `dateline_desc`** / **热门 `popular`**，以及 **只看楼主** 开关）。
  - **酷币评论自动折叠**：若开启设置且评论仅包含酷币表情，自动收纳进评论区顶部可展开的 `DisclosureGroup`（“已折叠 N 条酷币表情评论”）。
  - **置顶评论**与普通一级评论：清晰展示“楼主”微徽章、“置顶”微徽章，内嵌最多 2–3 条楼中楼预览及“查看全部 N 条回复 >”，点击进入原生 `.sheet` 或 push 的楼中楼详情页；支持作者置顶/取消置顶评论与删除自己评论。
- 底部交互条：贴合键盘安全区的原生 `.safeAreaInset(edge: .bottom)` 玻璃胶囊条（“写评论…”触发输入框 + 点赞 + 收藏 + 转发）。

### 6.4 沉浸式图片查看器（`MediaViewerView`）

- 全黑画布（`Color.black`），支持左右分页切换（`TabView` 或水平分页 + 缩放冲突手势协调）、双击 1x/2.5x 缩放、捏合自由缩放、下拉手势关闭。
- **HDR 支持**：使用 `ImageIO` / `SwiftUI` `Image.dynamicRange(.high)`（当设置未开启“我不想看 HDR”且设备/图片支持 HDR 时自动启用高动态范围渲染；开启“我不想看 HDR”时强制 `.standard` 显示高清 SDR，原件保存与实况播放不受影响）。
- **Live Photo 实况图片支持**：识别酷安实况图片配对视频 URL（或 HEIC/MOV），使用 `PhotosUI` 原生 `PHLivePhotoView` 渲染并播放（支持进入大图自动播一次、长按播放或点击实况按钮循环播放），支持通过 `PHPhotoLibrary` 将图片 + 视频原件组合保存为相册 Live Photo，或单独保存原图/全部图片/分享。
- 顶部与底部悬浮控制栏：使用 `GlassEffectContainer` 承载极简玻璃按钮（页码 `1 / 9`、关闭、HDR/LIVE 状态切换、保存原件、分享）。

### 6.5 本地内容过滤展示（`ContentFilter`）

- 列表态：**静默过滤**匹配项（不留下空白占位干扰阅读，彻底干净）。
- 用户主动进入某条已命中规则的动态详情或搜索精确结果时：以原生 `ContentUnavailableView` 风格的简洁提示门控展示命中原因（如“已按本地规则隐藏 · 仅本机生效”），提供“临时查看此次内容”与“始终允许此作者/此内容”按钮。

---

## 7. 异步解耦与高性能滚动规范（Performance & Concurrency）

1. **严禁主线程同步工作**：所有 JSON 解码、X-App-Token（BCrypt + 查找表）、FeedHTML 富文本解析、图片降采样、Markdown/HTML 导出与图片 Base64 内嵌均在后台 `actor` 或 `Task.detached` 执行，UI 层只接收不可变值类型状态（`Sendable` Struct）。
2. **图片流水线性能**：
   - 自研轻量 `ImageCache`（`NSCache` 内存成本限制 + 磁盘缓存目录 + ImageIO 按目标渲染尺寸降采样解码 `CGImageSourceCreateThumbnailAtIndex`），列表缩略图绝不整图解码 4K 原图。
   - **禁止列表项使用 `.glassEffect()`**，确保 ProMotion 120Hz 满帧滚动。
3. **富文本缓存**：`FeedHTMLParser` 将 HTML 转换为 `AttributedString`（带内联表情文本附件），用 `NSCache` 按 `(fontScale, appearance, htmlHash)` 缓存，并在收到内存警告时清理。
4. **状态管理隔离**：使用 Swift Observation（`@Observable` + `@MainActor` ViewModel），网络请求严格绑定 `Task` 生命周期与 `sessionGeneration`（切换账号或退出视图立即自动取消过期请求，防止旧账号数据串写）。
5. **列表结构稳定性**：全部信息流使用 `LazyVStack` + 稳定唯一 `id`（去重后），分页预加载在倒数第 4 条 `onAppear` 时触发并带防重入锁。

---

## 8. 构建与工程规范（Xcode 27 & CI Compliance）

1. **工程生成**：使用 `XcodeGen` (`project.yml`) 描述全部 Target 与本地 SwiftPM 包，严禁手改 `.xcodeproj` 导致合并冲突或引用漂移。
2. **严格并发与编译零警告**：启用 Swift 6 并发检查与 `IPHONEOS_DEPLOYMENT_TARGET = 27.0`，所有模型遵循 `Sendable`，消除平台条件编译噪音（纯 iOS 27）。
3. **CI 输出**：GitHub Actions 在 `xcode-27` runner 上执行 `xcodegen generate` → `swift test`（核心包单测）→ `xcodebuild archive` / `xcodebuild build`（`generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`）→ 打包标准 `Payload/C001APK.app` 生成未签名 `.ipa` 并附带 SHA-256 校验上传至 Artifacts。
