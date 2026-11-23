# Changelog

## [1.4.0] - 2026-11-23

### 变更
- **转型为纯净本地 TXT / EPUB 阅读器**：全面移除书源管理、书城发现、多源聚合搜索、换源、在线章节批量下载、JS 规则解析引擎、新章节检查及听书（TTS / 朗读）全部相关模块、界面入口与测试代码。
- **权限与依赖精简**：移除 `Info.plist` / `project.yml` 中的 `UIBackgroundModes: audio` 后台音频权限声明，移除 `Factory` 依赖包（保留用于本地 EPUB 解析的 `SwiftSoup`），专注纯净本地阅读，保留前台实体音量键翻页与自动阅读滚屏/翻页功能。
- **保留全部核心本地阅读与云同步体验**：保留多模式翻页与 CoreText 排版、自定义导入字体、3×3 九宫格点按区域、替换净化与 TXT 目录分章规则、书内全文搜索、书签与阅读统计，以及 WebDAV 手动选择性与可选实时同步（向下兼容忽略旧版云端备份中的书源字段）。

### 优化
- **包体积与版本标识精简**：签名/未签名归档包体由 `v1.3.0` 的 `3.74 MB` 缩减至约 `2.57 MB`；「设置 -> 关于应用」清晰标注「`1.4.0 (iOS 18+ 纯净阅读版)`」，清理数据模型与缓存层的历史书源/音频注释。

### 验证
- 精简后的单元测试（`LegadoTests`）在无在线源跳测条件下的全量运行保持 100% 通过，并在 `PurifyAndWebDAVSyncTests` 及 `LegadoUITests` 补充纯净版 `AppEnvironment` 冒烟校验、旧备份字段向下兼容及无「听书 / 换源 / 书源 / 发现」反向 UI 断言；版本号升级至 `1.4.0 (140)`。

## [1.3.0] - 2026-11-23

### 安全
- **WebDAV 密码迁移至 iOS Keychain（`WebDAVKeychainStore`）**：通过 `kSecClassGenericPassword`（`AfterFirstUnlockThisDeviceOnly`）安全托管 WebDAV 密码，读写时自动将历史 `UserDefaults` 明文密码迁移并擦除；同时新增 `isEffectivelyConfigured` 校验过滤未填完整的配置，防止误发后台请求。
- **重定向凭证防泄漏与 `file://` SSRF 阻断**：`WebDAVClient` 新增 `shouldPreserveAuth` 校验，严格拦截 HTTPS 降级、跨主机与跨端口重定向携带 `Authorization` 凭据，并改用原生 `async` 会话代理清除 Swift 6 Sendable 警告；`HTTPClient` 与 `JSEngine` 统一仅放行 `http` / `https` 协议并在同步请求超时后主动 `cancel()` 任务。
- **解压炸弹与路径穿越防护**：
  - `ZipArchiveReader` 新增 10,000 条目数上限与单文件 32 MB 解压上限，校验并拒绝含 `..` / 前导斜杠 / NUL 字符的恶意路径；`WebDAVLocalBookArchive.decompress` 限制归档上限为 64 MB。
  - `ImportLocalBookUseCase` 与 `LocalFontManager` 对导入电子书/字体预先校验文件体积，对封面扩展名执行白名单清洗，并对 `LocalFontManager.deleteFont` / `RestoreFromWebDAVUseCase` 归档文件名实施单层安全路径校验。
- **防云端覆盖保护与缓存上限收敛**：`WebDAVRealtimeSyncService` 与 `BackupToWebDAVUseCase` 严格区分 HTTP 404 与其它网络/限流/解析错误，异常时立即中止 `PUT` 覆盖并保留重试队列；收敛 `CookieStore`（256 域名）与 `CacheManager`（512 条内存键值）上限，并仅在 HTTPS 请求写入系统 Cookie 时标记 `Secure`。

### 性能
- **WebDAV 会话连接池与降频上传**：新增 `WebDAVSessionPool`（LRU 复用最多 4 组会话，复用 HTTP/2 与 TLS 连接）；稳态实时推送将 `ensureDirectory` 设为 `false`，先直接 `PUT` 仅遇 404/409 再自动补建目录，减少大量冗余 `MKCOL` 请求。
- **净化规则与分章正则零冗余编译**：`PurifyContentUseCase` 与 `TxtTocParser` 直接复用 `NSCache` 正则缓存，移除每章/每次优选前触发 `rule.isValid` 的重复正则编译开销；`ImportLocalBookUseCase`、`ReplaceRule` 与 `TextLayoutEngine` 静态预编译常用正则与 `CharacterSet`。
- **字体列表缓存与滚动对比优化**：`LocalFontManager` 进程内缓存系统可用字体与已注册字体文件；`AutoScrollReaderView` 改用 `ScrollRenderKey` 结构体对比替代高开销反射字符串拼接。

