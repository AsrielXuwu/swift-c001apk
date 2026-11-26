# C001APK iOS 27 Native Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port all features of `TG-Twilight/c001apk` to a pure native iOS 27.0+ SwiftUI app (`C001APK`), following `docs/design/iOS27-UI-Design-Spec.md` and building an unsigned `.ipa` via GitHub Actions on `xcode-27`.

**Architecture:** Two-layer modular Swift architecture: `Packages/CoolapkKit` (zero UIKit/AppKit dependencies; all Coolapk API endpoints, `X-App-Token` v1/v2/v3 + `BCrypt`, `SzlmDuidClient`, JSON models, `FeedHTMLParser`, `ContentFilterEngine`, and `ContentExport` Markdown/Offline HTML) + `C001APK` iOS 27 App Target (`@MainActor @Observable` state, `actor`-backed `ImagePipeline` & persistence, native `TabView` / `NavigationStack` / `NavigationSplitView` / Liquid Glass chrome). Generated via `XcodeGen` (`project.yml`).

**Tech Stack:** Swift 6.2, SwiftUI (iOS 27.0+ SDK), SwiftPM, `CryptoKit`, `WebKit`, `PhotosUI`, `ImageIO`, `Security` (Keychain), `XcodeGen`, GitHub Actions (`xcode-27`).

**Spec:**
- `docs/design/iOS27-UI-Design-Spec.md`
- `docs/superpowers/specs/2026-11-26-c001apk-ios-architecture-design.md`

## Global Constraints

- Minimum deployment target: `iOS 27.0` (`IPHONEOS_DEPLOYMENT_TARGET = 27.0`), Xcode 27 SDK, zero `#if os(macOS)` or iOS <27 compatibility clutter.
- Zero third-party SPM/CocoaPods dependencies; only Apple system frameworks + pure Swift implementations.
- UI strictly follows Apple iOS 27 Liquid Glass HIG: **zero** `.glassEffect` inside `List`/`LazyVStack` rows or content backgrounds; system bars (`TabView`, `NavigationStack`, `.searchable`, `.toolbar`, `.sheet`) remain native un-overridden Liquid Glass.
- All networking, token generation, HTML parsing, image decoding/downsampling, filtering, and export packaging run off the main actor; UI consumes immutable `Sendable` models.
- Requests track `sessionGeneration` so account switching immediately drops stale responses and never leaks credentials across sessions.

## Review Focus

1. **Account switching mid-flight:** Switching or logging out while feed/chat requests are in flight must discard stale responses (`sessionGeneration` mismatch) and clear `validate` captcha cookies cleanly.
2. **Coolapk API loosely-typed JSON & error shapes:** Numeric/string IDs (`id` vs `entityId`, Int vs String), `status == 1005` token expiry, `code == 403`, and `err_request_captcha_v2` must map cleanly without crashing or blanking loaded content.
3. **Content Filter rule & exception invariants:** Builtin + subscription + personal rules (`personal.*` namespace isolation, sentence-boundary masking, `allowedAuthorUids` / `allowedContentKeys` exceptions, disabled list kinds) must filter lists silently while allowing temporary viewing in detail.
4. **Offline HTML & Markdown export safety:** HTML special chars must be escaped, `data:image/...;base64,` embedding must enforce per-image (8MB) and total (32MB) caps, and popular comments must exclude blocked UIDs and filter-matched items without mutating live feed models.
5. **Xcode 27 CI buildability without macOS locally:** Every Swift file in `Packages/CoolapkKit` and `C001APK` must avoid missing imports, macOS-only symbols (`NSColor`/`NSImage`/`NSAttributedString` AppKit), and Swift 6 `Sendable`/actor-isolation errors.

---

### Task 1: Initialize Project Scaffolding, Resources & GitHub Actions CI

**Files:**
- Create: `.gitignore`
- Create: `project.yml`
- Create: `.github/workflows/build.yml`
- Create: `C001APK/Resources/Info.plist`
- Create: `C001APK/Resources/Assets.xcassets/Contents.json`
- Create: `C001APK/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `C001APK/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Copy: `C001APK/Resources/Emoji/*.png` (from `coolapk-for-mac/CoolapkForMac/Resources/Emoji`)

