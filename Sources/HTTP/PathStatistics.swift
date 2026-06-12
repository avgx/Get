import Foundation

/// Aggregates request activity by URL path using only ``RequestObserver`` callbacks
public actor PathStatistics: RequestObserver {
    private struct Bucket {
        var stats = PathRequestStatistics()
    }

    private var buckets: [String: Bucket] = [:]

    public init() {}

    /// Stable key for aggregation: ``URL/path``, `"/"` when empty, `"<no-url>"` when the request has no URL.
    public nonisolated static func pathKey(for request: URLRequest) -> String {
        guard let url = request.url else { return "<no-url>" }
        let path = url.path
        return path.isEmpty ? "/" : path
    }

    /// Snapshot of all paths observed so far.
    public func snapshot() -> [String: PathRequestStatistics] {
        buckets.mapValues(\.stats)
    }

    /// Clears all accumulated statistics.
    public func reset() {
        buckets = [:]
    }

    private func bucket(for request: URLRequest) -> String {
        Self.pathKey(for: request)
    }

    public func willSend(_ request: URLRequest) async {
        let key = bucket(for: request)
        var b = buckets[key] ?? Bucket()
        b.stats.willSendCount += 1
        b.stats.totalRequestBodyBytesSent += Int64(request.httpBody?.count ?? 0)
        buckets[key] = b
    }

    public func didCompleteSuccess(_ request: URLRequest, response: URLResponse, body: Data, duration: TimeInterval) async {
        let key = bucket(for: request)
        var b = buckets[key] ?? Bucket()
        b.stats.httpSuccessCount += 1
        b.stats.successDurationSum += duration
        b.stats.totalResponseBodyBytesReceived += Int64(body.count)
        if let http = response as? HTTPURLResponse {
            let code = http.statusCode
            b.stats.statusCodeCounts[code, default: 0] += 1
        }
        buckets[key] = b
    }

    public func didCompleteFailure(_ request: URLRequest, error: Error, duration: TimeInterval) async {
        let key = bucket(for: request)
        var b = buckets[key] ?? Bucket()
        b.stats.httpFailureCount += 1
        b.stats.failureDurationSum += duration
        buckets[key] = b
    }

    public func didDecodeFailure(
        _ request: URLRequest,
        response: URLResponse,
        body: Data,
        expectedDecodableTypeName: String,
        error: Error
    ) async {
        let key = bucket(for: request)
        var b = buckets[key] ?? Bucket()
        b.stats.decodeFailureCount += 1
        buckets[key] = b
    }
}

/// Aggregated counters for one URL path (see ``StatisticsRequestObserver/pathKey(for:)``).
public struct PathRequestStatistics: Sendable, Equatable {
    public var willSendCount: Int
    public var httpSuccessCount: Int
    public var httpFailureCount: Int
    public var decodeFailureCount: Int
    /// Counts per HTTP status code on successful loads (from ``HTTPURLResponse/statusCode``).
    public var statusCodeCounts: [Int: Int]
    /// Sum of ``didCompleteSuccess`` `duration` values (seconds).
    public var successDurationSum: TimeInterval
    /// Sum of ``didCompleteFailure`` `duration` values (seconds).
    public var failureDurationSum: TimeInterval
    /// Approximate request body bytes (`URLRequest.httpBody?.count` summed at ``willSend``).
    public var totalRequestBodyBytesSent: Int64
    /// Response body bytes summed on ``didCompleteSuccess`` (and not again on decode failure).
    public var totalResponseBodyBytesReceived: Int64

    public init(
        willSendCount: Int = 0,
        httpSuccessCount: Int = 0,
        httpFailureCount: Int = 0,
        decodeFailureCount: Int = 0,
        statusCodeCounts: [Int: Int] = [:],
        successDurationSum: TimeInterval = 0,
        failureDurationSum: TimeInterval = 0,
        totalRequestBodyBytesSent: Int64 = 0,
        totalResponseBodyBytesReceived: Int64 = 0
    ) {
        self.willSendCount = willSendCount
        self.httpSuccessCount = httpSuccessCount
        self.httpFailureCount = httpFailureCount
        self.decodeFailureCount = decodeFailureCount
        self.statusCodeCounts = statusCodeCounts
        self.successDurationSum = successDurationSum
        self.failureDurationSum = failureDurationSum
        self.totalRequestBodyBytesSent = totalRequestBodyBytesSent
        self.totalResponseBodyBytesReceived = totalResponseBodyBytesReceived
    }

    /// Average ``didCompleteSuccess`` duration when ``httpSuccessCount`` is greater than zero.
    public var averageSuccessDuration: TimeInterval {
        guard httpSuccessCount > 0 else { return 0 }
        return successDurationSum / TimeInterval(httpSuccessCount)
    }

    /// Average ``didCompleteFailure`` duration when ``httpFailureCount`` is greater than zero.
    public var averageFailureDuration: TimeInterval {
        guard httpFailureCount > 0 else { return 0 }
        return failureDurationSum / TimeInterval(httpFailureCount)
    }
}
