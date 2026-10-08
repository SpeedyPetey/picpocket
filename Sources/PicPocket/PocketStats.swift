import Foundation

/// Counts captures locally; opening or restoring the pocket does not add to it.
struct PocketStats {
    var defaults: UserDefaults = .standard

    func count(on date: Date = Date()) -> Int {
        guard let recordedDay = defaults.object(forKey: "pocketCaptureDay") as? Date,
              Calendar.current.isDate(recordedDay, inSameDayAs: date) else { return 0 }
        return defaults.integer(forKey: "pocketCaptureCount")
    }

    func recordCapture(on date: Date = Date()) {
        let next = count(on: date) + 1
        defaults.set(date, forKey: "pocketCaptureDay")
        defaults.set(next, forKey: "pocketCaptureCount")
    }
}