### 修复
- **WebDAV 实时同步可靠性闭环**：
  - 完善「实时同步规则与排版」双向闭环，新增独立 `rules_sync.json` 按时间戳双向推送与拉取，接入冷启动、App 回前台、阅读器切回 `.active` 与规则编辑/快捷净化变更触发链。
  - 阅读器采用 `navigationGeneration` 防拉取竞态覆盖，退后台与退出阅读接入 `UIApplication` 后台任务保活与串行推送队列；设置页新增 `WebDAVRealtimeSyncStatus` 同步状态与错误显示，同步清理 SwiftLint `control_statement` 告警。

### 验证
- 在 `TTSAndWebDAVSyncTests` 补全 WebDAV 防覆盖/规则双向同步/降频 `MKCOL` 回归测试，以及 Keychain 迁移、重定向凭证防泄漏、ZIP 炸弹/路径穿越、本地 HTTP/JS `file://` SSRF 阻断与净化/分章性能一致性测试；版本号升级至 `1.3.0 (130)`。

## [1.2.0] - 2026-11-22

### 性能
- **本地封面图异步解码与内存缓存（`BookCoverImage`）**：将本地磁盘封面图的 `Data(contentsOf:)` 与 `UIImage` 解码移出主线程 `body` 计算，改为 O(1) 内存缓存命中的同步渲染与 `.task` 后台异步解码，大幅消除书架滚动掉帧。
- **CoreText 阅读页排版渲染缓存（`CoreTextDrawView`）**：精简 `RenderKey` 对比字段至排版样式与高亮范围，并缓存 `CTFrame`，避免 HUD 显隐、进度面板联动触发无效 `NSAttributedString` 重构与文本重新排版。
- **高频调用点零分配优化**：
  - `Bookmark.formattedDate` 改用 `Calendar.current.dateComponents` 计算格式化字符串，替代每次渲染重复构造 `DateFormatter`。
  - `BookmarkRepositoryImpl.deleteBookmarks(ids:)` 由 N+1 循环查询合并为单次 SwiftData 拉取与单次 `save()` 提交。
  - `SearchBookContentUseCase` 改用 `Task.detached(priority: .userInitiated)` 在后台并发执行全书搜索。
  - `BookshelfView.body` 缓存 `filteredBooks` 计算结果，消除单次渲染周期内的 3 次重复筛选与排序。

### 优化
- **生命周期与防内存泄露加固**：
  - 为 `ReaderView+Helpers` 音量键监听回调补齐 `[weak viewModel]` 弱引用；为 `ReaderViewModel`、`BookshelfViewModel`、`SearchViewModel`、`ChangeSourceViewModel` 与 `SourceManageViewModel` 的异步任务统一挂载 `Task` 句柄，在 `deinit` 时自动取消并统一使用 `[weak self]`，消除页面关闭后的悬挂任务与强引用环。
  - `TTSPlayer` 将音频中断/路由/朗读生命周期通知令牌统一托管并在 `deinit` 注销；将 `AVSpeechSynthesisVoice.speechVoices()` 枚举延后至打开 `TTSControlSheet` 时按需懒加载，并预编译静态 `sentenceRegex`。
  - 为 `RuleEvaluator.storage` 增加 512 条容量上限，防止长期运行后内存无界增长。
- **交互逻辑与架构整洁度**：
  - 优化 `ReaderView` 左右边缘切章点击提示（首章/末章边界给出明确反馈）、滑动进度条重置 `draggingChapterIndex` 状态、下滑关闭目录 Sheet 时自动清理搜索关键词。
  - 书架为空且未处于批量管理模式时隐藏「管理」按钮；本地无在线源书架在下拉刷新时亦支持触发 `WebDAVRealtimeSyncService` 增量同步。
  - 拆分 `ReaderConfig+Helpers.swift` 与 `ReaderViewModel+Sync.swift`，消除 SwiftLint 长度与复杂度告警。

### 验证
- 新增回归单元测试覆盖 `Bookmark.formattedDate` 与批量删除、`SearchBookContentUseCase` 后台搜索上限、`TTSPlayer.splitIntoSentences` 确定性及 `RuleEvaluator` 存储上限；版本号升级至 `1.2.0 (120)`。

## [1.1.2] - 2026-11-22

### 新增
- **WebDAV 可选实时自动同步（`WebDAVRealtimeSyncService`）**：
  - 在 `WebDAVSettingsView` 新增「实时自动同步」开关组：支持独立开关「启用实时同步」（默认开启）、「实时同步阅读进度」（默认开启）与「实时同步规则与排版」（默认关闭）；未配置或未主动保存有效 WebDAV 服务器时绝对零后台网络请求。
  - 阅读翻页/切章时采用 2.5 秒防抖实时上传轻量进度索引 `reading_progress.json`，退出阅读或 App 退入后台立即刷新上传；打开书籍或 App 回到前台时自动拉取最新云端阅读进度并无缝定位。

