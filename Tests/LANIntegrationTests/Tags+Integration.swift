import Testing

extension Tag {
    /// LAN / device tests (Swift **Testing** tag, not SPM package traits).
    ///
    /// Запуск только этих тестов, например: `swift test --filter lanHttp` или `swift test --filter lanSse`.
    ///
    /// Общие переменные: `GET_TEST_LAN=1`, опционально `GET_TEST_HOST` (по умолчанию `192.168.1.41`), `GET_TEST_USER`, `GET_TEST_PASSWORD` (без пароля тесты с сетью пропускаются). То же можно задать в файле `.env` в корне пакета (см. `.env.example`); окружение процесса перекрывает `.env`.
    ///
    /// Дополнительно для стримов (если переменная не задана — соответствующий тест выходит сразу):
    /// - `GET_TEST_SSE_PATH` — путь к SSE (например `/events`), Basic-авторизация как у HTTP;
    /// - `GET_TEST_MJPEG_PATH` — путь к MJPEG по HTTP; multipart по boundary в одном теле — ``MultipartFrameStream/framesWireFormat``; отдельный ответ URLSession на каждую часть — ``MultipartFrameStream/frames``.
    /// - `GET_TEST_WS_PATH` — путь к WebSocket (`ws://` + Basic auth как у HTTP), модуль **WS**.
    /// - `GET_TEST_WS_LONG_LISTEN=1` — опционально: 10‑минутный WS‑тест (`lanWebSocketLongListenPayloadBytesAndState`), иначе тест сразу выходит.
    @Tag static var integration: Tag
}
