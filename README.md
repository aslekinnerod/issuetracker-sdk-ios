# Issuetracker SDK for iOS

Drop-in issue reporter for iOS apps. Shake the device (or call `Issuetracker.report()`) to capture a screenshot and file an issue directly into a pre-configured Issuetracker project.

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

That's it. Shake the device anywhere in your app to bring up the reporter.

Shake detection uses the accelerometer, so it works on real devices. In the simulator use `Issuetracker.report()` from a button to test.

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
