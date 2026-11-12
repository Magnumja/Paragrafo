// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Paragrafo", platforms: [.macOS(.v15)], targets: [
    .executableTarget(name: "Paragrafo"),
    .testTarget(name: "ParagrafoTests", dependencies: ["Paragrafo"])
])
