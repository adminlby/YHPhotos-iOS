import CoreLocation
import MapKit
import SwiftUI

private enum YHMapProvider {
    case apple
    case amap

    var title: String { self == .amap ? L10n.string("高德地图") : L10n.string("Apple 地图") }
}

@MainActor
private final class MapRegionResolver: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var provider: YHMapProvider
    private let manager = CLLocationManager()

    override init() {
        provider = Locale.current.region?.identifier.uppercased() == "CN" ? .amap : .apple
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func resolve() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            if let country = placemark?.isoCountryCode?.uppercased() {
                provider = country == "CN" ? .amap : .apple
            } else {
                provider = Self.isMainland(location.coordinate) ? .amap : .apple
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }

    private static func isMainland(_ value: CLLocationCoordinate2D) -> Bool {
        let lat = value.latitude, lng = value.longitude
        guard (18.0...54.0).contains(lat), (73.0...135.0).contains(lng) else { return false }
        let hongKong = (22.08...22.62).contains(lat) && (113.78...114.52).contains(lng)
        let macau = (22.05...22.24).contains(lat) && (113.50...113.66).contains(lng)
        let taiwan = (21.75...25.65).contains(lat) && (119.25...122.15).contains(lng)
        return !hongKong && !macau && !taiwan
    }
}

struct MapBrowserView: View {
    @StateObject private var regionResolver = MapRegionResolver()
    @State private var airports: [MapAirport] = []
    @State private var selectedAirportID: Int?
    @State private var fitRevision = 0
    @State private var region = Self.defaultRegion
    @State private var isLoading = true
    @State private var errorMessage: String?

