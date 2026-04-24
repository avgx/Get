import Foundation

public enum MultipartError: Error, Sendable, Equatable {
    case httpNotOK(statusCode: Int)
    case invalidRootContentType
    case missingBoundary
    case malformedBoundary
    case malformedPartHeaders
    case unexpectedBytesAfterPartBoundary
    case bufferExceeded(maxBytes: Int)
    case unexpectedEndOfStream
    /// A new URLSession part response arrived before the previous part’s `Content-Length` bytes were received.
    case urlSessionPartIncomplete
}
