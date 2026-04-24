import Foundation

/// Чистые преобразования интервалов и расчёт backoff 
enum Timing {
    static func handshakeTimeoutNanoseconds(_ seconds: TimeInterval) -> UInt64 {
        let raw = seconds * 1_000_000_000.0
        if raw >= Double(UInt64.max) { return UInt64.max }
        if raw <= 0 { return 0 }
        return UInt64(raw)
    }

    static func timeIntervalToSleepNanoseconds(_ seconds: TimeInterval) -> UInt64 {
        let raw = seconds * 1_000_000_000.0
        if raw >= Double(UInt64.max) { return UInt64.max }
        if raw <= 0 { return 1 }
        return UInt64(raw)
    }

    static func backoffNanoseconds(
        attempt: Int,
        initial: UInt64,
        max: UInt64,
        multiplier: Double
    ) -> UInt64 {
        guard attempt > 0 else { return initial }
        let powed = pow(multiplier, Double(attempt - 1))
        let scaled = Double(initial) * powed
        return UInt64(min(scaled, Double(max)))
    }
}
