import SwiftUI

private struct SceneEvent: Decodable, Identifiable, Sendable {
    let id: String
    let time: String
    let registration: String?
    let flightNumber: String?
    let `operator`: String?
    let aircraftType: String?
    let livery: String?
    let photographerCount: Int
    let vantageCount: Int
    let multiAngle: Bool
    let relationConfidence: String
    let photos: [Photo]
}

private struct SceneResp: Decodable, Sendable {
    struct Stats: Decodable, Sendable {
        let photos: Int
        let movements: Int
        let photographers: Int
    }
    let airport: String
    let date: String
    let stats: Stats
    let events: [SceneEvent]
}

struct SceneView: View {
    @State private var airport = ""
    @State private var day = Date()
    @State private var result: SceneResp?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didQuery = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                queryCard
                if let result {
                    GlassPanel(cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(result.airport) · \(result.date)").font(.headline)
                            Text(L10n.format("%d 张作品 · %d 次起降 · %d 位摄影师", result.stats.photos, result.stats.movements, result.stats.photographers))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(14)
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(result.events) { event in
                            eventCard(event)
                        }
                    }
                    if result.events.isEmpty && didQuery && !isLoading {
                        EmptyStateView(L10n.string("这一天没有场景"), systemImage: "calendar", description: L10n.string("换个机场或日期再试试。"))
                            .padding(.vertical, 24)
                    }
                }
                LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                    Task { await query() }
                }
            }
            .padding(18)
        }
        .navigationTitle(L10n.string("历史场景"))
        .navigationBarTitleDisplayMode(.inline)
        .appScreenBackground()
    }

    private var queryCard: some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                SuggestField(title: L10n.string("机场"), type: "airport", text: $airport)
                DatePicker(L10n.string("日期"), selection: $day, displayedComponents: .date)
                Button {
                    Task { await query() }
                } label: {
                    Text(isLoading ? L10n.string("查询中…") : L10n.string("查询场景"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(canQuery ? AppTheme.accent : AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(canQuery ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canQuery || isLoading)
            }
            .padding(18)
        }
    }

    private var canQuery: Bool {
        !airport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func eventCard(_ event: SceneEvent) -> some View {
        GlassPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(event.time).font(.headline)
                    Spacer()
                    StatusChip(text: confidenceLabel(event.relationConfidence))
                }
                Text([
                    event.flightNumber,
                    event.registration,
                    event.operator,
                    event.aircraftType,
                    event.livery,
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(L10n.format("%d 位摄影师 · %d 个机位%@", event.photographerCount, event.vantageCount, event.multiAngle ? " · 多机位" : ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if !event.photos.isEmpty {
                    let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(event.photos.prefix(6)) { photo in
                            NavigationLink {
                                PhotoDetailView(photoID: photo.id)
                            } label: {
                                RemoteImage(url: photo.thumbnailURL)
                                    .aspectRatio(4/3, contentMode: .fill)
                                    .frame(minHeight: 72)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func confidenceLabel(_ value: String) -> String {
        switch value {
        case "confirmed": return L10n.string("确认关联")
        case "probable": return L10n.string("可能关联")
        case "single": return L10n.string("单机位")
        default: return value
        }
    }

    @MainActor
    private func query() async {
        guard canQuery else { return }
        isLoading = true
        errorMessage = nil
        didQuery = true
        defer { isLoading = false }
        let dayString: String = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: day)
        }()
        do {
            result = try await APIClient.shared.get(
                "api/aviation-intel/scene",
                query: [
                    URLQueryItem(name: "airport", value: airport.trimmingCharacters(in: .whitespacesAndNewlines)),
                    URLQueryItem(name: "day", value: dayString),
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
            result = nil
        }
    }
}
