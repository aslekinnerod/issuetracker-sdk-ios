Pod::Spec.new do |s|
  s.name             = 'IssuetrackerSDK'
  s.version          = '0.4.1'
  s.summary          = 'Drop-in issue reporter SDK for iOS apps.'
  s.description      = <<~DESC
    Shake the device (or call Issuetracker.report()) to capture a
    screenshot, annotate it, and file an issue directly into a
    pre-configured Issuetracker project.
  DESC
  s.homepage         = 'https://issuetracker.no'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Asle Kinnerod' => 'asle78@gmail.com' }
  s.source           = { :git => 'https://github.com/aslekinnerod/issuetracker-sdk-ios.git', :tag => s.version.to_s }

  s.platform         = :ios, '16.0'
  s.swift_version    = '5.9'

  s.source_files     = 'Sources/IssuetrackerSDK/**/*.swift'
  s.frameworks       = 'UIKit', 'Foundation', 'CoreMotion', 'MetricKit', 'ReplayKit'
end
