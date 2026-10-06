// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "SecureContentNativePolicyTests",
  products: [
    .library(name: "SecureContentNativePolicies", targets: ["SecureContentNativePolicies"]),
  ],
  targets: [
    .target(
      name: "SecureContentNativePolicies",
      path: "secure_content/Sources/secure_content",
      exclude: [
        "SecureContentApi.g.swift",
        "SecureContentPlugin.swift",
        "SecureContentRuntime.swift",
        "SecureContentOverlays.swift",
        "SecureContentClipboard.swift",
        "SecureContentCapture.swift",
        "SecureContentAuthentication.swift",
        "SecureContentIntegrity.swift",
      ],
      sources: ["SecureContentNativePolicy.swift"]
    ),
    .testTarget(
      name: "SecureContentNativePolicyTests",
      dependencies: ["SecureContentNativePolicies"]
    ),
  ]
)
