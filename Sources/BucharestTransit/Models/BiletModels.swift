import Foundation

public struct BiletAccount: Codable, Sendable {
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let studentStatus: Bool?

    public var fullName: String? {
        let name = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { return name }
        return email?.split(separator: "@").first.map(String.init)
    }

    public var initials: String {
        return fullName?.split(whereSeparator: { $0.isWhitespace })
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased() ?? "?"
    }

}

public struct BiletStatus: Codable, Sendable {
    public let authenticated: Bool
    public let account: BiletAccount?
    public let activeTicketsCount: Int?
    public let availableTicketsCount: Int?
}

public struct Ticket: Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public let type: String?
    public let seriesCode: String?
    public let validFromDate: String?
    public let validToDate: String?
    public var remainingSeconds: Int?
    public let isElev: Bool?
    public let qrBase64Payload: String?
    public let price: Double?

    public var isStudentElev: Bool {
        let normalizedTitle = title.lowercased()
        return isElev == true ||
            normalizedTitle.contains("elev") ||
            normalizedTitle.contains("student") ||
            normalizedTitle.contains("pupil")
    }
}
