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
        Issuetracker.configure(
            apiKey: "it_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            endpoint: URL(string: "https://europe-west1-<your-firebase-project>.cloudfunctions.net")!
        )
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

## Environments

| Environment | Endpoint |
| --- | --- |
| Production | `https://api.issuetracker.no/v1` |
| Staging | `https://issuetracker-api-staging.web.app/v1` |

Use a staging API key when pointing at staging — production keys are not accepted there, and vice versa.

```swift
Issuetracker.configure(
    apiKey: "it_staging_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    endpoint: URL(string: "https://issuetracker-api-staging.web.app/v1")!
)
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