- [ ] **Step 1:** Initialize git repository and write `.gitignore` (ignoring `*.xcodeproj`, `build/`, `.build/`, `DerivedData/`, `.DS_Store`).
- [ ] **Step 2:** Copy official Coolapk emoji PNGs into `C001APK/Resources/Emoji/` and create `Assets.xcassets` (`AccentColor` `#0FB860`, `AppIcon` placeholder set) and `Info.plist` (`NSPhotoLibraryAddUsageDescription`, `NSPhotoLibraryUsageDescription`, `UILaunchScreen`).
- [ ] **Step 3:** Create `project.yml` for `XcodeGen` targeting `iOS: "27.0"`, Swift 6.0 / strict concurrency, linking local `Packages/CoolapkKit`, embedding `Resources/Emoji` as folder resource.
- [ ] **Step 4:** Create `.github/workflows/build.yml` using `runs-on: xcode-27` to run `swift test --package-path Packages/CoolapkKit`, `xcodegen generate`, `xcodebuild build` (`generic/platform=iOS`, `CODE_SIGNING_ALLOWED=NO`), package `Payload/C001APK.app` into `C001APK-iOS27-unsigned.ipa`, generate SHA-256, and upload artifact.

---

### Task 2: CoolapkKit — Auth, Crypto, Token v1/v2/v3, SZLM DUID & Captcha Challenge

**Files:**
- Create: `Packages/CoolapkKit/Package.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Auth/BlowfishTables.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Auth/BCrypt.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Auth/TokenTableV3.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Auth/CoolapkToken.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Auth/SzlmDuidClient.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Auth/OfficialDeviceIdentity.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Auth/CaptchaChallenge.swift`
- Test: `Packages/CoolapkKit/Tests/CoolapkKitTests/AuthAndIdentityTests.swift`

**Interfaces:**
- Produces: `BCrypt.hash(password:salt:)`, `CoolapkToken.appTokenV3(deviceCode:timestamp:appCode:)`, `CoolapkToken.makeDeviceCode()`, `SzlmFieldCodec`, `SzlmDuidClient.buildReport(...)`, `SzlmDuidClient.encodeReport(_:)`, `SzlmDuidClient.decodeId(_:)`, `OfficialDeviceIdentity.parse(_:)`, `CaptchaChallenge.fromBody(_:)`.

- [ ] **Step 1:** Create `Package.swift` (`swift-tools-version: 6.2`, `platforms: [.iOS("27.0"), .macOS("15.0")]` so `swift test` runs on macOS runners too, or pure Foundation/CryptoKit).
- [ ] **Step 2:** Implement `BlowfishTables`, `BCrypt`, `TokenTableV3`, `CoolapkToken` (matching `c001apk` cost `04` + `appCode` parameterized v3 token & v1/v2 fallback + device code generation).
- [ ] **Step 3:** Implement `SzlmDuidClient` (zlib + XOR codec, `auni.telecome.cn` / fallback host request, seed validation) and `OfficialDeviceIdentity` (`ShuzlmID:` parser & all-zero guard) and `CaptchaChallenge`.
- [ ] **Step 4:** Write comprehensive unit tests in `AuthAndIdentityTests.swift` covering Token v3 generation, device code encoding, SZLM field codec/XOR/zlib round-trip, all-zero rejection, `OfficialDeviceIdentity.parse`, and `CaptchaChallenge`.

---

### Task 3: CoolapkKit — Networking (`JSON`, `APIError`, `CoolapkClient`, `API`)