### 修复
- **跨设备恢复后打开书籍未切换至对应阅读进度的问题**：
  - 修复 `ImportLocalBookUseCase` 新导入未读书籍自带当前毫秒时间戳（导致覆盖或阻断另一设备更早阅读时间戳的进度还原）的问题，改为新书默认 `durChapterTime = 0`。
  - 修复 `RestoreFromWebDAVUseCase` 中 `.legadobook` 归档与 `bundle.books` / `reading_progress.json` 之间的进度合并与跳过逻辑，手动从云端还原会正确采用云端最新或用户显式选择的阅读章节、字偏与阅读时间。
  - 修复 `BookshelfView`、`BookDetailView` 与 `ReaderDestination` 传入过期快照章节号导致覆盖数据库最新进度的问题；打开阅读器时自动从 `BookRepository` 重读最新书籍进度。
  - 修复 `ReaderViewModel` 初始化排版期间 `.updateScreenBounds` 竞态将 `durChapterPos` 重置为第 0 页，以及刚打开书籍立即触发 `saveReadingProgress()` 覆写云端进度/时间戳的问题。

### 优化
- 完善 `BookshelfState.recentReadingBook` 与最近排序策略：优先匹配实际产生过阅读进度的书籍，并在 WebDAV 手动还原或实时拉取完成后立即通过 `bookshelfRefreshSubject` 刷新书架与“继续阅读”横幅。

## [1.1.1] - 2026-11-22

### Added
- **WebDAV Selective Sync**: Added independent toggles (`WebDAVSyncOptions`) in `WebDAVSettingsView` for syncing **Reading Progress & Bookmarks**, **Purification/TOC Rules & Typography**, and **Local Book Files**. Partial backups download and preserve unchecked remote categories in `legado_backup.json`.
- **Full Compressed Local Book File Sync**: Added `WebDAVLocalBookArchive` (Foundation zlib compression) storing chapters, `[Chapter]` TOC metadata, and local cover art under `books/<key>.legadobook` so local books transfer completely across devices.

### Fixed
- **WebDAV Ghost Book Prevention**: `RestoreFromWebDAVUseCase` matches books by exact `bookUrl` or normalized `(name, author)` and refuses to insert `local://` entries when local chapter files are absent (reporting skipped counts instead of leaving unopenable books on the bookshelf). `ReaderViewModel` also displays actionable recovery guidance if an existing local book lacks chapter files on disk.
- **Memory Leaks & Swift 6 Concurrency Warnings**: Fixed `TTSPlayer.shared` strong callback retention on `ReaderViewModel` (`[weak viewModel]` + clearing callbacks on `onDisappear`), broke the `CADisplayLink <-> Coordinator` retain cycle via `WeakDisplayLinkProxy`, added `deinit` Task/KVO cancellation across `ReaderViewModel`, `BookDetailViewModel`, `BookSearchContentViewModel`, and `VolumeButtonHandler`, and eliminated `WebDAVSessionDelegate` / unit-test `UserDefaults` sendability warnings.

### Performance
- Bounded `GetChapterContentUseCase` L1 chapter `memoryCache` (`countLimit = 24`, `totalCostLimit = 8 MB`).
- Precompiled static regexes and eliminated per-line scalar array copies in `PurifyContentUseCase.smartReSegment`; cached duplicate-title regex lookups.
- Rewrote `TxtTocParser.splitByRegex` as single-pass full-text `NSRegularExpression` match range slicing and avoided O(N) whole-book `count` during rule selection.
- Replaced per-call `DateFormatter` in `ReadRecordStore.dayKey(for:)` with `Calendar.current.dateComponents` and cached TTS lockscreen `MPMediaItemArtwork` per book/chapter.

## [1.1.0] - 2026-11-22

### Added & Improved
- **On-Demand Permissions Only**:
  - Removed automatic remote sample source seeding, remote sample cover loading (`AsyncImage`), and network-based bookshelf pull-to-refresh for local libraries so app launch, browsing, and reading never trigger unwanted network or local-network prompts.
  - `AVAudioSession` activation is deferred strictly until TTS playback starts/resumes and released cleanly on stop.
- **Bookshelf, Reader & Settings UX**:
  - Added a top "继续阅读" quick-resume banner on the bookshelf, 6-palette book-spine default covers (`BookDefaultCoverView`), remove confirmation alert, persistent grid/list layout toggle, and accurate first-chapter reading state (`在读` / `未读`).
  - Decluttered the compact iPhone reader top bar into `搜索 | 书签 | ···` menu, added persistent reading progress summary above the HUD slider, reordered single-hand bottom bar actions (`目录 | 排版 | 听书 | 日夜间 | 设置`), and removed duplicate bold toggle in favor of 5-level font weights.
  - Refactored WebDAV configuration into a dedicated `WebDAVSettingsView` subpage under a unified "云同步与存储" section.

