import CoreLocation
import Foundation

enum MXPlaceCategory: String, Codable, CaseIterable, Identifiable {
    case home, hotel, airport, mall, restaurant, cafe, nightlife, date, landmark, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .hotel: return "Hotel"
        case .airport: return "Airport"
        case .mall: return "Mall"
        case .restaurant: return "Restaurant"
        case .cafe: return "Café"
        case .nightlife: return "Nightlife"
        case .date: return "Date"
        case .landmark: return "Landmark"
        case .other: return "Place"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .hotel: return "bed.double.fill"
        case .airport: return "airplane"
        case .mall: return "bag.fill"
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .nightlife: return "moon.stars.fill"
        case .date: return "heart.fill"
        case .landmark: return "mappin.and.ellipse"
        case .other: return "star.fill"
        }
    }
}

struct MXVisitRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let date: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MXTripStop: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var category: MXPlaceCategory
    var city: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MXFavoriteMeta: Codable {
    var category: MXPlaceCategory
    var city: String
}

struct MXNamedCoordinate: Identifiable {
    let id = UUID()
    let name: String
    let category: MXPlaceCategory
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MXCityProfile: Identifiable {
    var id: String { name }
    let name: String
    let areas: [MXNamedCoordinate]
    let travelStops: [MXNamedCoordinate]

    static let all: [MXCityProfile] = [
        MXCityProfile(
            name: "Manila",
            areas: [
                MXNamedCoordinate(name: "BGC", category: .date, latitude: 14.5508, longitude: 121.0509),
                MXNamedCoordinate(name: "Makati CBD", category: .date, latitude: 14.5547, longitude: 121.0244),
                MXNamedCoordinate(name: "Poblacion", category: .nightlife, latitude: 14.5653, longitude: 121.0290),
                MXNamedCoordinate(name: "Tomas Morato", category: .nightlife, latitude: 14.6327, longitude: 121.0359),
                MXNamedCoordinate(name: "Ortigas", category: .date, latitude: 14.5854, longitude: 121.0611),
                MXNamedCoordinate(name: "Malate", category: .nightlife, latitude: 14.5720, longitude: 120.9900)
            ],
            travelStops: [
                MXNamedCoordinate(name: "NAIA", category: .airport, latitude: 14.5086, longitude: 121.0198),
                MXNamedCoordinate(name: "BGC", category: .hotel, latitude: 14.5508, longitude: 121.0509),
                MXNamedCoordinate(name: "SM Mall of Asia", category: .mall, latitude: 14.5354, longitude: 120.9822),
                MXNamedCoordinate(name: "Greenbelt", category: .restaurant, latitude: 14.5520, longitude: 121.0207),
                MXNamedCoordinate(name: "Poblacion", category: .nightlife, latitude: 14.5653, longitude: 121.0290)
            ]
        ),
        MXCityProfile(
            name: "Jakarta",
            areas: [
                MXNamedCoordinate(name: "SCBD", category: .date, latitude: -6.2259, longitude: 106.8094),
                MXNamedCoordinate(name: "Senopati", category: .restaurant, latitude: -6.2318, longitude: 106.8061),
                MXNamedCoordinate(name: "Kemang", category: .nightlife, latitude: -6.2607, longitude: 106.8132),
                MXNamedCoordinate(name: "Menteng", category: .date, latitude: -6.1944, longitude: 106.8298),
                MXNamedCoordinate(name: "Kuningan", category: .date, latitude: -6.2241, longitude: 106.8328)
            ],
            travelStops: [
                MXNamedCoordinate(name: "Soekarno-Hatta", category: .airport, latitude: -6.1256, longitude: 106.6559),
                MXNamedCoordinate(name: "SCBD", category: .hotel, latitude: -6.2259, longitude: 106.8094),
                MXNamedCoordinate(name: "Grand Indonesia", category: .mall, latitude: -6.1950, longitude: 106.8200),
                MXNamedCoordinate(name: "Senopati", category: .restaurant, latitude: -6.2318, longitude: 106.8061),
                MXNamedCoordinate(name: "Kemang", category: .nightlife, latitude: -6.2607, longitude: 106.8132)
            ]
        ),
        MXCityProfile(
            name: "Bangkok",
            areas: [
                MXNamedCoordinate(name: "Sukhumvit", category: .date, latitude: 13.7367, longitude: 100.5601),
                MXNamedCoordinate(name: "Thonglor", category: .nightlife, latitude: 13.7308, longitude: 100.5823),
                MXNamedCoordinate(name: "Siam", category: .mall, latitude: 13.7466, longitude: 100.5347),
                MXNamedCoordinate(name: "Silom", category: .nightlife, latitude: 13.7248, longitude: 100.5342)
            ],
            travelStops: [
                MXNamedCoordinate(name: "BKK Airport", category: .airport, latitude: 13.6900, longitude: 100.7501),
                MXNamedCoordinate(name: "Sukhumvit", category: .hotel, latitude: 13.7367, longitude: 100.5601),
                MXNamedCoordinate(name: "Siam", category: .mall, latitude: 13.7466, longitude: 100.5347),
                MXNamedCoordinate(name: "Terminal 21", category: .restaurant, latitude: 13.7379, longitude: 100.5604),
                MXNamedCoordinate(name: "Thonglor", category: .nightlife, latitude: 13.7308, longitude: 100.5823)
            ]
        ),
        MXCityProfile(
            name: "Baghdad",
            areas: [
                MXNamedCoordinate(name: "Mansour", category: .date, latitude: 33.3146, longitude: 44.3364),
                MXNamedCoordinate(name: "Karrada", category: .restaurant, latitude: 33.3025, longitude: 44.4430),
                MXNamedCoordinate(name: "Jadriya", category: .cafe, latitude: 33.2735, longitude: 44.3788)
            ],
            travelStops: [
                MXNamedCoordinate(name: "Baghdad Airport", category: .airport, latitude: 33.2625, longitude: 44.2346),
                MXNamedCoordinate(name: "Mansour", category: .hotel, latitude: 33.3146, longitude: 44.3364),
                MXNamedCoordinate(name: "Baghdad Mall", category: .mall, latitude: 33.3150, longitude: 44.3370),
                MXNamedCoordinate(name: "Karrada", category: .restaurant, latitude: 33.3025, longitude: 44.4430),
                MXNamedCoordinate(name: "Jadriya", category: .nightlife, latitude: 33.2735, longitude: 44.3788)
            ]
        )
    ]

    static func named(_ name: String) -> MXCityProfile {
        all.first(where: { $0.name == name }) ?? all[0]
    }
}

enum MXTravelData {
    private static let historyKey = "mx.travel.history.v1"
    private static let tripKey = "mx.travel.stops.v1"
    private static let favoriteMetaKey = "mx.travel.favoriteMeta.v1"

