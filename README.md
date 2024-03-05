# Get

Http client built using async/await. 

Configured to log using [Pulse](https://github.com/kean/Pulse)
Based on [Get](https://github.com/kean/Get)
With certificate pinning via fingerprint option (based on [samples](https://github.com/search?q=pinning+URLSession+language%3ASwift&type=code&l=Swift))

Get provides a clear and convenient API for modeling network requests using `Request<Response>` type. 
And its `HttpClient5` makes it easy to execute these requests and decode the responses.

```swift
// Create a client
let client = HttpClient5(baseURL: URL(string: "https://api.github.com"))

// Request json with get
let user: User = try await client.send(Request(path: "/user")).value

// Request json with post
var request = Request(path: "/user/emails", method: .post, body: ["alex@me.com"])
try await client.send(request)

// Don't decode for string
let string: String = try await client.send(Request(path: "/user")).value

// Don't decode for Data
let data: Data = try await client.send(Request(path: "/favicon.ico")).value
```

## Documentation

Learn how to use Get by going through the [documentation](https://kean-docs.github.io/get/documentation/get/) created using DocC.

To learn more about `URLSession`, see [URL Loading System](https://developer.apple.com/documentation/foundation/url_loading_system).


## License

Get is available under the MIT license. See the LICENSE file for more info.
