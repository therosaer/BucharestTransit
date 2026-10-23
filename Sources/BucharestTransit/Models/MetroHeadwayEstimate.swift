import Foundation

public enum MetroHeadwayEstimate {
    private struct ServiceBand {
        let start: Int
        let end: Int
        let mainLine: [Double]
        let branch: [Double]?
    }

    private struct LineSchedule {
        let weekday: [ServiceBand]
        let weekend: [Double]
        let weekendLate: [Double]
        let weekendBranch: [Double]?
        let weekendBranchLate: [Double]?
    }

    private static let schedules: [String: LineSchedule] = [
        "M1": LineSchedule(
            weekday: [
                ServiceBand(start: 300, end: 390, mainLine: [9], branch: [18]),
                ServiceBand(start: 390, end: 420, mainLine: [8], branch: [18]),
                ServiceBand(start: 420, end: 580, mainLine: [6], branch: [18]),
                ServiceBand(start: 580, end: 660, mainLine: [9], branch: [20]),
                ServiceBand(start: 660, end: 820, mainLine: [10], branch: [20]),
                ServiceBand(start: 820, end: 940, mainLine: [9], branch: [18]),
                ServiceBand(start: 940, end: 1200, mainLine: [6], branch: [18]),
                ServiceBand(start: 1200, end: 1290, mainLine: [9], branch: [18]),
                ServiceBand(start: 1290, end: 1320, mainLine: [10], branch: [20]),
                ServiceBand(start: 1320, end: 1410, mainLine: [12], branch: [20])
            ],
            weekend: [9],
            weekendLate: [10, 11],
            weekendBranch: [18],
            weekendBranchLate: [20]
        ),
        "M2": LineSchedule(
            weekday: [
                ServiceBand(start: 300, end: 360, mainLine: [10], branch: nil),
                ServiceBand(start: 360, end: 405, mainLine: [6, 5], branch: nil),
                ServiceBand(start: 405, end: 540, mainLine: [4], branch: nil),
                ServiceBand(start: 540, end: 600, mainLine: [5, 6], branch: nil),
                ServiceBand(start: 600, end: 780, mainLine: [8, 9], branch: nil),
                ServiceBand(start: 780, end: 900, mainLine: [6], branch: nil),
                ServiceBand(start: 900, end: 1200, mainLine: [4], branch: nil),
                ServiceBand(start: 1200, end: 1260, mainLine: [5, 6], branch: nil),
                ServiceBand(start: 1260, end: 1320, mainLine: [8], branch: nil),
                ServiceBand(start: 1320, end: 1380, mainLine: [9, 11], branch: nil)
            ],
            weekend: [9],
            weekendLate: [10, 12],
            weekendBranch: nil,
            weekendBranchLate: nil
        ),
        "M3": LineSchedule(
            weekday: [
                ServiceBand(start: 300, end: 390, mainLine: [9], branch: [4.5]),
                ServiceBand(start: 390, end: 420, mainLine: [8], branch: [4]),
                ServiceBand(start: 420, end: 580, mainLine: [6], branch: [3]),
                ServiceBand(start: 580, end: 660, mainLine: [9], branch: [4.5]),
                ServiceBand(start: 660, end: 820, mainLine: [10], branch: [5]),
                ServiceBand(start: 820, end: 940, mainLine: [9], branch: [4.5]),
                ServiceBand(start: 940, end: 1200, mainLine: [6], branch: [3]),
                ServiceBand(start: 1200, end: 1290, mainLine: [9], branch: [4.5]),
                ServiceBand(start: 1290, end: 1320, mainLine: [10], branch: [5]),
                ServiceBand(start: 1320, end: 1410, mainLine: [12], branch: [6])
            ],
            weekend: [9],
            weekendLate: [10, 11],
            weekendBranch: [4.5],
            weekendBranchLate: [5, 5.5]
        ),
        "M4": LineSchedule(
            weekday: [
                ServiceBand(start: 300, end: 390, mainLine: [13, 12], branch: nil),
                ServiceBand(start: 390, end: 600, mainLine: [11], branch: nil),
                ServiceBand(start: 600, end: 870, mainLine: [12], branch: nil),
                ServiceBand(start: 870, end: 1170, mainLine: [11], branch: nil),
                ServiceBand(start: 1170, end: 1320, mainLine: [12], branch: nil),
                ServiceBand(start: 1320, end: 1380, mainLine: [13], branch: nil)
            ],
            weekend: [9],
            weekendLate: [10, 11],
            weekendBranch: nil,
            weekendBranchLate: nil
        ),
        "M5": LineSchedule(
            weekday: [
                ServiceBand(start: 300, end: 360, mainLine: [9], branch: [18]),
                ServiceBand(start: 360, end: 600, mainLine: [6], branch: [12]),
                ServiceBand(start: 600, end: 780, mainLine: [9], branch: [18]),
                ServiceBand(start: 780, end: 1200, mainLine: [6], branch: [12]),
                ServiceBand(start: 1200, end: 1320, mainLine: [9], branch: [18]),
                ServiceBand(start: 1320, end: 1380, mainLine: [10], branch: [20])
            ],
            weekend: [9],
            weekendLate: [10],
            weekendBranch: [18],
            weekendBranchLate: [20]
        )
    ]

