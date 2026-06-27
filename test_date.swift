import Foundation
let dateStr = "2026-06-28T19:00Z"
let isoFmt = ISO8601DateFormatter()
isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
print("isoFmt:", isoFmt.date(from: dateStr) ?? "nil")
let isoFmt2 = DateFormatter()
isoFmt2.dateFormat = "yyyy-MM-dd'T'HH:mmZ"
isoFmt2.locale = Locale(identifier: "en_US_POSIX")
print("isoFmt2:", isoFmt2.date(from: dateStr) ?? "nil")
