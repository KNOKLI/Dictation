// Иконка в стиле тёмных иконок macOS 26: тёмно-синий сквиркл + серебристая металлическая волна.
// Запуск: swift make_icon.swift out.png
import SwiftUI
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

struct Icon: View {
    // высоты полосок волны (из 1024)
    let bars: [CGFloat] = [150, 300, 230, 500, 380, 260, 140]

    var metal: LinearGradient {
        LinearGradient(stops: [
            .init(color: Color(red: 0.97, green: 0.98, blue: 1.00), location: 0.00),
            .init(color: Color(red: 0.80, green: 0.83, blue: 0.90), location: 0.35),
            .init(color: Color(red: 0.93, green: 0.94, blue: 0.97), location: 0.55),
            .init(color: Color(red: 0.56, green: 0.61, blue: 0.72), location: 1.00),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            // фон
            shape.fill(LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.36),
                                               Color(red: 0.06, green: 0.08, blue: 0.18)],
                                      startPoint: .top, endPoint: .bottom))
            // мягкий свет сверху
            shape.fill(RadialGradient(colors: [.white.opacity(0.10), .clear],
                                      center: UnitPoint(x: 0.3, y: 0.0), startRadius: 0, endRadius: 650))
            // кромка
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03), .white.opacity(0.08)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 3)

            // волна
            HStack(spacing: 38) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule()
                        .fill(metal)
                        .overlay(
                            Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .clear],
                                                                  startPoint: .top, endPoint: .center),
                                                   lineWidth: 2.5)
                        )
                        .frame(width: 58, height: bars[i])
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 18, y: 12)
            .shadow(color: Color(red: 0.55, green: 0.65, blue: 1.0).opacity(0.15), radius: 40)
        }
        .frame(width: 824, height: 824)
        .compositingGroup()
        .shadow(color: .black.opacity(0.30), radius: 20, y: 10)
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