**Files:**
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Network/JSON.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Network/APIError.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Network/CoolapkClient.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Network/API.swift`
- Test: `Packages/CoolapkKit/Tests/CoolapkKitTests/JSONAndAPITests.swift`

**Interfaces:**
- Produces: `JSON` (`Sendable`), `APIError`, `CoolapkClient` (`actor` with `sessionGeneration`, protocol params override, `validate` captcha proof, `szlmId`, `request` / `dataList` / `upload` / `ossUploadPrepare` / `aliOSSUpload` / `showMessageImageURL`), `API` (all endpoints from `c001apk` + `coolapk-for-mac`).

- [ ] **Step 1:** Port `JSON` (`Sendable`) with resilient int/double/string/identifier/bool/date coercions.
- [ ] **Step 2:** Implement `CoolapkClient` actor supporting customizable protocol parameters (`versionName`, `versionCode`, `apiVersion`, `sdkInt`, `userAgent`, `deviceCode`, `szlmId`), `sessionGeneration` cancellation guard, automatic v3 token caching/refresh on `1005`, `err_request_captcha_v2` `CaptchaChallenge` extraction, `account.coolapk.com` login requests (hash + captcha + loginByCoolApk), `ossUploadPrepare` + Aliyun OSS PUT signing, and `message/showImage` non-redirecting 302 URL resolution.
- [ ] **Step 3:** Implement `API` covering all endpoints: `main/init`, `main/indexV8`, `main/headline`, `page/dataList`, `feed/detail`, `feed/replyList` (`lastupdate_desc`, `dateline_desc`, `popular`, `fromFeedAuthor`), `feed/like*`, `feed/collect*`, `feed/reply`, `feed/createFeed`, `feed/delete*`, `feed/addReplyTopToFeed`, `feed/cancelReplyTopFromFeed`, `feed/uploadImage`, `user/profile`, `user/space`, `user/feedList`, `user/followList`, `user/fansList`, `user/follow`, `user/unfollow`, `user/followTagList`, `user/likeList`, `user/recentHistoryList`, `user/hitHistoryList`, `user/dyhSubscribe`, `search`, `search/suggestSearchWordsNew`, `feed/searchTag`, `user/search`, `topic/*`, `product/*`, `apk/*`, `dyh/*`, `dyhArticle/list`, `collection/*`, `question/answerList`, `vote/commentList`, `event/detail`, `picture/list`, `notification/*`, `message/list`, `message/chat`, `message/send`, `message/delete`, `account/checkLoginInfo`, `account/loadConfig`, `feed/likeList`, `feed/forwardList`, `feed/changeHistoryList`.
- [ ] **Step 4:** Write tests in `JSONAndAPITests.swift` for `JSON` decoding, `API.pageTarget`, `API.rows(from:)` card template parsing, and `CoolapkClient` URL/form building.

---

### Task 4: CoolapkKit — Domain Models (`FeedModels`, `SocialModels`, `MessageModels`, `HomeTabConfig`)

**Files:**
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Models/FeedModels.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Models/SocialModels.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Models/MessageModels.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Models/HomeTabConfig.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Models/AccountModels.swift`
- Test: `Packages/CoolapkKit/Tests/CoolapkKitTests/ModelTests.swift`

- [ ] **Step 1:** Define `Sendable`, `Hashable`, `Identifiable` domain structs: `FeedItem` (including `articleParts`, `mediaItems: [FeedMedia]` with `isLivePhoto`/`isHdr`/`videoUrl`/`previewUrl`, `vote`, `question`, `topReplyRows`, `replyRows`, `sourceFeed`), `ReplyItem`, `FeedArticlePart`, `FeedMedia`, `VoteInfo`, `QuestionInfo`.
- [ ] **Step 2:** Define `UserProfile`, `UserBrief`, `TopicItem`, `ProductItem`, `AppItem`, `CollectionItem`, `DyhItem`, `EventItem`, `PearGoods`, `LiveTopic`, `HomeBanner`, `HomeIconLink`, `HomeSection`, `HomeFeedRow`.
- [ ] **Step 3:** Define `NotificationBadge`, `NotificationItem`, `MessageThread`, `ChatMessage`, `HomeTabConfiguration`, `SavedAccount`, `ProtocolParameters`.
- [ ] **Step 4:** Write `ModelTests.swift` testing `FeedItem` JSON parsing (articles, media items, HDR/Live metadata, forwarded feeds, top replies), `HomeTabConfiguration` persistence round-trip, and `NotificationBadge`.

---

### Task 5: CoolapkKit — Content Engines (`FeedHTMLParser`, `ContentFilterEngine`, `ContentExport`)

**Files:**
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Content/EmojiCatalog.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Content/FeedHTMLParser.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Content/ContentFilterRule.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Content/BuiltinFilterRules.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Content/ContentFilterEngine.swift`
- Create: `Packages/CoolapkKit/Sources/CoolapkKit/Content/ContentExport.swift`
- Test: `Packages/CoolapkKit/Tests/CoolapkKitTests/ContentEngineTests.swift`

- [ ] **Step 1:** Implement `FeedHTMLParser` converting Coolapk HTML into structured `RichTextSegment` tokens (text with bold/italic/strike, tappable `FeedLink` enum, inline `[emoji]` tokens) + plain text & Markdown helpers + `CoinReplyDetector` (`isCoinOnlyReply`).
- [ ] **Step 2:** Port `ContentFilterRule`, `FilterRuleSet`, `BuiltinFilterRules`, and `ContentFilterEngine` (visible HTML text extraction, normalization, proximity matching across groups, exception masking, `personal.*` namespace rules, author/topic/content exceptions).
- [ ] **Step 3:** Port `ContentExport` (`ExportDocument` generating Markdown and self-contained offline HTML with `data:image/...;base64,` substitution, up to 3 pinned-first popular comments, escaped HTML, and safe filenames).
- [ ] **Step 4:** Write `ContentEngineTests.swift` covering HTML parsing & `FeedLink` resolution, coin-only reply detection, content filter standard vs strict & exceptions & distance matching, and Markdown/HTML export escaping & comment selection.

---

### Task 6: App Core Services, Persistence, ImagePipeline & Routing

**Files:**
- Create: `C001APK/App/AppState.swift`
- Create: `C001APK/App/AppRouter.swift`
- Create: `C001APK/Services/AccountStore.swift`
- Create: `C001APK/Services/SettingsStore.swift`
- Create: `C001APK/Services/LocalFollowStore.swift`
- Create: `C001APK/Services/BlacklistStore.swift`
- Create: `C001APK/Services/ContentFilterService.swift`
- Create: `C001APK/Services/HistoryAndFavStore.swift`
- Create: `C001APK/Services/ImagePipeline.swift`
- Create: `C001APK/Services/RichTextRenderer.swift`
- Create: `C001APK/Services/ExportCoordinator.swift`
- Create: `C001APK/Services/UpdateChecker.swift`

- [ ] **Step 1:** Implement `AccountStore` (Keychain token vault + UserDefaults account metadata + multi-account switch / guest mode / session expiration).
- [ ] **Step 2:** Implement `SettingsStore`, `LocalFollowStore`, `BlacklistStore`, `ContentFilterService` (including GitHub `rules.json` subscription refresh with size caps), and `HistoryAndFavStore` (local browsing history + local bookmarks).
- [ ] **Step 3:** Implement `ImagePipeline` actor (memory `NSCache` + disk cache, `ImageIO` thumbnail downsampling, HDR gain-map detection, Live Photo paired asset download, memory-warning purge, cache byte-size calculation & clear).
- [ ] **Step 4:** Implement `RichTextRenderer` (UIKit-backed `NSAttributedString` / SwiftUI `AttributedString` with `NSTextAttachment` emoji PNGs + `NSCache` + `EmojiBundleLoader`), `ExportCoordinator` (image fetching with 8MB/32MB limits, UI decode verification, Share sheet), `UpdateChecker` (GitHub releases API), `AppRouter`, and `AppState`.

---

### Task 7: iOS 27 UI Foundations & Shared Components

**Files:**
- Create: `C001APK/App/C001APKApp.swift`
- Create: `C001APK/App/RootTabView.swift`
- Create: `C001APK/Components/RemoteImageView.swift`
- Create: `C001APK/Components/RichTextView.swift`
- Create: `C001APK/Components/FeedRowView.swift`
- Create: `C001APK/Components/MediaGridView.swift`
- Create: `C001APK/Components/HomeCardViews.swift`
- Create: `C001APK/Components/ContentFilterGateView.swift`
- Create: `C001APK/Components/Formatting.swift`

- [ ] **Step 1:** Implement `RootTabView` with iOS 27 `TabView` (5 tabs: 首页, 关注, 消息, 我的, `Tab(role: .search)` 搜索), `.tabViewStyle(.sidebarAdaptable)`, `.tabBarMinimizeBehavior(.onScrollDown)`, global toast overlay (`glassEffect`), sheets (Onboarding, Login, Captcha, Compose), and full-screen cover (MediaViewer).
- [ ] **Step 2:** Implement `RemoteImageView` (async pipeline image loading with optional target size & HDR dynamic range control) and `MediaGridView` (1-image adaptive ratio, 2/3-column grid, `GIF`/`长图`/`HDR`/`LIVE` minimal badges).
- [ ] **Step 3:** Implement `RichTextView` (clickable `@user` / `#topic#` / URLs via `FeedLink` routing, inline emoji support, Dynamic Type + user font-scale multiplier).
- [ ] **Step 4:** Implement `FeedRowView` (clean borderless Telegram/MNGA-style 4-part row, context menu, sensory feedback on like, forwarded card, target entity strip, hot-reply preview) and `HomeCardViews` (carousel, icon grid/scroll, section title, product/app/topic/goods/live/link-bar rows) and `ContentFilterGateView`.

---

### Task 8: Primary Tabs — Home, Follow, Messages & Chat, Search

**Files:**
- Create: `C001APK/Features/Home/HomeView.swift`
- Create: `C001APK/Features/Home/HomeFeedViewModel.swift`
- Create: `C001APK/Features/Follow/FollowView.swift`
- Create: `C001APK/Features/Follow/FollowViewModel.swift`
- Create: `C001APK/Features/Messages/MessagesView.swift`
- Create: `C001APK/Features/Messages/ChatThreadView.swift`
- Create: `C001APK/Features/Messages/MessagesViewModel.swift`
- Create: `C001APK/Features/Search/SearchView.swift`
- Create: `C001APK/Features/Search/SearchViewModel.swift`

- [ ] **Step 1:** Implement `HomeView` & `HomeFeedViewModel` (customizable category picker from `HomeTabConfiguration`, `indexV8`/`headline`/`pageFeed`/`appIndex`/`coolPic` sources, pull-to-refresh, infinite scroll, tap-tab scroll-to-top, toolbar compose & notification shortcuts).
- [ ] **Step 2:** Implement `FollowView` & `FollowViewModel` (All merged timeline deduped by ID & sorted by date, Followed Users, Followed Topics bar, Local/Silent Follow feed with guest support).
- [ ] **Step 3:** Implement `MessagesView`, `MessagesViewModel`, and `ChatThreadView` (segmented Inbox: 私信 / 回复 / @我 / 赞 / 粉丝; Telegram-style chat bubbles with 302 message image resolution, OSS chat image upload, optimistic delivery state + retry/discard, delete message).
- [ ] **Step 4:** Implement `SearchView` & `SearchViewModel` (bound to iOS 27 `TabRole.search`, search history, hot search words, `0.35s` debounced suggestions, segmented results: 综合 / 动态 / 话题 / 用户 / 应用 / 看看号).

---

### Task 9: Detail, Compose & Media Viewer (HDR + Live Photo + Export)

**Files:**
- Create: `C001APK/Features/FeedDetail/FeedDetailView.swift`
- Create: `C001APK/Features/FeedDetail/FeedDetailViewModel.swift`
- Create: `C001APK/Features/FeedDetail/ReplyThreadSheet.swift`
- Create: `C001APK/Features/FeedDetail/EngagementListView.swift`
- Create: `C001APK/Features/Compose/ComposeSheet.swift`
- Create: `C001APK/Features/Compose/ComposeViewModel.swift`
- Create: `C001APK/Features/Compose/EmojiPickerView.swift`
- Create: `C001APK/Features/MediaViewer/MediaViewerView.swift`
- Create: `C001APK/Features/MediaViewer/LivePhotoRepresentable.swift`

- [ ] **Step 1:** Implement `FeedDetailView` & `FeedDetailViewModel` (supports iPad/landscape split reading pane when enabled; article interleaved parts; poll/question sections; reply sorting & author-only filter; coin-only reply folding `DisclosureGroup`; author pin/unpin & delete reply; content filter gate; Markdown/Offline HTML export flow with warning confirmation & `ShareSheet`).
- [ ] **Step 2:** Implement `ReplyThreadSheet` (nested reply-to-reply pagination + quick reply bar) and `EngagementListView` (likes list, forwards list, edit history).
- [ ] **Step 3:** Implement `ComposeSheet` (new feed, forward feed, reply to feed/comment; `PhotosPicker` multi-image upload; bundled emoji grid picker; `@user` & `#topic#` search sheets).
- [ ] **Step 4:** Implement `MediaViewerView` & `LivePhotoRepresentable` (`PHLivePhotoView` auto-play once + manual loop toggle, `Image.dynamicRange(.high/.standard)` honoring "我不想看HDR", pinch/double-tap zoom, pull-down dismiss, `GlassEffectContainer` floating controls, save photo / save Live Photo / save all / share / copy URL).

---

### Task 10: Discover, Auth, Profile, Onboarding & Settings

**Files:**
- Create: `C001APK/Features/Discover/DiscoverViews.swift` (Topic, Product, App, Dyh, Collection, Event, Carousel/Page, CoolPic)
- Create: `C001APK/Features/Auth/LoginSheet.swift`
- Create: `C001APK/Features/Auth/WebLoginSheet.swift`
- Create: `C001APK/Features/Auth/CaptchaWebViewSheet.swift`
- Create: `C001APK/Features/Profile/ProfileTabView.swift`
- Create: `C001APK/Features/Profile/UserDetailView.swift`
- Create: `C001APK/Features/Profile/AccountsView.swift`
- Create: `C001APK/Features/Profile/HistoryAndFavoritesViews.swift`
- Create: `C001APK/Features/Profile/LocalFollowListView.swift`
- Create: `C001APK/Features/Onboarding/OnboardingView.swift`
- Create: `C001APK/Features/Settings/SettingsView.swift`
- Create: `C001APK/Features/Settings/ContentFilterSettingsView.swift`
- Create: `C001APK/Features/Settings/BlacklistView.swift`
- Create: `C001APK/Features/Settings/DeviceIdentityView.swift`
- Create: `C001APK/Features/Settings/ProtocolParamsView.swift`
- Create: `C001APK/Features/Settings/AboutView.swift`

- [ ] **Step 1:** Implement all `DiscoverViews` (`TopicDetailView`, `ProductDetailView`, `AppDetailView`, `DyhDetailView`, `CollectionDetailView`, `EventDetailView`, `PageFeedView`, `CoolPicView`).
- [ ] **Step 2:** Implement `Auth` flows (`LoginSheet` password + image captcha + `requestHash`, `WebLoginSheet` `WKWebView` cookie capture, `CaptchaWebViewSheet` NetEase NECaptcha embed JS bridge returning `validate` proof).
- [ ] **Step 3:** Implement `ProfileTabView`, `UserDetailView` (with long-press follow for Secret Follow / guest local follow), `AccountsView` (multi-account switch/add/remove/guest), `HistoryAndFavoritesViews`, `LocalFollowListView`, and `OnboardingView`.
- [ ] **Step 4:** Implement complete `SettingsView` (`InsetGrouped` 8 categories + adaptive split on iPad) including Appearance (theme accent color, light/dark, home tabs editor, hide publish button), Reading (split reading mode, font scale, show emoji, fold coin replies), Media (auto-load policy, disable HDR), Follow (secret follow toggle & manager), Filter ("屏蔽傻逼内容" level/lists/subscription/personal rules/exceptions + user/topic blacklists), Privacy (history, open in browser), Storage & Updates (cache size/clear, GitHub release update check), Protocol & Device (`DeviceIdentityView` with SZLM DUID auto-fetch + `ShuzlmID` paste import + `ProtocolParamsView`), and `AboutView`.

---

### Task 11: Verification, Static Audit & GitHub Push Readiness

- [ ] **Step 1:** Run all cross-platform unit tests in `Packages/CoolapkKit` (or verify Swift syntax/logic thoroughly if running on Windows without Swift toolchain; check whether `swift` or GitHub Actions is needed).
- [ ] **Step 2:** Audit every Swift file for iOS 27 API correctness, zero `AppKit` imports, zero missing `Sendable` conformances, zero custom background/glass violations per `iOS27-UI-Design-Spec.md`, and complete `project.yml` + `.github/workflows/build.yml` consistency.
- [ ] **Step 3:** Commit clean git history ready for push to GitHub Actions compilation.
