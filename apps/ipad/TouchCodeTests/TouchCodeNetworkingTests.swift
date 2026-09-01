import Foundation
import XCTest
@testable import TouchCode

final class TouchCodeNetworkingTests: XCTestCase {
    func testPrototypeTransportDecodesVersionedHello() throws {
        let body = #"{"protocolVersion":1,"role":"host","platform":"macOS","appVersion":"0.1.0","capabilities":["pairing"],"bridgeURL":"http://192.0.2.10:4317"}"#
        let response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n\(body)".utf8)

        let hello = try PrototypeHTTPTransport.decodeHello(from: response)

        XCTAssertEqual(hello.protocolVersion, 1)
        XCTAssertEqual(hello.role, "host")
        XCTAssertEqual(hello.bridgeURL, "http://192.0.2.10:4317")
    }

    func testPrototypeTransportRejectsNonSuccessHTTPResponse() {
        let response = Data("HTTP/1.1 503 Service Unavailable\r\n\r\n{}".utf8)
        XCTAssertThrowsError(try PrototypeHTTPTransport.decodeHello(from: response))
    }
}
