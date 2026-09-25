import SwiftUI

enum AppTheme {
    static let canvas = Color(red: 8 / 255, green: 10 / 255, blue: 13 / 255)
    static let elevated = Color(red: 16 / 255, green: 21 / 255, blue: 28 / 255)
    static let accent = Color("AccentColor")
    static let divider = Color.white.opacity(0.12)
    static let dockHeight: CGFloat = 82
}

extension View {
    @ViewBuilder
    func appGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
    }

    func appScreenBackground() -> some View {
        background(AppTheme.canvas.ignoresSafeArea())
    }
}

struct GlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .appGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension Int {
    var compactCount: String {
        if self >= 10_000 {
            let value = Double(self) / 10_000
            return value >= 100 ? "\(Int(value))万" : String(format: "%.1f万", value)
        }
        if self >= 1_000 { return String(format: "%.1fk", Double(self) / 1_000) }
        return formatted()
    }
}
