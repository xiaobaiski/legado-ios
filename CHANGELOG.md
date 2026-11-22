# Changelog

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
