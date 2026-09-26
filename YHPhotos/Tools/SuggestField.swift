import SwiftUI

struct SuggestHit: Decodable, Identifiable, Sendable {
    let label: String
    let sub: String?
    let fill: [String: String]
    let ids: [String: Int?]?

    var id: String { "\(label)-\(sub ?? "")" }
    var primaryFill: String { fill.values.first ?? label }
}

/// Lightweight autocomplete used by aviation-intel tools (airport / airline / registration).
struct SuggestField: View {
    let title: String
    let type: String
    @Binding var text: String
    var onPick: ((SuggestHit) -> Void)? = nil

    @State private var suggestions: [SuggestHit] = []
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($focused)
                .onChange(of: text) { _ in scheduleFetch() }
                .onChange(of: focused) { on in if !on { suggestions = [] } }

            if focused && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.prefix(8).enumerated()), id: \.element.id) { index, hit in
                        Button {
                            text = hit.label
                            onPick?(hit)
                            suggestions = []
                            focused = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.label).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                if let sub = hit.sub, !sub.isEmpty {
                                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if index < min(suggestions.count, 8) - 1 { Divider() }
                    }
                }
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func scheduleFetch() {
        task?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard focused, query.count >= 1 else { suggestions = []; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            do {
                let hits: [SuggestHit] = try await APIClient.shared.get(
                    "api/suggest",
                    query: [
                        URLQueryItem(name: "type", value: type),
                        URLQueryItem(name: "q", value: query),
                    ]
                )
                guard !Task.isCancelled else { return }
                suggestions = hits
            } catch {
                suggestions = []
            }
        }
    }
}
