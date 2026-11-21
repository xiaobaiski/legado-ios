# Changelog

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
