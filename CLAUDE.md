# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AudioBooth is an iOS/iPadOS/watchOS/CarPlay/Mac Catalyst client for [Audiobookshelf](https://audiobookshelf.org) servers. Swift 6.2, Xcode 26+, deploys to iOS 17+ / watchOS 10+. Some screens have `iOS 26.0+` paths (e.g. modern `TabView` in `ContentView.swift`).

There is no test suite. Verification is manual through Xcode builds and runs.

## Common Commands

```bash
# Format Swift code (run before committing — pre-commit hook also enforces this)
xcrun swift-format format --in-place --recursive --parallel .

# Lint (strict — what the pre-commit hook runs)
xcrun swift-format lint --strict --recursive --parallel .

# Install pre-commit hooks (one-time, for contributors)
pre-commit install

# Build for simulator from CLI
xcodebuild -project AudioBooth/AudioBooth.xcodeproj -scheme AudioBooth -destination 'platform=iOS Simulator,name=iPhone 15' build
```

For device builds, copy `AudioBooth/Local.xcconfig.example` to `AudioBooth/Local.xcconfig` and fill in `DEVELOPMENT_TEAM` / `ORG_IDENTIFIER`. The file is gitignored. See `CONTRIBUTING.md` for which capabilities must be removed on a free developer account.

## Repository Layout

The Xcode project lives at `AudioBooth/AudioBooth.xcodeproj` and depends on three local Swift packages at the repo root:

- **`API/`** — `Audiobookshelf` singleton (`Audiobookshelf.shared`) that owns all server-facing services (`AuthenticationService`, `LibrariesService`, `BooksService`, `PodcastsService`, `SessionService`, `BookmarksService`, `NetworkDiscoveryService`, …). `NetworkService` handles HTTP + token refresh; `CredentialsActor` guards keychain access. DTOs live in `API/Sources/API/Models/`.
- **`Models/`** — SwiftData `@Model` types (`LocalBook`, `LocalEpisode`, `LocalPodcast`, `MediaProgress`, `Bookmark`, `PlaybackSession`, …) plus `ModelContextProvider` (per-server `ModelContainer`s) and `AudiobookshelfSchema` (versioned schema). Shared with the widget and Watch extensions.
- **`PlayerIntents/`** — App Intents that touch playback (`PlayBookIntent`, `PausePlaybackIntent`, `OpenBookIntent`, sleep-timer Live Activity attrs). Kept separate so the widget/Shortcuts can import it without dragging in the full app.

Xcode targets under `AudioBooth/`:

- `AudioBooth` (iOS app, also runs as Mac Catalyst)
- `AudioBooth Watch App`
- `AudioBoothWidget` (home-screen + lock-screen widgets, Live Activities)
- `AudioBoothWatchWidget` (watchOS complications)

## Architecture

**View / Model / ViewModel.** Each screen under `AudioBooth/Screens/<Feature>/` typically has `<Feature>View.swift` + `<Feature>Model.swift` (or `<Feature>ViewModel.swift`). Don't mix network/storage logic into Views — push it into the Model.

**Singletons orchestrate cross-screen state.** Most live in `AudioBooth/Services/`:

- `PlayerManager.shared` — current playback (`current: BookPlayer.Model?`), queue, full-player presentation, ebook reader presentation. Subscribes to `Audiobookshelf.shared.libraries` and clears state on server switch.
- `SessionManager.shared` — playback session sync to the server, including replaying unsynced sessions on foreground (`AudioBoothApp.swift` `scenePhase`).
- `DownloadManager.shared` / `StorageManager.shared` — offline downloads (uses background URLSession; `AppDelegate.handleEventsForBackgroundURLSession` wires the completion handler).
- `UserPreferences.shared` — `@AppStorage`-backed preferences (`Services/UserPreferences/`). Mirrored to the shared App Group + iCloud KV store.
- `WatchConnectivityManager`, `NowPlayingManager`, `WidgetManager`, `BookmarkSyncQueue`, `PinnedPlaylistManager`, `SmartContinueResolver`, `DeepLinkManager`, `CrashReporter`, `Haptics`, `ToastManager`.

**Audiobookshelf is a singleton hub.** All API calls go through `Audiobookshelf.shared.<service>`. The singleton rebuilds `NetworkService` and the Nuke `ImagePipeline` when the active server changes; `onServerSwitched` (wired in `AppDelegate`) tells `ModelContextProvider` to swap its SwiftData container.

**Per-server SwiftData containers.** `ModelContextProvider.shared` keeps one `ModelContainer` per `serverID`, stored under the App Group `group.me.jgrenier.audioBS` so the widget/Watch can read the same DB. Accessing `.context` without an active server triggers an `assertionFailure` and falls back to a `"fallback"` DB — don't rely on that path in normal flows.

**App Group is `group.me.jgrenier.audioBS`** — used for shared `UserDefaults` (e.g. accent color for widgets), shared SwiftData containers, and downloaded ebook files. Bundle IDs are templated through `ORG_IDENTIFIER` from `Local.xcconfig` (the App Group itself is fixed).

**iOS 26 vs iOS 17 split.** `ContentView.swift` branches on `#available(iOS 26.0, *)` for the modern `TabView` with `tabViewBottomAccessory`; the legacy path uses `safeAreaInset` for the mini player. New navigation/tab work should preserve both branches.

**CarPlay** lives in `AudioBooth/CarPlay/`. `CarPlayDelegate`/`CarPlayController` set up the scene; each `CarPlay*` file implements one template (`CarPlayPageProtocol`).

## Code Style

- `swift-format` config is at `.swift-format` (line length 120, 2-space indent, ordered imports enforced, file-scoped privacy enforced). Pre-commit runs both `format --in-place` and `lint --strict`.
- Swift 6.2 strict concurrency — prefer `async/await` and `Sendable`. Several singletons use `@unchecked Sendable` where Combine/observable bridging forces it; follow the existing pattern rather than introducing new locking.
- Models in `API/` are plain `Decodable & Sendable` DTOs; persistent state belongs in `Models/` as SwiftData `@Model` types.
- User-facing strings go in `AudioBooth/Localizable.xcstrings` (the catalog Xcode auto-updates on build).

## Things to Know Before Editing

- **Don't bypass the `Audiobookshelf.shared` services** to make raw HTTP requests — auth, token refresh, and Pulse logging all hang off `NetworkService`.
- **Don't read/write SwiftData outside `ModelContextProvider.shared.context`** — the per-server container routing is what keeps multi-server data isolated.
- **Widgets and the Watch app import `API` and `Models`** — keep those packages free of UIKit-only or main-app-only code.
- **Main branch is occasionally rebased and force-pushed** (see `README.md`). Don't assume linear history when interpreting `git log`.
