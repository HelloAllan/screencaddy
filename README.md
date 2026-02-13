# ScreenCaddy

A macOS Dock app that captures and mirrors selected app windows. Pick which apps to share, let capture auto-switch as you move between them, and see an overlay on the window that is currently being captured.

[Download on the Mac App Store](https://apps.apple.com/au/app/screencaddy/id6760108218)

![Focus mode](screenshots/02-focus-mode.png)

## Features

- Choose exactly which apps are shared, so nothing else leaks into a screen share
- Auto-switches capture to the active app
- Focus mode (one app) and tile mode (several apps at once)
- Overlay on the window being captured

## Requirements

- macOS 14+
- Screen Recording permission (System Settings → Privacy & Security → Screen Recording)
- Swift 5.9+ toolchain

## Build

Run from the `app/` directory:

```bash
swift build                # debug build
swift build -c release     # release build
make run                   # release build, create .app bundle, open it
make bundle                # create .app bundle only
make clean                 # clean build artifacts
```

The `bundle`, `appstore` and `dmg` targets sign with the author's Apple Developer identity. To build locally, change the `codesign --sign` identity in `app/Makefile` (for example `--sign -` for ad-hoc signing).

## Architecture

Swift Package Manager project with a single executable target, `ScreenCaddy`, and no third-party dependencies.

```
app/Sources/ScreenCaddy/
├── main.swift         # Entry point, Dock app
├── AppDelegate.swift  # Window creation, menu bar, preferences
├── AppState.swift     # Central coordinator
├── Capture/           # ScreenCaptureKit stream wrapper
├── Monitor/           # Active window and running apps tracking
├── Overlay/           # "Being shared" overlay panel
├── Views/             # SwiftUI views
└── Utilities/         # Preferences, permissions, debouncer
```

`CaptureEngine` wraps ScreenCaptureKit's `SCStream` and renders frames into a `CALayer`. `AppState` owns one engine in focus mode and one per app in tile mode.

## License

[MIT](LICENSE)
