import Darwin
import Foundation

/// Thread-safe one-shot flag without `OSAllocatedUnfairLock` (iOS 16+) and without `NSLock` in `async` contexts (Swift 6).
final class OnceFlag: @unchecked Sendable {
    private let state = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    init() {
        state.initialize(to: 0)
    }

    deinit {
        state.deinitialize(count: 1)
        state.deallocate()
    }

    /// Returns `true` the first time; then `false`.
    func tryConsume() -> Bool {
        OSAtomicCompareAndSwap32Barrier(0, 1, state)
    }
}
