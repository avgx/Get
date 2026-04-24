import Foundation

/// Controls how ``URLSession`` follows HTTP redirects (via ``URLSessionTaskDelegate/urlSession(_:task:willPerformHTTPRedirection:newRequest:)``).
///
/// Map to URLSession behavior: return `newRequest` to follow, or `nil` to stop and deliver the redirect response to the task completion handler.
public enum RedirectDisposition: Sendable, Hashable {
    /// Follow the server’s redirect using the provided request (same as returning `newRequest` from the delegate callback).
    case follow
    /// Do not follow; the task completes with the 3xx response (often paired with ``HTTPError/redirectTo(_:)`` from ``HTTPResponseValidator``).
    case doNotFollow

    
}

