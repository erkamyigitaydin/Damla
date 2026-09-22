// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Damla",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Damla", targets: ["Damla"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Damla",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Damla",
            // Sparkle.framework is copied into Contents/Frameworks by build.sh / release.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ],
    swiftLanguageModes: [.v5]
)
