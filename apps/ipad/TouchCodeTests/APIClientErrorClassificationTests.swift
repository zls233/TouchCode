import XCTest

final class APIClientErrorClassificationTests: XCTestCase {
    func testAuthenticationAndUnknownRunErrorsArePermanent() {
        XCTAssertTrue(TouchCodeAPIClient.isPermanentBridgeError(
            BridgeError.requestFailed("unauthorized", statusCode: 401)))
        XCTAssertTrue(TouchCodeAPIClient.isPermanentBridgeError(
            BridgeError.requestFailed("forbidden", statusCode: 403)))
        XCTAssertTrue(TouchCodeAPIClient.isPermanentBridgeError(
            BridgeError.requestFailed("unknown run", statusCode: 404)))
    }

    func testServerAndTransportErrorsRemainRetryable() {
        XCTAssertFalse(TouchCodeAPIClient.isPermanentBridgeError(
            BridgeError.requestFailed("server unavailable", statusCode: 503)))
        XCTAssertFalse(TouchCodeAPIClient.isPermanentBridgeError(
            URLError(.timedOut)))
    }
}
