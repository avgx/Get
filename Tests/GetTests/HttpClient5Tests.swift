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
    // Override query item encoding.
    // Addresses https://github.com/kean/Get/issues/35
//    func testOverridingQueryItemsEncoding() async throws {
//        // GIVEN
//        let client = APIClient.mock {
//            $0.delegate = ClientDelegate()
//        }
//
//        let request = Request(path: "/domain.tld", query: [("query", "value1+value2")])
//
//        // WHEN
//        let urlRequest = try await client.makeURLRequest(for: request)
//
//        // THEN "+" is percent encoded
//        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.github.com/domain.tld?query=value1%2Bvalue2")
//    }
    
    func testExampleWithDomainAndPin() async throws {
        let url = URL(string: "https://example.com")!
        
        let pin = SSL.Pin(
            serialNumber: "07:5B:CE:F3:06:89:C8:AD:DF:13:E5:1A:F4:AF:E1:87",
            sha256: "EF:BA:26:D8:C1:CE:37:79:AC:77:63:0A:90:F8:21:63:A3:D6:89:2E:D6:AF:EE:40:86:72:CF:19:EB:A7:A3:62",
            sha1: "4D:A2:5A:6D:5E:F6:2C:5F:95:C7:BD:0A:73:EA:3C:17:7B:36:99:9D"
        )
        let pins: [String: SSL.Pin] = [ "example.com": pin ]
        
        let http = HttpClient5(baseURL: url, pins: pins)
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
        
        let pin = SSL.Pin(
            serialNumber: "07:5B:CE:F3:06:89:C8:AD:DF:13:E5:1A:F4:AF:E1:87",
            sha256: "EF:BA:26:D8:C1:CE:37:79:AC:77:63:0A:90:F8:21:63:A3:D6:89:2E:D6:AF:EE:40:86:72:CF:19:EB:A7:A3:62",
            sha1: "4D:A2:5A:6D:5E:F6:2C:5F:95:C7:BD:0A:73:EA:3C:17:7B:36:99:9D"
        )
        let pins: [String: SSL.Pin] = [ "example.com": pin, "93.184.216.34": pin ]
        
        let http = HttpClient5(baseURL: url, pins: pins)
        
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
    
}

//""
