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

## Accessibility

The shake and two-finger long-press triggers are motion- and
multipoint-gestures. Not every user can perform them: WCAG 2.2
requires a single-pointer alternative for multipoint gestures
(2.5.1) and a non-motion alternative for motion actuation (2.5.4),
and gestures like these can also collide with VoiceOver and Switch
Control input.

If you enable shake and/or long-press, you **must** also provide an
accessible activation path. Either let the SDK do it (ADR-0008):

```swift
Issuetracker.configure(
  apiKey: "it_...",
  // Registers a "Report a bug" VoiceOver custom action whenever
  // VoiceOver is running — screen readers claim multi-finger
  // gestures, so this is the screen-reader path to the reporter.
  accessibilityAction: true,
  // Shows a small floating "Report" button (bottom-trailing) —
  // a visible, single-pointer, non-motion alternative for everyone
  // else. Hidden while the reporter is open.
  showReportButton: true
)
```

**or** expose a visible control in your own UI that calls
`Issuetracker.report()` — for example a "Report a bug" row in your
settings or help menu:

```swift
Button("Report a bug") {
  Issuetracker.report()
}
```

Both flags default to `false` and can be flipped at runtime by
calling `configure(...)` again.

You should also offer a user-facing setting to disable the gesture
triggers, both for accessibility reasons and because shake/two-finger
press can conflict with assistive technologies or your app's own
gestures.

The SDK's own UI supports Dynamic Type, VoiceOver labels and
announcements, and Reduce Motion.

## Full documentation

API reference, triggers, TERMINATED behavior, crash reporting, identity
flow, breadcrumbs, and troubleshooting — see
**[docs.issuetracker.no/sdk/ios](https://docs.issuetracker.no/sdk/ios)**.

## Requirements

- iOS 16.0+
- Swift 5.9+
- Xcode 15+

CI builds and tests on the current Xcode 26 toolchain against the newest
iOS simulator runtime on the runner image. Older Xcode versions and the
iOS 16 runtime floor are supported by declaration (deployment target and
`swift-tools-version`), not by an automated test run.

## License

MIT
