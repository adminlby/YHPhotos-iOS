import MapKit
import SwiftUI

struct MapBrowserView: View {
    @State private var airports: [MapAirport] = []
    @State private var selectedAirportID: Int?
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30, longitude: 108),
            span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 45)
        )
    )
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, selection: $selectedAirportID) {
                ForEach(airports) { airport in
                    Annotation(airport.iata ?? airport.name, coordinate: coordinate(airport)) {
                        VStack(spacing: 3) {
                            Image(systemName: "airplane.circle.fill")
                                .font(.title).foregroundStyle(AppTheme.accent)
                                .background(.black.opacity(0.8), in: Circle())
                            Text(airport.count.compactCount)
                                .font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .tag(airport.id)
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .ignoresSafeArea(edges: .bottom)

            if let airport = selectedAirport {
                airportCard(airport).padding(.horizontal, 18).padding(.bottom, 14)
            } else {
                GlassPanel(cornerRadius: 18) {
                    HStack {
                        Image(systemName: "map.fill").foregroundStyle(AppTheme.accent)
                        Text("\(airports.count) 个有作品的机场").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("轻点标记查看").font(.caption).foregroundStyle(.secondary)
                    }.padding(14)
                }
                .padding(.horizontal, 18).padding(.bottom, 14)
            }

            if isLoading { ProgressView().controlSize(.large) }
        }
        .navigationTitle("地图浏览")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { fitAll() } label: { Image(systemName: "scope") }
            }
        }
        .task { await load() }
        .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("重试") { Task { await load() } }
        } message: { Text(errorMessage ?? "") }
    }

    private var selectedAirport: MapAirport? { airports.first { $0.id == selectedAirportID } }

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
                    Text("件作品").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(16)
        }
    }

    private func coordinate(_ airport: MapAirport) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: airport.lat, longitude: airport.lng)
    }

    private func fitAll() {
        position = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30, longitude: 108),
            span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 45)
        ))
    }

    @MainActor
    private func load() async {
        isLoading = true
        do {
            airports = try await APIClient.shared.get("api/map/airports")
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}