### Fixed
- **WebDAV Connectivity & Protocol Compatibility**:
  - Declared `NSLocalNetworkUsageDescription` in `project.yml` & `Legado/Info.plist` for on-demand LAN NAS / Alist / OpenList / Synology access.
  - Added `WebDAVSessionDelegate` preserving HTTP method, body, headers, and `Authorization` across redirects, supporting HTTP Basic/Digest auth and an opt-in `允许自签名证书 (局域网 NAS HTTPS)` toggle.
  - Sent standard RFC 4918 `PROPFIND` XML body with `Depth: 1` / `OPTIONS` / `remoteDirectory` fallback, normalized `dav://` / `davs://` / schemeless / non-ASCII URLs, iterative `MKCOL`, and actionable Chinese `URLError` diagnostics.
- **Full Reader Backup, Storage & TTS Fixes**:
  - `BackupToWebDAVUseCase` / `RestoreFromWebDAVUseCase` back up and restore actual `ReplaceRuleStore`, `TxtTocRuleStore`, `ReadRecordStore`, and `ReaderConfigStore`.
  - Fixed Settings TTS speech-rate slider range (`0.5...2.0x`), cross-chapter TTS normalization & empty volume skipping, migrated `local://` book chapters to `Application Support/LegadoLocalBooks` with cache size isolation, refreshed local book reading progress on `BookDetailView` return, clamped near-end jump offsets, and bundled offline chapters 2–3 for the built-in sample book.

## [1.0.0] - 2026-11-21

### Added
- **Local Books (TXT & EPUB)**: Native UIKit `DocumentPickerView` import, `.onOpenURL` "Open In Legado", pure-Swift `ZipArchiveReader` & `EpubParser` (EPUB 2/3 metadata, TOC, local cover extraction & cache cleanup), `CharsetDetector` (UTF-8 / GBK / Big5 / UTF-16 BOM).
- **CoreText Typography & Margins**: Independent Top/Bottom/Left/Right margins with optional left-right lock, 3-tab bottom panel (`排版 | 边距 | 外观`), font size, 5-level font weight, line/paragraph/letter spacing, paragraph indent, full justification, Traditional/Simplified Chinese conversion, customizable chapter title layout (`居左 / 居中 / 隐藏`, relative size, top/bottom spacing), and 6-slot customizable header/footer info bar with dividers.
- **Real Font Picker & Local Font Loader**: Runtime device font discovery (`UIFont.familyNames`) with live Chinese preview + `TTF / OTF / TTC` local font import (`LocalFontManager`).
- **Page Turn & Auto-Reading**: Native `UIPageViewController(.pageCurl)` supporting iPhone single-page curl and iPad landscape center-spine dual-page curl; cover, slide, continuous scroll, and instant modes; Timed Paged & 60/120Hz `CADisplayLink` Smooth Vertical Auto-Scroll.
- **Themes, Night Mode & Eye Care**: One-tap Reader Day/Night toggle with theme memory, app-wide appearance mode (`跟随系统 / 日间 / 夜间`), custom RGB theme picker with auto dark detection, and warm amber blue-light filter overlay.
- **Interaction & Accessibility**: 3×3 customizable tap zones (`TapZoneConfig`) with 4 presets, hardware volume-button page turn (auto-yields during TTS), configurable keep-screen-on timer, progress bar chapter/page behavior toggle, global haptic toggle, and iPad hardware keyboard shortcuts.
- **Legado Rules Compatibility**: Full Legado Android JSON import/export compatibility for `ReplaceRule` (regex/plain text, title/content/book scope, excludeScope) and `TxtTocRule` (14 official built-in rules with multi-rule scoring & empty volume header merging), plus duplicate title removal and smart re-segmentation.
- **Reading Tools & Bookshelf**: Native `UITableView` TOC sheet focusing directly on the active chapter with Locate/Top/Bottom/Reverse controls, page text excerpt/copy/annotated bookmark/one-tap quick-purify sheet, `ReadRecordStore` daily & per-book reading time statistics, bookshelf sorting (Recent / Title / Progress), and book title/author editing.

### Performance & Quality
- Off-main-thread CoreText pagination with task cancellation on rapid slider scrubbing.
- `CTFramesetter` caching, `NSCache` compiled regex cache, `ImageIO` 600px downsampled local cover cache, and in-memory hot caches for rules and reader config.
- Verified via GitHub Actions SwiftLint, XcodeGen, 84/84 unit tests, and unsigned Release `.ipa` build.
