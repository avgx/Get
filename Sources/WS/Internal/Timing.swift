import Foundation

/// Pure time conversions.
enum Timing {
    /// Nanoseconds for `Task.sleep`; never 0 so a zero interval still yields.
    static func sleepNanoseconds(_ seconds: TimeInterval) -> UInt64 {
        let raw = seconds * 1_000_000_000.0
        if raw >= Double(UInt64.max) { return UInt64.max }
        if raw <= 0 { return 1 }
        return UInt64(raw)
    }
}
