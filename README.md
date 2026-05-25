# Issuetracker SDK for iOS

Drop-in issue reporter for iOS apps. Shake the device, two-finger
long-press for 3 seconds, or call `Issuetracker.report()` — capture a
screenshot and file an issue directly into a pre-configured Issuetracker
project.

## Install

### Swift Package Manager

```swift
.package(url: "https://github.com/aslekinnerod/issuetracker-sdk-ios.git", from: "0.5.0")
```

### CocoaPods

```ruby
pod 'IssuetrackerSDK', '~> 0.5'
```

## Quickstart

```swift
import IssuetrackerSDK

@main
struct MyApp: App {
  init() {
    Issuetracker.configure(apiKey: "it_...")
  }
  var body: some Scene { WindowGroup { ContentView() } }
}
```

## Full documentation

API reference, triggers, TERMINATED behavior, crash reporting, identity
flow, breadcrumbs, and troubleshooting — see
**[docs.issuetracker.no/sdk/ios](https://docs.issuetracker.no/sdk/ios)**.

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 15+

## License

MIT
