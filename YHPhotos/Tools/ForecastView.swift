import SwiftUI

private struct ForecastSitePhoto: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String?
    let thumb: String?
    let href: String
    let author: String?
    let shotAt: String?
}

private struct ForecastItem: Decodable, Identifiable, Sendable {
    let flightNumber: String?
    let callsign: String?
    let mode: String
    let typecode: String?
    let typeText: String?
    let registration: String?
    let airlineCode: String?
    let airlineName: String?
    let origin: String?
    let destination: String?
    let status: String?
    let runway: String?
    let scheduledAtIso: String?
    let scheduledDepartureIso: String?
    let scheduledArrivalIso: String?
    let estimatedDepartureIso: String?
    let estimatedArrivalIso: String?
    let realDepartureIso: String?
    let realArrivalIso: String?
    let departureIso: String?
    let arrivalIso: String?
    let score: Double
    let tags: [String]
    let goodTypes: [String]?
    let reasons: [String]
    let liveryName: String?
    let isSpecialLivery: Bool?
    let photos: [ForecastSitePhoto]?
    let equipmentChange: EquipmentChange?

    struct EquipmentChange: Decodable, Sendable {
        let previousTypecode: String?
        let previousFlightNumber: String?
    }

    var id: String {
        [flightNumber, registration, mode, scheduledAtIso, String(score)].compactMap { $0 }.joined(separator: "|")
    }

    var title: String {
        flightNumber ?? callsign ?? registration ?? L10n.string("航班")
    }

    var isArrival: Bool {
        mode.lowercased().hasPrefix("arrival")
    }

    var directionTitle: String {
        isArrival ? L10n.string("进港") : L10n.string("离港")
    }

    var directionSymbol: String {
        isArrival ? "arrow.down.left" : "arrow.up.right"
    }

    var departureTimeISO: String? {
        departureIso ?? realDepartureIso ?? estimatedDepartureIso ?? scheduledDepartureIso
    }

    var arrivalTimeISO: String? {
        arrivalIso ?? realArrivalIso ?? estimatedArrivalIso ?? scheduledArrivalIso
    }

    var eventTimeISO: String? {
        isArrival ? arrivalTimeISO : departureTimeISO
    }
}

private struct ForecastResp: Decodable, Sendable {
    struct AirportInfo: Decodable, Sendable {
        let id: Int
        let name: String?
        let nameEn: String?
        let city: String?
        let iata: String?
        let icao: String?
        let timezone: String?
    }

    struct Cache: Decodable, Sendable {
        let hit: Bool
        let ttlSeconds: Int
        let partialHit: Bool?
    }

    let airport: String
    let airportInfo: AirportInfo?
    let day: String
    let mode: String
    let generatedAt: String
    let totalFlights: Int
    let goodCount: Int
    let minScore: Double
    let items: [ForecastItem]
    let cache: Cache
}

private enum ForecastDirectionFilter: String, CaseIterable, Identifiable {
    case all
    case arrivals
    case departures

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.string("全部")
        case .arrivals: L10n.string("进港")
        case .departures: L10n.string("离港")
        }
    }

    func includes(_ item: ForecastItem) -> Bool {
        switch self {
        case .all: true
        case .arrivals: item.isArrival
        case .departures: !item.isArrival
        }
    }
}

private struct ForecastEvent: Identifiable {
    let item: ForecastItem
    let date: Date
    let minute: Int

    var id: String { item.id }
}

