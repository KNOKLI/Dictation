// swift-tools-version: 6.0
import PackageDescription

// Движок распознавания — whisper.cpp из Homebrew (brew install whisper-cpp)
let whisper = "/opt/homebrew/opt/whisper.cpp"
let ggml = "/opt/homebrew/opt/ggml"

let package = Package(
    name: "Dictation",
    platforms: [.macOS("26.0")],
    targets: [
        .target(
            name: "CWhisper",
            cSettings: [.unsafeFlags(["-I\(whisper)/include", "-I\(ggml)/include"])],
            linkerSettings: [.unsafeFlags([
                "-L\(whisper)/lib", "-lwhisper", "-L\(ggml)/lib", "-lggml", "-lggml-base",
                "-Xlinker", "-rpath", "-Xlinker", "\(whisper)/lib",
            ])]
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
