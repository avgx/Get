// The MIT License (MIT)
//
// Copyright (c) 2021-2022 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Get

import Foundation
import Pulse

final class HttpClient5Tests: XCTestCase {
    override func setUp() async throws {
        Task {
            LoggerStore.shared.removeAll()
        }
    }
    
    func testExampleWithDomainAndPin() async throws {
        let url = URL(string: "https://example.com")!
        
        let pin = SSL.Pin(
            host: "example.com",
            serialNumber: "07:5B:CE:F3:06:89:C8:AD:DF:13:E5:1A:F4:AF:E1:87",
            sha256: "EF:BA:26:D8:C1:CE:37:79:AC:77:63:0A:90:F8:21:63:A3:D6:89:2E:D6:AF:EE:40:86:72:CF:19:EB:A7:A3:62",
            sha1: "4D:A2:5A:6D:5E:F6:2C:5F:95:C7:BD:0A:73:EA:3C:17:7B:36:99:9D"
        )
        
        let http = HttpClient5(baseURL: url, ssl: .pinning([ pin ]))
        let x = try await http.send(Request<String>(path: "/"))
        XCTAssert(x.value.count > 0)
        
        let certs = await http.certificates(for: "example.com")
        for c in certs ?? [] {
            print("sha256 \(c.sha256)")
            print("sha1 \(c.sha1)")
            print("serialNumber \(c.serialNumber)")
            print("subjectSummary \(String(describing: c.subjectSummary))")
            print("commonName \(String(describing: c.commonName)) isSelfSigned \(String(describing: c.isSelfSigned))")
            print("isSelfSigned \(String(describing: c.isSelfSigned))")
            print("pem \n\(c.pem)")
        }
        
        XCTAssertEqual(certs?.first?.serialNumber, pin.serialNumber)
    }
    
    func testExampleWithIPAndNoPin() async throws {
        let url = URL(string: "https://93.184.216.34")! //https://example.com
        
        
        let http = HttpClient5(baseURL: url)
        
        do {
            let x = try await http.send(Request<String>(path: "/"))
            print(x.value.count)
            XCTFail()
        } catch CustomError.sslTrustError(let e) {
            XCTAssert(e.isSSL)
            XCTAssert(e.localizedDescription.contains("93.184.216.34"))
        } catch {
            XCTFail()
        }
        
        let certs = await http.certificates(for: "93.184.216.34")
        for c in certs ?? [] {
            print("serialNumber \(c.serialNumber)")
            print("commonName \(String(describing: c.commonName)) isSelfSigned \(String(describing: c.isSelfSigned))")
            print("isSelfSigned \(String(describing: c.isSelfSigned))")
        }
        XCTAssertEqual(certs?.first?.serialNumber, "07:5B:CE:F3:06:89:C8:AD:DF:13:E5:1A:F4:AF:E1:87")
    }
    
    func testExampleWithIPAndPin() async throws {
        let url = URL(string: "https://93.184.216.34")!
        
        let pin1 = SSL.Pin(
            host: "example.com",
            serialNumber: "07:5B:CE:F3:06:89:C8:AD:DF:13:E5:1A:F4:AF:E1:87",
            sha256: "EF:BA:26:D8:C1:CE:37:79:AC:77:63:0A:90:F8:21:63:A3:D6:89:2E:D6:AF:EE:40:86:72:CF:19:EB:A7:A3:62",
            sha1: "4D:A2:5A:6D:5E:F6:2C:5F:95:C7:BD:0A:73:EA:3C:17:7B:36:99:9D"
        )
        let pin2 = SSL.Pin(
            host: "93.184.216.34",
            serialNumber: "07:5B:CE:F3:06:89:C8:AD:DF:13:E5:1A:F4:AF:E1:87",
            sha256: "EF:BA:26:D8:C1:CE:37:79:AC:77:63:0A:90:F8:21:63:A3:D6:89:2E:D6:AF:EE:40:86:72:CF:19:EB:A7:A3:62",
            sha1: "4D:A2:5A:6D:5E:F6:2C:5F:95:C7:BD:0A:73:EA:3C:17:7B:36:99:9D"
        )
        let pins = [ pin1, pin2 ]
        
        let http = HttpClient5(baseURL: url, ssl: .pinning(pins))
        
        do {
            let x = try await http.send(Request<String>(path: "/"))
            XCTAssert(x.value.count > 0)
        } catch CustomError.unacceptableStatusCode(let code, let str, let url) {
            XCTAssert(code == 404)
            
            print(str)
            XCTAssertEqual(url.absoluteString, "https://93.184.216.34/")
        } catch {
            XCTFail()
        }
    }
    
    func testSelfSigned() async throws {
        let url = URL(string: "https://self-signed.badssl.com/")!
        
        let http = HttpClient5(baseURL: url)
        
        do {
            let x = try await http.send(Request<String>(path: "/"))
            XCTAssert(x.value.count > 0)
        } catch CustomError.sslTrustError(let e) {
            XCTAssert(e.isSSL)
            let certs = await http.certificates(for: "self-signed.badssl.com")
            XCTAssertEqual(certs?.count, 1)
            XCTAssertEqual(certs?.first?.isSelfSigned, true)
            XCTAssertEqual(certs?.first?.commonName, "*.badssl.com")
        } catch {
            XCTFail()
        }
    }
    
    func testMultipart() async throws {
        let url = URL(string: "http://try.axxonsoft.com:8000/asip-api/v1/logic_service/batchgetactivealerts")!
        
        var req = URLRequest(url: url)
        req.addValue(Authorization.basic(.init(user: "root", password: "root")).header!, forHTTPHeaderField: "Authorization")
        req.httpMethod = "POST"
        req.httpBody = "{ }".data(using: .utf8)   ////!!!!!!! Это важно при отправке!! иначе 400
        let (stream, response) = try await URLSession.shared.bytes(for: req)
        var bytes: [UInt8] = []
        // 4
        for try await byte in stream {
            // 5
            bytes.append(byte)
        }
        XCTAssert(bytes.count > 0)
        
    }
    
    func testMultipart5() async throws {
        struct Empty: Codable { }
        
        let url = URL(string: "http://try.axxonsoft.com:8000/asip-api")!
        
        let http = HttpClient5(baseURL: url, authorization: .basic(.init(user: "root", password: "root")))
        let req = Request(path: "/v1/logic_service/batchgetactivealerts", method: .post, body: Empty())
        let resp = try await http.send(req)
        
        
        XCTAssert(resp.data.count > 0)
        
    }
}

//""