private enum ForecastTime {
    static func timeZone(_ identifier: String?) -> TimeZone {
        identifier.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: 0)!
    }

    static func date(from iso: String?) -> Date? {
        guard let iso else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: iso) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: iso)
    }

    static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    static func day(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar(in: timeZone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func minute(_ date: Date, in timeZone: TimeZone) -> Int {
        let parts = calendar(in: timeZone).dateComponents([.hour, .minute], from: date)
        return min(max((parts.hour ?? 0) * 60 + (parts.minute ?? 0), 0), 1_439)
    }

    static func clock(minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func zoneLabel(_ timeZone: TimeZone, at date: Date = Date()) -> String {
        let offset = timeZone.secondsFromGMT(for: date)
        guard offset != 0 else { return "UTC" }
        let sign = offset >= 0 ? "+" : "−"
        let absoluteMinutes = abs(offset) / 60
        let hours = absoluteMinutes / 60
        let minutes = absoluteMinutes % 60
        return minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }

    static func clock(_ date: Date, in timeZone: TimeZone) -> String {
        "\(clock(minute: minute(date, in: timeZone))) \(zoneLabel(timeZone, at: date))"
    }

    static func full(_ date: Date, in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar(in: timeZone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "\(formatter.string(from: date)) \(zoneLabel(timeZone, at: date))"
    }
}

struct ForecastView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var airport = ""
    @State private var loadedAirportQuery = ""
    @State private var directionFilter: ForecastDirectionFilter = .all
    @State private var selectedMinute = 12 * 60
    @State private var result: ForecastResp?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if appModel.sessionUser == nil {
                    LoginRequiredCard(message: L10n.string("登录后可查询好货预报。"))
                } else {
                    queryCard

                    if let result {
                        forecastContent(result)
                    }

                    LoadingOrErrorView(isLoading: isLoading, error: errorMessage) {
                        Task { await query(forceRefresh: false) }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .navigationTitle(L10n.string("好货预报"))
        .navigationBarTitleDisplayMode(.inline)
        .appScreenBackground()
    }

    private var queryCard: some View {
        GlassPanel(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                SuggestField(title: L10n.string("机场"), type: "airport", text: $airport)

                Button {
                    Task { await query(forceRefresh: false) }
                } label: {
                    Label(
                        isLoading ? L10n.string("查询中…") : L10n.string("查看今天"),
                        systemImage: "clock"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(canQuery ? AppTheme.accent : AppTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(canQuery ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canQuery || isLoading)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func forecastContent(_ result: ForecastResp) -> some View {
        let timeZone = ForecastTime.timeZone(result.airportInfo?.timezone)
        let events = forecastEvents(result, filter: directionFilter, timeZone: timeZone)

        VStack(spacing: 16) {
            forecastHeader(result, eventCount: events.count, timeZone: timeZone)
            directionPicker

            RareFlightTimeline(
                events: events,
                day: result.day,
                timeZone: timeZone,
                selectedMinute: $selectedMinute
            )

            nearbyFlights(events, result: result, timeZone: timeZone)
        }
    }

    private func forecastHeader(_ result: ForecastResp, eventCount: Int, timeZone: TimeZone) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.format("今天 · %@", result.day))
                    .font(.title3.weight(.bold))
                Text([result.airportInfo?.iata ?? result.airport, result.airportInfo?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(ForecastTime.zoneLabel(timeZone))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.format("共 %d 架", eventCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var directionPicker: some View {
        HStack(spacing: 8) {
            ForEach(ForecastDirectionFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        directionFilter = filter
                    }
                } label: {
                    Text(filter.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            directionFilter == filter ? AppTheme.accent : AppTheme.elevated,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(directionFilter == filter ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(directionFilter == filter ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func nearbyFlights(_ events: [ForecastEvent], result: ForecastResp, timeZone: TimeZone) -> some View {
        let nearby = events.filter { abs($0.minute - selectedMinute) <= 30 }
        let lowerMinute = max(0, selectedMinute - 30)
        let upperMinute = min(1_439, selectedMinute + 30)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("选中时间附近"))
                        .font(.headline)
                    Text("\(ForecastTime.clock(minute: lowerMinute))–\(ForecastTime.clock(minute: upperMinute)) · \(ForecastTime.zoneLabel(timeZone))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(L10n.format("%d 架", nearby.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if nearby.isEmpty {
                nearbyEmptyState(events, result: result, timeZone: timeZone)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(nearby) { event in
                        forecastCard(event, timeZone: timeZone)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nearbyEmptyState(_ events: [ForecastEvent], result: ForecastResp, timeZone: TimeZone) -> some View {
        GlassPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                if events.isEmpty {
                    Label(L10n.string("今天暂无好货预报"), systemImage: "airplane")
                        .font(.headline)
                    Text(L10n.string("时间轴仍可浏览全天；切换进港或离港筛选查看对应结果。"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.format("%@ 附近暂无好货", ForecastTime.clock(minute: selectedMinute)))
                        .font(.headline)

                    if let adjacent = adjacentEvent(in: events) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedMinute = adjacent.minute
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: adjacent.minute > selectedMinute ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(adjacent.minute > selectedMinute ? L10n.string("下一架") : L10n.string("上一架"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(ForecastTime.clock(minute: adjacent.minute)) · \(adjacent.item.title) · \(adjacent.item.directionTitle)")
                                        .font(.subheadline.weight(.semibold))
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("\(adjacent.item.directionTitle) \(adjacent.item.title)，\(ForecastTime.clock(adjacent.date, in: timeZone))")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func forecastCard(_ event: ForecastEvent, timeZone: TimeZone) -> some View {
        let item = event.item
        let departureDate = ForecastTime.date(from: item.departureTimeISO)
        let arrivalDate = ForecastTime.date(from: item.arrivalTimeISO)

        return GlassPanel(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Label(item.directionTitle, systemImage: item.directionSymbol)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .frame(minHeight: 30)
                        .background(directionColor(item).opacity(0.16), in: Capsule())
                        .foregroundStyle(directionColor(item))

                    Text(item.title)
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 8)
                }

                VStack(alignment: .leading, spacing: 5) {
                    if let airline = item.airlineName ?? item.airlineCode {
                        Text(airline)
                            .font(.subheadline.weight(.medium))
                    }
                    if item.origin != nil || item.destination != nil {
                        Text("\(item.origin ?? "—") → \(item.destination ?? "—")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ForecastTime.clock(event.date, in: timeZone))
                            .font(.title2.monospacedDigit().weight(.bold))
                        Text(item.isArrival ? L10n.string("到港") : L10n.string("起飞"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(probabilityText(item.score))
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                        Text(L10n.string("稀有机型概率"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if item.typeText != nil || item.typecode != nil || item.registration != nil {
                    Label(
                        [item.typeText ?? item.typecode, item.registration].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "airplane"
                    )
                    .font(.subheadline.weight(.semibold))
                }

                Divider()

                VStack(spacing: 9) {
                    if let departureDate {
                        detailTimeRow(title: L10n.string("起飞"), value: ForecastTime.full(departureDate, in: timeZone))
                    }
                    if let arrivalDate {
                        detailTimeRow(title: L10n.string("降落"), value: ForecastTime.full(arrivalDate, in: timeZone))
                    }
                    if let runway = item.runway, !runway.isEmpty {
                        detailTimeRow(title: L10n.string("跑道"), value: runway)
                    }
                }

                if item.status != nil || !item.tags.isEmpty {
                    FlowChips(items: statusAndTagLabels(item))
                }

                if !item.reasons.isEmpty {
                    Text(item.reasons.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let photos = item.photos, !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos) { photo in
                                NavigationLink {
                                    PhotoDetailView(photoID: photo.id)
                                } label: {
                                    RemoteImage(url: MediaURL.resolve(photo.thumb))
                                        .frame(width: 88, height: 66)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func detailTimeRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusAndTagLabels(_ item: ForecastItem) -> [String] {
        var labels = item.tags.map(ToolUI.forecastTagLabel)
        if let status = item.status, !status.isEmpty {
            labels.insert(L10n.format("航班状态 · %@", status), at: 0)
        }
        return labels
    }

    private func probabilityText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.001 {
            return String(format: "%.0f%%", value)
        }
        return String(format: "%.1f%%", value)
    }

    private func directionColor(_ item: ForecastItem) -> Color {
        item.isArrival ? .blue : .orange
    }

    private func forecastEvents(
        _ result: ForecastResp,
        filter: ForecastDirectionFilter,
        timeZone: TimeZone
    ) -> [ForecastEvent] {
        result.items.compactMap { item in
            guard filter.includes(item),
                  let date = ForecastTime.date(from: item.eventTimeISO),
                  ForecastTime.day(date, in: timeZone) == result.day else {
                return nil
            }
            return ForecastEvent(item: item, date: date, minute: ForecastTime.minute(date, in: timeZone))
        }
        .sorted {
            if $0.date == $1.date { return $0.item.title < $1.item.title }
            return $0.date < $1.date
        }
    }

    private func adjacentEvent(in events: [ForecastEvent]) -> ForecastEvent? {
        events.first(where: { $0.minute > selectedMinute })
            ?? events.last(where: { $0.minute < selectedMinute })
    }

    private var canQuery: Bool {
        !airport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func query(forceRefresh: Bool) async {
        guard canQuery else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let airportQuery = airport.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownTimeZoneIdentifier = loadedAirportQuery.caseInsensitiveCompare(airportQuery) == .orderedSame
            ? result?.airportInfo?.timezone
            : nil
        let initialTimeZone = ForecastTime.timeZone(knownTimeZoneIdentifier)
        let initialDay = ForecastTime.day(Date(), in: initialTimeZone)

        do {
            var response = try await fetchForecast(
                airport: airportQuery,
                day: initialDay,
                forceRefresh: forceRefresh
            )

            if let identifier = response.airportInfo?.timezone,
               let airportTimeZone = TimeZone(identifier: identifier) {
                let airportToday = ForecastTime.day(Date(), in: airportTimeZone)
                if response.day != airportToday {
                    response = try await fetchForecast(
                        airport: airportQuery,
                        day: airportToday,
                        forceRefresh: forceRefresh
                    )
                }
            }

            apply(response, airportQuery: airportQuery)
        } catch {
            errorMessage = error.localizedDescription
            result = nil
        }
    }

    private func fetchForecast(airport: String, day: String, forceRefresh: Bool) async throws -> ForecastResp {
        var query = [
            URLQueryItem(name: "airport", value: airport),
            URLQueryItem(name: "day", value: day),
            URLQueryItem(name: "mode", value: "both"),
        ]
        if forceRefresh {
            query.append(URLQueryItem(name: "refresh", value: "true"))
        }
        return try await APIClient.shared.get("api/aviation-intel/forecast", query: query)
    }

    private func apply(_ response: ForecastResp, airportQuery: String) {
        let timeZone = ForecastTime.timeZone(response.airportInfo?.timezone)
        let allEvents = forecastEvents(response, filter: .all, timeZone: timeZone)
        let airportToday = ForecastTime.day(Date(), in: timeZone)

        result = response
        loadedAirportQuery = airportQuery
        directionFilter = .all
        selectedMinute = response.day == airportToday
            ? ForecastTime.minute(Date(), in: timeZone)
            : (allEvents.first?.minute ?? 12 * 60)
    }
}

private struct RareFlightTimeline: View {
    let events: [ForecastEvent]
    let day: String
    let timeZone: TimeZone
    @Binding var selectedMinute: Int

    @State private var pointsPerMinute: CGFloat = 1.35
    @State private var dragStartMinute: Int?
    @State private var zoomStartScale: CGFloat?

    private let defaultPointsPerMinute: CGFloat = 1.35
    private let minimumPointsPerMinute: CGFloat = 0.45
    private let maximumPointsPerMinute: CGFloat = 4.5
    private let scaleY: CGFloat = 66
    private let timelineHeight: CGFloat = 238

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let nowMinute = ForecastTime.day(context.date, in: timeZone) == day
                ? ForecastTime.minute(context.date, in: timeZone)
                : nil
            timeline(nowMinute: nowMinute)
        }
    }

    private func timeline(nowMinute: Int?) -> some View {
        GlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.string("单指拖动 · 双指缩放"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(ForecastTime.clock(minute: selectedMinute)) · \(ForecastTime.zoneLabel(timeZone))")
                            .font(.title3.monospacedDigit().weight(.bold))
                    }

                    Spacer(minLength: 4)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            pointsPerMinute = defaultPointsPerMinute
                        }
                    } label: {
                        Text(String(format: "%.1f×", pointsPerMinute / defaultPointsPerMinute))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .background(AppTheme.elevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.string("缩放比例，点按恢复默认"))

                    if let nowMinute, abs(nowMinute - selectedMinute) > 1 {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedMinute = nowMinute
                            }
                        } label: {
                            Label(L10n.string("回到现在"), systemImage: "location.fill")
                                .font(.caption.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                GeometryReader { geometry in
                    timelineCanvas(nowMinute: nowMinute, width: geometry.size.width)
                }
                .frame(height: timelineHeight)
            }
            .padding(.bottom, 10)
        }
    }

    private func timelineCanvas(nowMinute: Int?, width: CGFloat) -> some View {
        let markers = TimelineMarker.build(from: events, pointsPerMinute: pointsPerMinute)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())

            Path { path in
                path.move(to: CGPoint(x: xPosition(for: 0, width: width), y: scaleY))
                path.addLine(to: CGPoint(x: xPosition(for: 1_439, width: width), y: scaleY))
            }
            .stroke(Color.secondary.opacity(0.55), lineWidth: 1)

            ForEach(0..<97, id: \.self) { quarter in
                let minute = min(quarter * 15, 1_439)
                let x = xPosition(for: minute, width: width)
                let isHour = minute % 60 == 0 || quarter == 96

                Rectangle()
                    .fill(isHour ? Color.primary.opacity(0.65) : Color.secondary.opacity(0.35))
                    .frame(width: isHour ? 1.5 : 1, height: isHour ? 16 : 8)
                    .position(x: x, y: scaleY)

                if isHour {
                    Text(ForecastTime.clock(minute: minute))
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .position(x: x, y: scaleY - 22)
                }
            }

            if let nowMinute {
                currentTimeIndicator(minute: nowMinute, width: width)
            }

            ForEach(markers) { marker in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedMinute = marker.minute
                    }
                } label: {
                    markerLabel(marker)
                }
                .buttonStyle(.plain)
                .position(x: xPosition(for: marker.minute, width: width), y: 96 + CGFloat(marker.lane) * 38)
                .accessibilityLabel(marker.accessibilityLabel)
                .accessibilityHint(L10n.string("点按查看这个时间附近的航班"))
            }

            selectedTimeIndicator(width: width)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(timelineGesture)
        .simultaneousGesture(tapGesture(width: width))
        .clipped()
    }

    private func currentTimeIndicator(minute: Int, width: CGFloat) -> some View {
        let x = xPosition(for: minute, width: width)
        return ZStack(alignment: .top) {
            Path { path in
                path.move(to: CGPoint(x: x, y: 20))
                path.addLine(to: CGPoint(x: x, y: timelineHeight - 6))
            }
            .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

            Text(L10n.string("现在"))
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.red, in: Capsule())
                .foregroundStyle(.white)
                .position(x: x, y: 12)
        }
    }

    private func selectedTimeIndicator(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(AppTheme.accent)
                .frame(width: 2.5, height: timelineHeight - 24)
                .position(x: width / 2, y: timelineHeight / 2 + 12)

            Image(systemName: "triangle.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.accent)
                .rotationEffect(.degrees(180))
                .position(x: width / 2, y: scaleY - 10)
        }
        .allowsHitTesting(false)
    }

    private func markerLabel(_ marker: TimelineMarker) -> some View {
        let title = marker.events.count == 1
            ? marker.events[0].item.title
            : L10n.format("%d 架", marker.events.count)

        return HStack(spacing: 5) {
            Image(systemName: marker.symbol)
                .font(.caption2.weight(.bold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(width: 96)
        .frame(minHeight: 32)
        .background(marker.color.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(marker.color.opacity(0.4), lineWidth: 1))
        .foregroundStyle(marker.color)
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }

    private var timelineGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .simultaneously(with: MagnificationGesture())
            .onChanged { value in
                if let magnification = value.second {
                    let baseScale = zoomStartScale ?? pointsPerMinute
                    if zoomStartScale == nil {
                        zoomStartScale = baseScale
                        dragStartMinute = nil
                    }
                    pointsPerMinute = min(
                        max(baseScale * magnification, minimumPointsPerMinute),
                        maximumPointsPerMinute
                    )
                } else if let drag = value.first {
                    let baseMinute = dragStartMinute ?? selectedMinute
                    if dragStartMinute == nil {
                        dragStartMinute = baseMinute
                    }
                    let minuteDelta = Int((drag.translation.width / pointsPerMinute).rounded())
                    selectedMinute = min(max(baseMinute - minuteDelta, 0), 1_439)
                }
            }
            .onEnded { _ in
                dragStartMinute = nil
                zoomStartScale = nil
            }
    }

    private func tapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                withAnimation(.easeOut(duration: 0.18)) {
                    selectedMinute = minute(at: value.location.x, width: width)
                }
            }
    }

    private func xPosition(for minute: Int, width: CGFloat) -> CGFloat {
        width / 2 + CGFloat(minute - selectedMinute) * pointsPerMinute
    }

    private func minute(at x: CGFloat, width: CGFloat) -> Int {
        let minute = selectedMinute + Int(((x - width / 2) / pointsPerMinute).rounded())
        return min(max(minute, 0), 1_439)
    }
}

private struct TimelineMarker: Identifiable {
    let events: [ForecastEvent]
    let minute: Int
    let lane: Int

    var id: String { events.map(\.id).joined(separator: "|") }

    var symbol: String {
        let hasArrival = events.contains(where: { $0.item.isArrival })
        let hasDeparture = events.contains(where: { !$0.item.isArrival })
        if hasArrival && hasDeparture { return "arrow.left.and.right" }
        return hasArrival ? "arrow.down.left" : "arrow.up.right"
    }

    var color: Color {
        let hasArrival = events.contains(where: { $0.item.isArrival })
        let hasDeparture = events.contains(where: { !$0.item.isArrival })
        if hasArrival && hasDeparture { return .purple }
        return hasArrival ? .blue : .orange
    }

    var accessibilityLabel: String {
        let flights = events.map { "\($0.item.directionTitle) \($0.item.title)" }.joined(separator: "，")
        return "\(ForecastTime.clock(minute: minute))，\(flights)"
    }

    static func build(from events: [ForecastEvent], pointsPerMinute: CGFloat) -> [TimelineMarker] {
        guard !events.isEmpty else { return [] }

        let clusterWindow = max(8, Int((20 / pointsPerMinute).rounded(.up)))
        var groups: [[ForecastEvent]] = []
        for event in events.sorted(by: { $0.minute < $1.minute }) {
            if let lastEvent = groups.last?.last, event.minute - lastEvent.minute <= clusterWindow {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
            }
        }

        let laneSpacing = max(20, Int((106 / pointsPerMinute).rounded(.up)))
        var lastMinuteByLane = Array(repeating: -10_000, count: 4)
        return groups.map { group in
            let minute = Int((Double(group.map(\.minute).reduce(0, +)) / Double(group.count)).rounded())
            let lane = lastMinuteByLane.firstIndex(where: { minute - $0 >= laneSpacing })
                ?? lastMinuteByLane.enumerated().min(by: { $0.element < $1.element })!.offset
            lastMinuteByLane[lane] = minute
            return TimelineMarker(events: group, minute: minute, lane: lane)
        }
    }
}

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlexibleChipWrap(items: items)
    }
}

private struct FlexibleChipWrap: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.elevated, in: Capsule())
            }
        }
    }
}
