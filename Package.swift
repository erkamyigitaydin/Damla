// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Damla",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Damla", targets: ["Damla"])],
    targets: [.executableTarget(name: "Damla", path: "Sources/Damla")],
    swiftLanguageModes: [.v5]
)