    static func loadHistory() -> [MXVisitRecord] {
        load([MXVisitRecord].self, key: historyKey) ?? []
    }

    static func loadTripStops() -> [MXTripStop] {
        load([MXTripStop].self, key: tripKey) ?? []
    }

    static func saveTripStops(_ stops: [MXTripStop]) {
        save(stops, key: tripKey)
    }

    static func recordVisit(_ coordinate: CLLocationCoordinate2D) {
        var records = loadHistory()
        if let first = records.first,
           abs(first.latitude - coordinate.latitude) < 0.000001,
           abs(first.longitude - coordinate.longitude) < 0.000001,
           Date().timeIntervalSince(first.date) < 5 {
            return
        }
        records.insert(
            MXVisitRecord(
                id: UUID(),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                date: Date()
            ),
            at: 0
        )
        if records.count > 150 {
            records = Array(records.prefix(150))
        }
        save(records, key: historyKey)
    }

    static func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    static func setFavoriteMeta(id: String, category: MXPlaceCategory, city: String) {
        var all = favoriteMeta()
        all[id] = MXFavoriteMeta(category: category, city: city)
        save(all, key: favoriteMetaKey)
    }

    static func meta(for id: String) -> MXFavoriteMeta? {
        favoriteMeta()[id]
    }

    private static func favoriteMeta() -> [String: MXFavoriteMeta] {
        load([String: MXFavoriteMeta].self, key: favoriteMetaKey) ?? [:]
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
