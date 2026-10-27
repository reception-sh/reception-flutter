require 'yaml'
pubspec = YAML.load_file(File.join(__dir__, '..', 'pubspec.yaml'))
Pod::Spec.new do |s|
  s.name = 'reception_flutter'
  s.version = pubspec['version']
  s.summary = 'Native Reception support chat for Flutter apps on iOS.'
  s.description = pubspec['description']
  s.homepage = pubspec['homepage']
  s.license = { :type => 'MIT', :file => '../LICENSE' }
  s.author = 'Reception'
  s.source = { :path => '.' }
  s.ios.deployment_target = '17.0'
  s.swift_version = '5.0'
  s.source_files = 'reception_flutter/Sources/reception_flutter/**/*.swift'
  # The SDK resolves its resources from a bundle named "Reception" under CocoaPods and from Bundle.module under SwiftPM.
  s.resource_bundles = {
    'Reception' => [
      'reception_flutter/Sources/reception_flutter/Vendor/Reception/Sources/Reception/Resources/Localizable.xcstrings',
      'reception_flutter/Sources/reception_flutter/Vendor/Reception/Sources/Reception/Resources/PrivacyInfo.xcprivacy',
    ],
  }
  s.dependency 'Flutter'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_STRICT_CONCURRENCY' => 'complete',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
