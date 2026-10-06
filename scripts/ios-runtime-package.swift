// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "SecureContentRuntimeTests",
  platforms: [.iOS(.v15)],
  targets: [
    .binaryTarget(name: "Flutter", path: "Flutter.xcframework"),
    .target(
      name: "secure_content",
      dependencies: ["Flutter"],
      path: "Sources/SecureContent",
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),
    .testTarget(
      name: "SecureContentRuntimeTests",
      dependencies: ["secure_content", "Flutter"],
      path: "Tests/SecureContentRuntimeTests",
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),
  ],
  swiftLanguageVersions: [.v5]
)
