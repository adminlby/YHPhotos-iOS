import SwiftUI

enum AppTheme {
    static let canvas = Color(uiColor: .systemBackground)
    static let elevated = Color(uiColor: .secondarySystemBackground)
    static let accent = Color("AccentColor")
    static let divider = Color(uiColor: .separator)
}

extension View {
    @ViewBuilder
    func appGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // Clip first so intro gradients / fills don't draw square edges outside the glass shape.
        content
            .clipShape(shape)
            .appGlass(in: shape)
    }
}

extension Int {
    var compactCount: String {
        if AppLanguage.resolved == .english {
            return formatted(.number.notation(.compactName))
        }
        if self >= 10_000 {
            let value = Double(self) / 10_000
            return value >= 100
                ? L10n.format("%d万", Int(value))
                : L10n.format("%.1f万", value)
        }
        if self >= 1_000 { return String(format: "%.1fk", Double(self) / 1_000) }
        return formatted()
    }
}
