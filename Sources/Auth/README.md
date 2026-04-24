нормальная декомпозиция: **Auth state → interceptor → transport → delegate → metrics/logging**.


# идея архитектуры

Раздели ответственность:

* **AuthState (actor)**
  Хранит текущий access token + refresh token
  Управляет refresh (с дедупликацией)

* **AuthInterceptor**
  Встраивает Bearer token в `URLRequest`
  Реагирует на 401 → инициирует refresh → повторяет запрос

* **HTTPClient (обёртка над URLSession)**
  Выполняет запросы
  Прогоняет через interceptor chain

---

# 2. AuthState как actor (без гонок)

Это центральная точка. Без actor тут почти гарантированы race conditions.

```swift
actor AuthState {
    private var accessToken: String?
    private var refreshToken: String?
    
    private var refreshTask: Task<String, Error>?

    func setTokens(access: String, refresh: String) {
        self.accessToken = access
        self.refreshToken = refresh
    }

    func getAccessToken() -> String? {
        accessToken
    }

    func validAccessToken(refreshIfNeeded: Bool = true) async throws -> String {
        if let token = accessToken {
            return token
        }
        guard refreshIfNeeded else {
            throw AuthError.missingToken
        }
        return try await refresh()
    }

    func refresh() async throws -> String {
        if let task = refreshTask {
            return try await task.value
        }

        let task = Task<String, Error> {
            defer { refreshTask = nil }

            let newToken = try await performRefresh()
            self.accessToken = newToken
            return newToken
        }

        refreshTask = task
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        // отдельный URLSession без interceptor'ов!
        // иначе recursion
        throw URLError(.badServerResponse)
    }
}
```

Ключевой момент:
**refreshTask** устраняет “thundering herd” — все запросы ждут один refresh.

---

---

# 4. AuthInterceptor

```swift
final class AuthInterceptor: HTTPInterceptor {
    private let auth: AuthState

    init(auth: AuthState) {
        self.auth = auth
    }

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request

        let token = try await auth.validAccessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return request
    }

    func retry(_ request: URLRequest, dueTo error: Error) async -> Bool {
        guard let urlError = error as? URLError else { return false }

        // лучше проверять HTTP 401 через response, но для примера:
        if urlError.code == .userAuthenticationRequired {
            do {
                _ = try await auth.refresh()
                return true
            } catch {
                return false
            }
        }

        return false
    }
}
```


# 7. Важные edge cases

### 1. Рекурсия refresh

refresh должен идти через **чистый client без interceptor**

---

### 2. Retry loop

Добавь ограничение:

```swift
var retryCount = 0
```

или через `URLRequest` extension (associated storage)

---

### 3. 401 vs network error

Правильнее:

* проверять `HTTPURLResponse.statusCode == 401`
* а не `URLError`

---

### 4. Cancellation propagation

Если исходный Task отменён — refresh тоже должен отменяться
(по умолчанию Task это делает, но проверяй)

---


#  Что дальше имеет смысл улучшить

Если делать «production-grade»:

* exponential backoff
* jitter
* circuit breaker
* request coalescing (одинаковые GET)
* structured logging (trace-id)
* metrics (TTFB, DNS, TLS)

---
