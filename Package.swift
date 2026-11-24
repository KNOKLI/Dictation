// swift-tools-version: 6.0
import PackageDescription

// Движок распознавания — whisper.cpp, собранный статически внутрь приложения (scripts/build_whisper.sh,
// 2026-11-25): пользователям не нужен Homebrew. Раньше брался из Homebrew (brew install whisper-cpp).
let vendor = Context.packageDirectory + "/vendor/whisper"

let package = Package(
    name: "Dictation",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "CWhisper",
            cSettings: [.unsafeFlags(["-I\(vendor)/include"])],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(vendor)/lib", "-lwhisper", "-lggml", "-lggml-base", "-lggml-cpu",
                    "-lggml-metal", "-lggml-blas",
                ]),
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "Dictation",
            dependencies: ["CWhisper"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
