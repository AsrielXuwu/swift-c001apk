import Foundation

public enum Formatting {
    public static func count(_ value: Int) -> String {
        if value >= 100_000_000 { return String(format: "%.1f亿", Double(value) / 100_000_000) }
        if value >= 10_000 { return String(format: "%.1f万", Double(value) / 10_000) }
        if value >= 1_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return String(value)
    }

    public static func relativeTime(_ date: Date?, fallback: String = "") -> String {
        guard let date else { return fallback }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3_600 { return "\(Int(interval / 60))分钟前" }
        if interval < 86_400 { return "\(Int(interval / 3_600))小时前" }
        if interval < 86_400 * 7 { return "\(Int(interval / 86_400))天前" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func chatTimestamp(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        let timeText = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "今天 \(timeText)"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(timeText)"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())),
           date >= weekAgo {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.locale = Locale(identifier: "zh_CN")
            weekdayFormatter.dateFormat = "EEEE HH:mm"
            return weekdayFormatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if calendar.component(.year, from: date) == calendar.component(.year, from: Date()) {
            formatter.dateFormat = "M月d日 HH:mm"
        } else {
            formatter.dateFormat = "yyyy年M月d日 HH:mm"
        }
        return formatter.string(from: date)
    }

    public static func byteSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
