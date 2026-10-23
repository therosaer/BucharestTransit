import Foundation
import OSLog
import Security

// MARK: - TransitAPIService (Direct Standalone Actor)

public actor TransitAPIService {
    public static let shared = TransitAPIService()

    // Upstream Official Endpoints
    private let moBiApiURL = URL(string: "https://mo-bi.ro/python_api/")!
    private let stbBackofficeURL = "https://online.stbsa.ro:8080/external"

    // Rate Limiting & In-Memory State (10.5s cooldown matching mo-bi upstream rules)
    private var lastMoBiCall: Date?
    private var cachedVehicles: [Vehicle] = []
    private var lastStats: TransitStats?
    private let logger = Logger(subsystem: "BucharestTransit", category: "Ticketing")

    // Local Persistence Keys
    private let tokenKey = "stb_bilet_token"
    private let accountKey = "stb_bilet_account_data"
    private let bearerAuthorizationPrefix = "Bearer "

    public nonisolated static func getInitialData() -> ([Vehicle], TransitStats) {
        return loadSnapshotData()
    }

    private init() {
        UserDefaults.standard.removeObject(forKey: "custom_server_url")
        let (initialVehicles, initialStats) = Self.loadSnapshotData()
        self.cachedVehicles = initialVehicles
        self.lastStats = initialStats
    }

    // MARK: - Snapshot Fallback Loader (Instant Fleet on Cold Boot)

    private static func loadSnapshotData() -> ([Vehicle], TransitStats) {
        var candidates: [URL?] = []
        #if SWIFT_PACKAGE
        candidates.append(Bundle.module.url(forResource: "snapshot_vehicles", withExtension: "json", subdirectory: "Resources"))
        candidates.append(Bundle.module.url(forResource: "snapshot_vehicles", withExtension: "json"))
        candidates.append(Bundle.module.bundleURL.appendingPathComponent("Resources/snapshot_vehicles.json"))
        #endif
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("BucharestTransit_BucharestTransit.bundle/Resources/snapshot_vehicles.json"))
        candidates.append(Bundle.main.resourceURL?.appendingPathComponent("BucharestTransit_BucharestTransit.bundle/Resources/snapshot_vehicles.json"))
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Resources/snapshot_vehicles.json"))
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("snapshot_vehicles.json"))

        for case let url? in candidates {
            if let data = try? Data(contentsOf: url),
               let rawList = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let processed = processRawVehiclesArray(rawList, source: .snapshot)
                if !processed.isEmpty {
                    return (processed, computeStats(from: processed))
                }
            }
        }

        let empty: [Vehicle] = []
        return (empty, computeStats(from: empty))
    }

    // MARK: - Live Vehicles (Direct mo-bi.ro Feed)

    public func fetchVehicles(line: String? = nil, mode: String = "all", crowded: Bool = false) async -> [Vehicle] {
        let shouldFetchLive: Bool = {
            guard let last = lastMoBiCall else { return true }
            return Date().timeIntervalSince(last) >= 10.5 || cachedVehicles.isEmpty
        }()

        if shouldFetchLive {
            await downloadAndProcessLiveFeed()
        }

        return filterVehicles(cachedVehicles, line: line, mode: mode, crowded: crowded)
    }

    private func downloadAndProcessLiveFeed() async {
        var request = URLRequest(url: moBiApiURL)
        request.timeoutInterval = 10.0
        // Exact User-Agent proven to be accepted by mo-bi upstream
        request.setValue("BucharestTransitInteractiveApp/1.0 (Mozilla/5.0)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }

            guard let rawList = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }

            let processed = Self.processRawVehiclesArray(rawList, source: .live)
            if !processed.isEmpty {
                self.cachedVehicles = processed
                self.lastMoBiCall = Date()
                self.lastStats = Self.computeStats(from: processed)
            }
        } catch {
            // Keep in-memory cached/snapshot vehicles on transient network disruption
        }
    }

    private static func processRawVehiclesArray(_ rawList: [[String: Any]], source: VehicleDataSource) -> [Vehicle] {
        var processed: [Vehicle] = []
        for item in rawList {
            if let v = enrichRawVehicleItem(item, source: source) {
                processed.append(v)
            }
        }
        return processed
    }

    private static func enrichRawVehicleItem(_ item: [String: Any], source: VehicleDataSource) -> Vehicle? {
        let vInfo = item["vehicle"] as? [String: Any]
        let trip = vInfo?["trip"] as? [String: Any]
        let vehIdent = vInfo?["vehicle"] as? [String: Any]
        let pos = vInfo?["position"] as? [String: Any]
        let psg = vInfo?["passenger_info"] as? [String: Any]

        let lat = (pos?["latitude"] as? Double) ?? (pos?["latitude"] as? NSNumber)?.doubleValue
        let lon = (pos?["longitude"] as? Double) ?? (pos?["longitude"] as? NSNumber)?.doubleValue

        // Filter coordinates strictly within Bucharest / Ilfov transit perimeter
        guard let lat = lat, let lon = lon, lat >= 44.0 && lat <= 44.9 && lon >= 25.5 && lon <= 26.8 else {
            return nil
        }

        let routeIdVal = trip?["route_id"]
        let routeIdStr: String? = {
            if let s = routeIdVal as? String, s != "None" && !s.isEmpty { return s }
            if let i = routeIdVal as? Int { return String(i) }
            if let n = routeIdVal as? NSNumber { return n.stringValue }
            return nil
        }()

        let routeShortName = (trip?["route_short_name"] as? String) ?? (trip?["route_name"] as? String)

        let meta: RouteMetadata? = {
            if let r = routeIdStr, let m = LocalTransitDataManager.shared.routeMetadata(for: r) { return m }
            if let r = routeShortName, let m = LocalTransitDataManager.shared.metadataForLine(r) { return m }
            return nil
        }()

        let lineName: String
        let vType: VehicleType
        if let m = meta {
            lineName = m.line
            switch m.type.lowercased() {
            case "tram": vType = .tram
            case "trolley", "trolleybus": vType = .trolley
            case "regional_bus", "regional": vType = .regional
            case "night_bus", "night": vType = .night
            case "metro": vType = .metro
            default: vType = .bus
            }
        } else if let s = routeShortName, !s.isEmpty && s != "None" {
            lineName = s
            vType = .bus
        } else if let r = routeIdStr {
            lineName = "R\(r)"
            vType = .bus
        } else {
            lineName = "STB"
            vType = .bus
        }

        let onBoard = (psg?["on_board"] as? Int) ?? (psg?["on_board"] as? NSNumber)?.intValue
        let crowdedness: CrowdednessLevel? = onBoard.map { ob in
            if ob <= 15 { return .low }
            if ob <= 40 { return .moderate }
            return .high
        }

        let vehIdVal = vehIdent?["id"]
        let vehIdStr: String? = {
            if let s = vehIdVal as? String { return s }
            if let i = vehIdVal as? Int { return String(i) }
            if let n = vehIdVal as? NSNumber { return n.stringValue }
            if let s = item["id"] as? String { return s }
            if let i = item["id"] as? Int { return String(i) }
            if let n = item["id"] as? NSNumber { return n.stringValue }
            return nil
        }()
        guard let vehIdStr, !vehIdStr.isEmpty, vehIdStr != "None" else { return nil }

        let rawPlate = vehIdent?["license_plate"] as? String
        let plate = (rawPlate != nil && !rawPlate!.isEmpty && rawPlate != "None") ? rawPlate : nil
        let directionId = (trip?["direction_id"] as? Int) ?? (trip?["direction_id"] as? NSNumber)?.intValue
        let posTimestamp = (pos?["timestamp"] as? String) ?? (item["timestamp"] as? String)
        let lastPositionUpdate = posTimestamp.flatMap(Self.date(from:))
        let gpsAgeMinutes = lastPositionUpdate.map { max(0, Int(Date().timeIntervalSince($0) / 60)) }
        let isStaleGps: Bool? = source == .snapshot ? true : gpsAgeMinutes.map { $0 > 2 }
        let speed = Self.number(pos?["speed"])
        let bearing = Self.number(pos?["bearing"])

        return Vehicle(
            id: "stb-\(vehIdStr)",
            label: plate,
            line: lineName,
            routeId: routeIdStr,
            directionId: directionId,
            latitude: lat,
            longitude: lon,
            bearing: bearing,
            speed: speed,
            crowdedness: crowdedness,
            isOnRoute: nil,
            isOffRoute: nil,
            distanceToRouteKm: nil,
            depotName: nil,
            gpsTimestamp: posTimestamp,
            gpsAgeMinutes: gpsAgeMinutes,
            lastPositionUpdate: lastPositionUpdate,
            isStaleGps: isStaleGps,
            vehicleType: vType,
            dataSource: source
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func date(from timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: timestamp)
        }()
    }

    private func filterVehicles(_ list: [Vehicle], line: String?, mode: String, crowded: Bool) -> [Vehicle] {
        var res = list

        if mode != "all" {
            res = res.filter { v in
                switch mode {
                case "tram": return v.vehicleType == .tram
                case "trolley": return v.vehicleType == .trolley
                case "bus": return v.vehicleType == .bus || v.vehicleType == .regional
                case "metro": return v.vehicleType == .metro
                default: return true
                }
            }
        }

        if let l = line, !l.isEmpty {
            let q = l.uppercased().trimmingCharacters(in: .whitespaces)
            res = res.filter { $0.line.uppercased() == q || ($0.label?.uppercased().contains(q) == true) }
        }

        if crowded {
            res = res.filter { $0.crowdedness == .high || $0.crowdedness == .moderate }
        }

        return res
    }

    private static func computeStats(from vehicles: [Vehicle]) -> TransitStats {
        var breakdown: [String: Int] = ["bus": 0, "tram": 0, "trolley": 0, "metro": 0]
        var crowdedCount = 0
        var hasCrowdingData = false
        var activeLines = Set<String>()

        for v in vehicles {
            activeLines.insert(v.line)
            if v.crowdedness != nil { hasCrowdingData = true }
            if v.crowdedness == .high { crowdedCount += 1 }
            switch v.vehicleType {
            case .tram: breakdown["tram", default: 0] += 1
            case .trolley: breakdown["trolley", default: 0] += 1
            case .metro: breakdown["metro", default: 0] += 1
            default: breakdown["bus", default: 0] += 1
            }
        }

        return TransitStats(
            totalVehicles: vehicles.count,
            activeLines: activeLines.count,
            crowdedVehicles: hasCrowdingData ? crowdedCount : nil,
            avgSpeed: {
                let speeds = vehicles.compactMap(\.speed)
                guard !speeds.isEmpty else { return nil }
                return speeds.reduce(0, +) / Double(speeds.count)
            }(),
            byType: breakdown
        )
    }

    public func triggerRefresh() async {
        self.lastMoBiCall = nil
        await downloadAndProcessLiveFeed()
    }

    // MARK: - Routes & Lines (Local Data Manager)

    public func fetchRoutes() async -> [Route] {
        let vehicles = cachedVehicles
        return LocalTransitDataManager.shared.allRoutes(liveVehicles: vehicles)
    }

    public func fetchLineDetails(line: String) async -> LineDetails? {
        let vehicles = cachedVehicles
        if let details = LocalTransitDataManager.shared.lineDetails(line: line, liveVehicles: vehicles) {
            return details
        }
        return nil
    }

    public func fetchStats() async -> TransitStats? {
        return lastStats
    }

    // MARK: - Bilet TB Official Backoffice API (online.stbsa.ro:8080)

    public func fetchBiletStatus() async -> BiletStatus {
        do {
            guard let token = try storedTicketToken(), !token.isEmpty else {
                return BiletStatus(authenticated: false, account: nil, activeTicketsCount: 0, availableTicketsCount: 0)
            }
            if token.hasPrefix("token_stb_elev_") || token.hasPrefix("mock_jwt_token_") {
                try deleteTicketToken()
                UserDefaults.standard.removeObject(forKey: accountKey)
                return BiletStatus(authenticated: false, account: nil, activeTicketsCount: 0, availableTicketsCount: 0)
            }
            if let acc = getStoredAccount() {
                return BiletStatus(
                    authenticated: true,
                    account: acc,
                    activeTicketsCount: nil,
                    availableTicketsCount: nil
                )
            }
            return BiletStatus(authenticated: false, account: nil, activeTicketsCount: 0, availableTicketsCount: 0)
        } catch {
            logger.error("Unable to read ticket session securely: \(error.localizedDescription, privacy: .public)")
            return BiletStatus(authenticated: false, account: nil, activeTicketsCount: 0, availableTicketsCount: 0)
        }
    }

    public func fetchBiletActiveTickets() async throws -> [Ticket] {
        guard let token = try storedTicketToken(), !token.isEmpty else {
            throw BiletAPIError.missingAuthentication
        }

        guard let url = URL(string: "\(stbBackofficeURL)/active-user-tickets") else {
            throw BiletAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = "{}".data(using: .utf8)
        req.timeoutInterval = 30
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let authorizationHeader = bearerAuthorizationPrefix + token
        req.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw BiletAPIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw BiletAPIError.httpStatus(http.statusCode)
        }
        guard let rawTickets = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw BiletAPIError.unexpectedPayload
        }

        return rawTickets.map { item in
            let package = item["ticketPackage"] as? [String: Any]
            let ticketObject = package?["ticket"] as? [String: Any]
            let title = (ticketObject?["name"] as? String) ?? (item["title"] as? String) ?? "Titlu de călătorie"
            let fareCategory = package?["fareCategory"] as? [String: Any]
            let categoryName = (fareCategory?["name"] as? String)?.lowercased()
            let normalizedTitle = title.lowercased()
            let isStudentOrPupil = categoryName == "elev" ||
                categoryName == "pupil" ||
                categoryName == "student" ||
                normalizedTitle.contains("elev") ||
                normalizedTitle.contains("student") ||
                normalizedTitle.contains("pupil")
            let validTo = item["validToDate"] as? String

            return Ticket(
                id: "\(item["id"] ?? UUID().uuidString)",
                title: title,
                type: isStudentOrPupil ? "student" : "calatorie",
                seriesCode: item["qrCodeCode"] as? String,
                validFromDate: item["validFromDate"] as? String,
                validToDate: validTo,
                remainingSeconds: calculateRemainingSeconds(vTo: validTo),
                isElev: isStudentOrPupil,
                qrBase64Payload: item["qrCode"] as? String,
                price: 0.0
            )
        }

    }

    public func loginBilet(username: String, password: String) async -> Bool {
        let u = username.trimmingCharacters(in: .whitespaces)
        let p = password.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty, !p.isEmpty else { return false }

        // Try direct official STB /authenticate endpoint
        if let authUrl = URL(string: "\(stbBackofficeURL)/authenticate") {
            var req = URLRequest(url: authUrl)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 4.0

            let payload: [String: Any] = [
                "username": u,
                "password": p,
                "rememberMe": true,
                "deviceUuid": "ios-stb-native-\(abs(u.hashValue))"
            ]

            if let bodyData = try? JSONSerialization.data(withJSONObject: payload) {
                req.httpBody = bodyData
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let token = json["id_token"] as? String {
                        do {
                            try storeTicketToken(token)
                            await fetchAndStoreAccount(token: token, defaultUsername: u)
                            return true
                        } catch {
                            logger.error("Unable to save ticket session securely: \(error.localizedDescription, privacy: .public)")
                            return false
                        }
                    }
                }
            }
        }

        return false
    }

    public func logoutBilet() async -> Bool {
        do {
            try deleteTicketToken()
        } catch {
            logger.error("Unable to remove ticket session from Keychain: \(error.localizedDescription, privacy: .public)")
            return false
        }
        UserDefaults.standard.removeObject(forKey: accountKey)
        return true
    }

    private func fetchAndStoreAccount(token: String, defaultUsername: String) async {
        if let accUrl = URL(string: "\(stbBackofficeURL)/account") {
            var req = URLRequest(url: accUrl)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 3.5
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let authorizationHeader = bearerAuthorizationPrefix + token
            req.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let firstName = json["firstName"] as? String
                let lastName = json["lastName"] as? String
                let email = json["email"] as? String ?? defaultUsername
                let phone = json["phone"] as? String
                let fareCat = json["fareCategory"] as? [String: Any]
                let categoryName = (fareCat?["name"] as? String)?.lowercased()
                let isStudentOrPupil = categoryName == "elev" || categoryName == "pupil" || categoryName == "student"

                let account = BiletAccount(
                    firstName: firstName,
                    lastName: lastName,
                    email: email,
                    phone: phone,
                    studentStatus: fareCat == nil ? nil : isStudentOrPupil
                )
                if let accData = try? JSONEncoder().encode(account) {
                    UserDefaults.standard.set(accData, forKey: accountKey)
                }
                return
            }
        }

        let account = BiletAccount(
            firstName: nil,
            lastName: nil,
            email: defaultUsername,
            phone: nil,
            studentStatus: nil
        )
        if let d = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(d, forKey: accountKey)
        }
    }

    private func getStoredAccount() -> BiletAccount? {
        guard let data = UserDefaults.standard.data(forKey: accountKey) else { return nil }
        return try? JSONDecoder().decode(BiletAccount.self, from: data)
    }

    private func storedTicketToken() throws -> String? {
        var query = ticketTokenQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw BiletAPIError.invalidKeychainData
            }
            return token
        }
        guard status == errSecItemNotFound else { throw BiletAPIError.keychain(status) }

        guard let legacyToken = UserDefaults.standard.string(forKey: tokenKey), !legacyToken.isEmpty else {
            return nil
        }
        try storeTicketToken(legacyToken)
        UserDefaults.standard.removeObject(forKey: tokenKey)
        return legacyToken
    }

    private func storeTicketToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else { throw BiletAPIError.invalidKeychainData }
        var query = ticketTokenQuery
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            UserDefaults.standard.removeObject(forKey: tokenKey)
            return
        }
        guard updateStatus == errSecItemNotFound else { throw BiletAPIError.keychain(updateStatus) }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw BiletAPIError.keychain(addStatus) }
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    private func deleteTicketToken() throws {
        let status = SecItemDelete(ticketTokenQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BiletAPIError.keychain(status)
        }
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    private var ticketTokenQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "BucharestTransit",
            kSecAttrAccount as String: tokenKey,
        ]
    }

    private func calculateRemainingSeconds(vTo: String?) -> Int? {
        guard let vTo = vTo else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: vTo) {
            return max(0, Int(date.timeIntervalSinceNow))
        }
        return nil
    }

    private enum BiletAPIError: LocalizedError {
        case missingAuthentication
        case invalidURL
        case invalidResponse
        case unexpectedPayload
        case httpStatus(Int)
        case keychain(OSStatus)
        case invalidKeychainData

        var errorDescription: String? {
            switch self {
            case .missingAuthentication:
                return "Sesiunea a expirat. Autentifică-te din nou."
            case .invalidURL:
                return "Adresa serviciului de titluri nu este validă."
            case .invalidResponse:
                return "Serviciul de titluri a trimis un răspuns invalid."
            case .unexpectedPayload:
                return "Răspunsul serviciului de titluri nu are formatul așteptat."
            case .httpStatus(let statusCode):
                return "Serviciul de titluri a răspuns cu eroarea \(statusCode)."
            case .keychain(let status):
                return "Sesiunea nu a putut fi salvată în Keychain (eroare \(status))."
            case .invalidKeychainData:
                return "Sesiunea salvată nu a putut fi citită."
            }
        }
    }

}
