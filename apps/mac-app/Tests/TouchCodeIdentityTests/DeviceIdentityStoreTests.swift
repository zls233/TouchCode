import Foundation
import Security
import XCTest
@testable import TouchCodeIdentity

final class DeviceIdentityStoreTests: XCTestCase, @unchecked Sendable {
    func testDeviceIDMatchesSharedProtocolGoldenVector() throws {
        let publicKey = try XCTUnwrap(Data(base64URL: "BMFNoWM3YHGMzbG97Zqo6wWc-PE0O6k6P719hkzzq3uJwEUYgyR9miVjotMrt-mWy1Mpi2PJ5Icu4SmpFJ7hyvk"))
        XCTAssertEqual(
            try DeviceIdentityDerivation.deviceID(publicKeyX963: publicKey),
            "tcid1_-s9yHQa79RESg-U5J-5mWMBi0wuM3v-kclPZExMG2v0"
        )
    }

    func testLoadOrCreateIsStableAndDisplayNameIsSeparateMetadata() throws {
        let provider = InMemoryP256KeyProvider()
        let firstStore = DeviceIdentityStore(provider: provider)
        let first = try firstStore.loadOrCreate(displayName: "  TouchCode Mac  ")
        let renamed = try firstStore.loadOrCreate(displayName: "Studio Mac")
        let relaunched = try DeviceIdentityStore(provider: provider).loadOrCreate(displayName: "Studio Mac")

        XCTAssertEqual(first.displayName, "TouchCode Mac")
        XCTAssertEqual(first.deviceId, renamed.deviceId)
        XCTAssertEqual(first.publicKeyX963, renamed.publicKeyX963)
        XCTAssertEqual(renamed, relaunched)
        XCTAssertEqual(provider.createCount, 1)
        XCTAssertEqual(first.version, 1)
        XCTAssertEqual(first.keyAlgorithm, "p256")
        XCTAssertEqual(first.signatureAlgorithm, "ecdsa-sha256")
        XCTAssertEqual(first.signatureEncoding, "asn1-der")
    }

    func testConcurrentLoadsCreateOneIdentity() async throws {
        let provider = InMemoryP256KeyProvider()
        let store = DeviceIdentityStore(provider: provider)

        let identities = try await withThrowingTaskGroup(of: DeviceIdentity.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try store.loadOrCreate(displayName: "TouchCode Mac")
                }
            }
            var results: [DeviceIdentity] = []
            for try await identity in group {
                results.append(identity)
            }
            return results
        }

        XCTAssertEqual(Set(identities.map(\.deviceId)).count, 1)
        XCTAssertEqual(provider.createCount, 1)
    }

    func testSignatureVerifiesAndTamperingFails() throws {
        let provider = InMemoryP256KeyProvider()
        let store = DeviceIdentityStore(provider: provider)
        let identity = try store.loadOrCreate(displayName: "TouchCode Mac")
        let transcript = Data("canonical transcript".utf8)
        let signature = try store.sign(transcript: transcript)
        let publicKeyData = try XCTUnwrap(Data(base64URL: identity.publicKeyX963))
        let publicKey = try XCTUnwrap(makePublicKey(x963: publicKeyData))

        XCTAssertTrue(SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            transcript as CFData,
            signature as CFData,
            nil
        ))
        XCTAssertFalse(SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            Data("tampered transcript".utf8) as CFData,
            signature as CFData,
            nil
        ))
    }

    func testInvalidStoredKeyFailsClosedWithoutCreatingReplacement() throws {
        let provider = InMemoryP256KeyProvider(storedKey: try makePrivateKey(type: kSecAttrKeyTypeRSA, size: 2048))
        let store = DeviceIdentityStore(provider: provider)

        XCTAssertThrowsError(try store.loadOrCreate(displayName: "TouchCode Mac")) { error in
            XCTAssertEqual(error as? DeviceIdentityError, .invalidStoredKey)
        }
        XCTAssertEqual(provider.createCount, 0)
    }

    func testInvalidDisplayNameDoesNotAccessKeyStorage() throws {
        let provider = InMemoryP256KeyProvider()
        let store = DeviceIdentityStore(provider: provider)

        XCTAssertThrowsError(try store.loadOrCreate(displayName: "   ")) { error in
            XCTAssertEqual(error as? DeviceIdentityError, .invalidDisplayName)
        }
        XCTAssertEqual(provider.loadCount, 0)
        XCTAssertEqual(provider.createCount, 0)
    }

    func testCreationFailureCanRetryWithoutCachingPartialIdentity() throws {
        let provider = RetryableP256KeyProvider()
        let store = DeviceIdentityStore(provider: provider)

        XCTAssertThrowsError(try store.loadOrCreate(displayName: "TouchCode Mac")) { error in
            XCTAssertEqual(error as? DeviceIdentityError, .keychain(errSecInteractionNotAllowed))
        }

        let identity = try store.loadOrCreate(displayName: "TouchCode Mac")
        XCTAssertTrue(identity.deviceId.hasPrefix("tcid1_"))
        XCTAssertEqual(provider.createCount, 2)
    }

    func testBridgeEnvironmentContainsOnlyProtocolPublicIdentity() throws {
        let identity = try DeviceIdentityStore(provider: InMemoryP256KeyProvider())
            .loadOrCreate(displayName: "TouchCode Mac")
        let value = try BridgeIdentityEnvironment.encode(identity)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        )

        XCTAssertEqual(BridgeIdentityEnvironment.variableName, "TOUCHCODE_HOST_IDENTITY_JSON")
        XCTAssertEqual(Set(object.keys), [
            "version",
            "deviceId",
            "keyAlgorithm",
            "signatureAlgorithm",
            "signatureEncoding",
            "publicKeyX963",
            "displayName",
        ])
        XCTAssertEqual(object["deviceId"] as? String, identity.deviceId)
        XCTAssertNil(object["privateKey"])
        XCTAssertNil(object["signature"])
    }

    func testIdentityHelperProtocolAcceptsCanonicalBoundedTranscripts() throws {
        let transcript = Data("TouchCode Identity v1\0example".utf8)
        let encoded = DeviceIdentityDerivation.base64URL(transcript)
        XCTAssertEqual(try IdentityHelperProtocol.decodeTranscript(encoded), transcript)
        XCTAssertThrowsError(try IdentityHelperProtocol.decodeTranscript(""))
        XCTAssertThrowsError(try IdentityHelperProtocol.decodeTranscript("YWJj="))
        XCTAssertThrowsError(try IdentityHelperProtocol.decodeTranscript(" YWJj"))
        XCTAssertThrowsError(try IdentityHelperProtocol.decodeTranscript(
            DeviceIdentityDerivation.base64URL(Data(repeating: 1, count: IdentityHelperProtocol.maximumTranscriptBytes + 1))
        ))
    }
}

