# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SiftRAW is a small macOS 14+ SwiftUI app for culling `.ARW`+`.JPG` photo pairs from a Sony A7III. Swift 5.9, single application target, no third-party runtime dependencies, no test target.

## Commands

The `SiftRAW.xcodeproj` is generated — **never hand-edit it**. Edit `project.yml` and regenerate.

```bash
xcodegen generate                          # regenerate SiftRAW.xcodeproj from project.yml
xcodebuild -scheme SiftRAW build           # build from CLI
xcodebuild -scheme SiftRAW -configuration Release build
open SiftRAW.xcodeproj                     # open in Xcode, then Run
```

To add or rename a source file, drop it under `SiftRAW/` and run `xcodegen generate` — sources are picked up by path glob, no project edit needed.

## Architecture

Single-window SwiftUI app. State flows through one `@MainActor` observable, `CullSession`, injected via `.environmentObject` in [SiftRAWApp.swift](SiftRAW/SiftRAWApp.swift).

**Layers** (under `SiftRAW/`):
- `Model/` — pure logic, no SwiftUI imports except where noted:
  - [CullSession.swift](SiftRAW/Model/CullSession.swift): the single source of truth (source/dest URLs, groups, current index, mode, apply state). All mutations go through here.
  - [PhotoScanner.swift](SiftRAW/Model/PhotoScanner.swift): non-recursive folder scan, groups `.ARW`+`.JPG` by **lowercased basename** into `PhotoGroup`s.
  - [PhotoGroup.swift](SiftRAW/Model/PhotoGroup.swift): one shot = optional RAW + optional JPEG + `Decision` (defaults to `.reject`).
  - [Applier.swift](SiftRAW/Model/Applier.swift): two-phase — `buildPlan` (pure, computes destination paths with `(n)` collision suffixes) then `apply` (does the actual move/copy on a detached task). Owns `CullMode` enum.
  - [PreviewLoader.swift](SiftRAW/Model/PreviewLoader.swift): `actor` with LRU image cache (capacity 80, sized for the max ±20 window plus the visible thumbnails) plus an `in-flight` task map. Uses `CGImageSourceCreateThumbnailAtIndex` — never full-decodes the RAW. Cache key includes pixel size so the strip (small) and main view (large) don't collide. `setActiveWindow(_:)` declares a "warm" set of previews (the ±N around the current photo, N configurable via Settings) closest-first; on each call it cancels in-flight tasks that fell out of the previous window and schedules new ones at `.utility` priority. Direct `load(...)` calls (e.g. ThumbnailStrip, the current visible photo) run at `.userInitiated`, join any in-flight prefetch (priority gets escalated), and are never cancelled by window changes. The window refresh is **debounced by 750 ms** in [PhotoView.swift](SiftRAW/Views/PhotoView.swift) so holding an arrow key through 30 photos doesn't keep cancelling and re-scheduling prefetches that never finish; the visible photo's `load(...)` still fires immediately on every navigation. Changing the radius in [PreferencesView.swift](SiftRAW/Views/PreferencesView.swift) bypasses the debounce and refreshes immediately.
- `Views/` — [PhotoView](SiftRAW/Views/PhotoView.swift) (main image), [ThumbnailStrip](SiftRAW/Views/ThumbnailStrip.swift), [ToolbarView](SiftRAW/Views/ToolbarView.swift).
- [ContentView.swift](SiftRAW/ContentView.swift) wires it all together and hosts the key handler.

**Key cross-cutting patterns to preserve:**

1. **Menu commands → ContentView via NotificationCenter.** `CommandGroup` in `SiftRAWApp` can't easily reach the `@EnvironmentObject`, so menu items post `Notification.Name`s (`.pickSourceFolder`, `.pickDestinationFolder`, `.resetAllDecisions`, `.applyDecisions`) defined at the bottom of [SiftRAWApp.swift](SiftRAW/SiftRAWApp.swift), and `ContentView` subscribes via `.onReceive`. New menu shortcuts should follow the same pattern.

2. **Arrow/Space key handling uses a custom AppKit monitor**, not SwiftUI `.onKeyPress`. `KeyCatcherView` in [ContentView.swift](SiftRAW/ContentView.swift) installs a local `NSEvent` monitor and only swallows the event when no command/option/control modifier is held — that's what keeps `⌘O`/`⌘T`/`⌘R`/`⌘Return` flowing to the menu. Don't replace it with `.onKeyPress` without re-testing menu shortcuts.

3. **Preview always prefers the JPEG companion**; RAW is only loaded for preview when no JPEG exists (`PhotoGroup.previewURL`). This is load-bearing for scroll perf — don't decode `.ARW` for display.

4. **Default decision is `.reject`**, not `.keep`. `Space` toggles. Apply removes only the applied groups from the in-memory list (Apply can be partial; user can change their mind on remaining photos and apply again).

5. **`effectiveMode` overrides user choice when source == destination**, forcing `.move` (copying onto yourself would produce `(1)` duplicates). When changing the apply UI, read `session.effectiveMode`, not `session.mode`.

6. **`splitByType` (default on)** routes each file into `keep/jpg/`, `keep/raw/`, `reject/jpg/`, `reject/raw/`. The "type" comes from `PhotoScanner.rawExtensions`/`jpegExtensions` — if you add a new format, update both sets *and* `Applier.typeSubfolder`.

7. **`Applier.apply` runs on a detached task**; UI state updates hop back to `MainActor`. Don't call it from the main thread synchronously.

8. **`@AppStorage` keys and their defaults live on `UserPrefs`** in [PreferencesView.swift](SiftRAW/Views/PreferencesView.swift), not inline at each `@AppStorage(...)` site. If you read or write a preference from a new view, reuse `UserPrefs.<key>` and `UserPrefs.default…` so the default never drifts between call sites — and for bounded values, clamp via `UserPrefs.clampedPrefetchRadius` (or the equivalent) since users can write arbitrary values to UserDefaults from outside the app.

## Out of scope (v1)

XMP/star ratings, direct deletion, video (`.MP4`), recursive scans (the `recursive` flag in `PhotoScanner` exists but is never set true), decision persistence across restarts, SD-card auto-mount. Don't add these without confirming.

## Trademark note

The MIT license covers code only; the "SiftRAW" name and branding are reserved. Forks distributed elsewhere should ship under a different name — keep that in mind if generating release-facing strings, bundle IDs, or marketing copy.