    fileprivate static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 30, longitude: 108),
        span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 45)
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            mapContent.ignoresSafeArea(edges: .bottom)
            VStack(spacing: 10) {
                HStack {
                    Label(regionResolver.provider.title, systemImage: regionResolver.provider == .amap ? "location.fill" : "apple.logo")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                    Spacer()
                }
                if let airport = selectedAirport { airportCard(airport) } else { summaryCard }
            }
            .padding(.horizontal, 18).padding(.bottom, 14)
            if isLoading { ProgressView().controlSize(.large) }
        }
        .navigationTitle(L10n.string("地图浏览"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { fitAll() } label: { Image(systemName: "scope") } } }
        .task { regionResolver.resolve(); await load() }
        .alert(L10n.string("加载失败"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L10n.string("重试")) { Task { await load() } }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder private var mapContent: some View {
        if regionResolver.provider == .amap {
            AutoNaviMapView(airports: airports, selectedAirportID: $selectedAirportID, fitRevision: fitRevision)
        } else {
            Map(coordinateRegion: $region, annotationItems: airports) { airport in
                MapAnnotation(coordinate: coordinate(airport)) {
                    Button {
                        selectedAirportID = airport.id
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "airplane.circle.fill").font(.title).foregroundStyle(AppTheme.accent)
                                .background(.black.opacity(0.8), in: Circle())
                            Text(airport.count.compactCount).font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedAirport: MapAirport? { airports.first { $0.id == selectedAirportID } }
    private var summaryCard: some View {
        GlassPanel(cornerRadius: 18) {
            HStack {
                Image(systemName: "map.fill").foregroundStyle(AppTheme.accent)
                Text(L10n.format("%d 个有作品的机场", airports.count)).font(.subheadline.weight(.semibold))
                Spacer()
                Text(L10n.string("轻点标记查看")).font(.caption).foregroundStyle(.secondary)
            }.padding(14)
        }
    }

    private func airportCard(_ airport: MapAirport) -> some View {
        GlassPanel(cornerRadius: 22) {
            HStack(spacing: 14) {
                Image(systemName: "airport.extreme.tower").font(.title2).foregroundStyle(AppTheme.accent)
                    .frame(width: 48, height: 48).background(AppTheme.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(airport.name).font(.headline).lineLimit(1)
                    Text([airport.city, airport.iata, airport.icao].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(airport.count.formatted()).font(.title3.bold()).monospacedDigit()
                    Text(L10n.string("件作品")).font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(16)
        }
    }

    private func coordinate(_ airport: MapAirport) -> CLLocationCoordinate2D { .init(latitude: airport.lat, longitude: airport.lng) }
    private func fitAll() { selectedAirportID = nil; region = Self.defaultRegion; fitRevision += 1 }

    @MainActor private func load() async {
        isLoading = true; defer { isLoading = false }
        do { airports = try await APIClient.shared.get("api/map/airports"); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

private final class AutoNaviTileOverlay: MKTileOverlay {
    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        let shard = (path.x + path.y) % 4 + 1
        return URL(string: "https://wprd0\(shard).is.autonavi.com/appmaptile?lang=zh_cn&size=1&scl=1&style=7&x=\(path.x)&y=\(path.y)&z=\(path.z)")!
    }
}

private final class AirportMapAnnotation: NSObject, MKAnnotation {
    let airportID: Int
    let title: String?
    let subtitle: String?
    dynamic var coordinate: CLLocationCoordinate2D

    init(_ airport: MapAirport) {
        airportID = airport.id
        title = airport.iata ?? airport.name
        subtitle = L10n.format("%d 件作品", airport.count)
        coordinate = Self.wgsToGCJ(latitude: airport.lat, longitude: airport.lng)
    }

    private static func wgsToGCJ(latitude: Double, longitude: Double) -> CLLocationCoordinate2D {
        guard longitude >= 72.004, longitude <= 137.8347, latitude >= 0.8293, latitude <= 55.8271 else { return .init(latitude: latitude, longitude: longitude) }
        let pi = Double.pi, a = 6_378_245.0, ee = 0.006693421622965943
        func tLat(_ x: Double, _ y: Double) -> Double {
            var v = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
            v += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
            v += (20*sin(y*pi) + 40*sin(y/3*pi))*2/3
            v += (160*sin(y/12*pi) + 320*sin(y*pi/30))*2/3
            return v
        }
        func tLng(_ x: Double, _ y: Double) -> Double {
            var v = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
            v += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
            v += (20*sin(x*pi) + 40*sin(x/3*pi))*2/3
            v += (150*sin(x/12*pi) + 300*sin(x/30*pi))*2/3
            return v
        }
        var dLat = tLat(longitude - 105, latitude - 35), dLng = tLng(longitude - 105, latitude - 35)
        let radLat = latitude / 180 * pi
        var magic = sin(radLat); magic = 1 - ee * magic * magic
        let root = sqrt(magic)
        dLat = dLat * 180 / ((a * (1 - ee) / (magic * root)) * pi)
        dLng = dLng * 180 / ((a / root * cos(radLat)) * pi)
        return .init(latitude: latitude + dLat, longitude: longitude + dLng)
    }
}

private struct AutoNaviMapView: UIViewRepresentable {
    let airports: [MapAirport]
    @Binding var selectedAirportID: Int?
    let fitRevision: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MapBrowserView.defaultRegion, animated: false)
        let overlay = AutoNaviTileOverlay(); overlay.canReplaceMapContent = true
        map.addOverlay(overlay, level: .aboveLabels)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        let current = Set(map.annotations.compactMap { ($0 as? AirportMapAnnotation)?.airportID })
        if current != Set(airports.map(\.id)) {
            map.removeAnnotations(map.annotations); map.addAnnotations(airports.map(AirportMapAnnotation.init))
        }
        if context.coordinator.lastFitRevision != fitRevision {
            context.coordinator.lastFitRevision = fitRevision
            map.setRegion(MapBrowserView.defaultRegion, animated: true)
        }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AutoNaviMapView
        var lastFitRevision = 0
        init(_ parent: AutoNaviMapView) { self.parent = parent }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            return MKTileOverlayRenderer(tileOverlay: tile)
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let airport = annotation as? AirportMapAnnotation else { return nil }
            let id = "airport"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation: airport, reuseIdentifier: id)
            view.annotation = airport; view.markerTintColor = UIColor(AppTheme.accent); view.glyphImage = UIImage(systemName: "airplane"); view.canShowCallout = true
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let airport = view.annotation as? AirportMapAnnotation { parent.selectedAirportID = airport.airportID }
        }
        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            if view.annotation is AirportMapAnnotation { parent.selectedAirportID = nil }
        }
    }
}