private final class InMemoryP256KeyProvider: P256KeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: SecKey?
    private(set) var loadCount = 0
    private(set) var createCount = 0

    init(storedKey: SecKey? = nil) {
        self.storedKey = storedKey
    }

    func loadPrivateKey() throws -> SecKey? {
        lock.lock()
        defer { lock.unlock() }
        loadCount += 1
        return storedKey
    }

    func createPrivateKey() throws -> SecKey {
        lock.lock()
        defer { lock.unlock() }
        createCount += 1
        let key = try makePrivateKey(type: kSecAttrKeyTypeECSECPrimeRandom, size: 256)
        storedKey = key
        return key
    }
}

private final class RetryableP256KeyProvider: P256KeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: SecKey?
    private(set) var createCount = 0

    func loadPrivateKey() throws -> SecKey? {
        lock.lock()
        defer { lock.unlock() }
        return storedKey
    }

    func createPrivateKey() throws -> SecKey {
        lock.lock()
        defer { lock.unlock() }
        createCount += 1
        if createCount == 1 {
            throw DeviceIdentityError.keychain(errSecInteractionNotAllowed)
        }
        let key = try makePrivateKey(type: kSecAttrKeyTypeECSECPrimeRandom, size: 256)
        storedKey = key
        return key
    }
}

private func makePrivateKey(type: CFString, size: Int) throws -> SecKey {
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey([
        kSecAttrKeyType as String: type,
        kSecAttrKeySizeInBits as String: size,
    ] as CFDictionary, &error) else {
        if let error {
            throw error.takeRetainedValue()
        }
        throw DeviceIdentityError.keyGeneration("Missing test key error")
    }
    return key
}

private func makePublicKey(x963: Data) -> SecKey? {
    var error: Unmanaged<CFError>?
    return SecKeyCreateWithData(x963 as CFData, [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits as String: 256,
    ] as CFDictionary, &error)
}

private extension Data {
    init?(base64URL: String) {
        var value = base64URL.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value.append(String(repeating: "=", count: (4 - value.count % 4) % 4))
        self.init(base64Encoded: value)
    }
}