    public static func description(
        for line: String,
        stationName: String? = nil,
        at date: Date = .now
    ) -> String? {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let schedule = schedules[line] else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }

        let currentMinutes = hour * 60 + minute
        guard (300...1380).contains(currentMinutes) else {
            return "În afara programului estimativ (05:00–23:00)"
        }

        let isNonWorkingDay = calendar.isDateInWeekend(date) || isRomanianPublicHoliday(date, calendar: calendar)
        let isBranchStation = isBranchStation(line: line, stationName: stationName)
        let interval: [Double]

        if isNonWorkingDay {
            let isLate = currentMinutes >= 1320
            if isBranchStation, let branch = isLate ? schedule.weekendBranchLate : schedule.weekendBranch {
                interval = branch
            } else {
                interval = isLate ? schedule.weekendLate : schedule.weekend
            }
        } else if let band = schedule.weekday.first(where: { currentMinutes >= $0.start && currentMinutes < $0.end }) {
            interval = isBranchStation ? (band.branch ?? band.mainLine) : band.mainLine
        } else {
            return "În afara programului estimativ (05:00–23:00)"
        }

        let averageHeadway = interval.reduce(0, +) / Double(interval.count)
        let averageWait = Int(ceil(averageHeadway / 2))
        let intervalDescription = interval
            .sorted()
            .map(formatMinutes)
            .joined(separator: "–")
        return "Așteptare medie ~\(averageWait) min (interval \(intervalDescription) min)"
    }

    private static func isBranchStation(line: String, stationName: String?) -> Bool {
        let name = stationName?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch line {
        case "M1":
            return name.contains("pantelimon")
        case "M3":
            return [
                "eroilor", "izvor", "piata unirii", "timpuri noi",
                "mihai bravu", "dristor 1"
            ].contains(where: name.contains)
        case "M5":
            return name.contains("constantin brancusi") || name.contains("raul doamnei")
        default:
            return false
        }
    }

    private static func isRomanianPublicHoliday(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year else { return false }

        let fixedHolidays: Set<String> = [
            "1-1", "1-2", "1-6", "1-7", "1-24", "5-1",
            "6-1", "8-15", "11-30", "12-1", "12-25", "12-26"
        ]
        if let month = components.month, let day = components.day,
           fixedHolidays.contains("\(month)-\(day)") {
            return true
        }

        guard let easterSunday = orthodoxEasterSunday(year: year, calendar: calendar) else { return false }
        let movableHolidays = [-2, 0, 1, 49, 50]
        return movableHolidays.contains { offset in
            guard let holiday = calendar.date(byAdding: .day, value: offset, to: easterSunday) else { return false }
            return calendar.isDate(date, inSameDayAs: holiday)
        }
    }

    private static func orthodoxEasterSunday(year: Int, calendar: Calendar) -> Date? {
        let a = year % 4
        let b = year % 7
        let c = year % 19
        let d = (19 * c + 15) % 30
        let e = (2 * a + 4 * b - d + 34) % 7
        let value = d + e + 114
        let julianMonth = value / 31
        let julianDay = value % 31 + 1

        var components = DateComponents()
        components.year = year
        components.month = julianMonth
        components.day = julianDay
        components.timeZone = calendar.timeZone
        guard let julianDate = calendar.date(from: components) else { return nil }
        return calendar.date(byAdding: .day, value: 13, to: julianDate)
    }

    private static func formatMinutes(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }
}
