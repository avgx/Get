import Foundation

/// One-shot result slot shared by a callback, a waiter and a cancellation handler.
///
/// `URLSession` WebSocket callbacks may fire more than once, late, or never once the task is cancelled.
/// The first `resume` wins; later ones are ignored. A result that arrives before the waiter is installed is kept.
final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var early: Result<Value, Error>?
    private var done = false

    /// Call once, from inside `withCheckedThrowingContinuation`.
    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let early {
            self.early = nil
            done = true
            lock.unlock()
            continuation.resume(with: early)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Safe from any thread, any number of times.
    func resume(_ result: Result<Value, Error>) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        guard let continuation else {
            if early == nil { early = result }
            lock.unlock()
            return
        }
        self.continuation = nil
        done = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

/// Awaits a completion-handler API and returns as soon as the current task is cancelled,
/// even if the handler is never called afterwards.
///
/// `start` hands the handler to the API; the handler may be called any number of times, only the first call counts.
func awaitCallback<Value: Sendable>(
    _ start: (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void
) async throws -> Value {
    let slot = ResumeOnce<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
            slot.install(continuation)
            start { slot.resume($0) }
        }
    } onCancel: {
        slot.resume(.failure(CancellationError()))
    }
}
