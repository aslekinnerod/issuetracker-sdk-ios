# Issuetracker SDK for iOS

Drop-in issue reporter for iOS apps. Shake the device, two-finger long-press for 3 seconds, or call `Issuetracker.report()` — capture a screenshot and file an issue directly into a pre-configured Issuetracker project.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/aslekinnerod/issuetracker-sdk-ios.git", from: "0.1.0")
```

## Usage

1. Create an API key in the Issuetracker web app: `Project → ⚙ settings → API keys → Generate key`.
2. Configure once at app launch:

```swift
import IssuetrackerSDK

@main
struct MyApp: App {
    init() {
        Issuetracker.configure(apiKey: "it_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
    }
    // ...
}
```

That's it. Either gesture brings up the reporter:

| Trigger | Notes |
| --- | --- |
| Shake the device | Accelerometer-based — real devices only, not the simulator |
| Two-finger long-press for 3 seconds | Anywhere in the app; works in the simulator too |
| `Issuetracker.report()` | Programmatic, e.g. from a "Report a bug" menu item |

Both gestures are enabled by default. Disable individually via `shakeToReport: false` or `longPressToReport: false` on `configure(...)`.

The SDK talks to Issuetracker's hosted backend — there is no endpoint to configure. Staging-prefixed keys (`it_staging_…`) are routed to the staging environment automatically; everything else hits production.

## First-run onboarding (optional)

Opt-in popover shown on first launch that teaches the user which gestures trigger the reporter:

```swift
Issuetracker.configure(
    apiKey: "it_xxx…",
    showOnboarding: true
)
```

Shown once per install (persisted in `UserDefaults`). Only renders illustrations for gestures that are actually enabled — disable shake or long-press and that tile drops out. If both are disabled, the popover is skipped entirely.

Re-present from your own settings screen ("Show introduction again"):

```swift
Button("Show introduction again") { Issuetracker.showOnboarding() }
```

## Manual trigger

```swift
Button("Report bug") { Issuetracker.report() }
```

## Platform

- iOS 16+
- No third-party dependencies
- ~30 KB compiled

## License

MIT — see [LICENSE](LICENSE).
