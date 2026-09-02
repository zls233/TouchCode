import CryptoKit
import Foundation
import Security

public struct DeviceIdentity: Encodable, Equatable, Sendable {
    public let version: Int
    public let deviceId: String
    public let keyAlgorithm: String
    public let signatureAlgorithm: String
    public let signatureEncoding: String
    public let publicKeyX963: String
    public let displayName: String

    init(publicKeyX963: Data, displayName: String) throws {
        self.version = 1
        self.deviceId = try DeviceIdentityDerivation.deviceID(publicKeyX963: publicKeyX963)
        self.keyAlgorithm = "p256"
        self.signatureAlgorithm = "ecdsa-sha256"
        self.signatureEncoding = "asn1-der"
        self.publicKeyX963 = DeviceIdentityDerivation.base64URL(publicKeyX963)
        self.displayName = displayName
    }
}

public enum DeviceIdentityError: Error, Equatable, Sendable {
    case invalidDisplayName
    case keychain(OSStatus)
    case keyGeneration(String)
    case invalidStoredKey
    case publicKeyExtraction(String)
    case signingUnsupported
    case signingFailed(String)
}

public enum DeviceIdentityDerivation {
    public static func deviceID(publicKeyX963: Data) throws -> String {
        guard publicKeyX963.count == 65, publicKeyX963.first == 0x04 else {
            throw DeviceIdentityError.invalidStoredKey
        }

        var material = Data("TouchCode device id v1".utf8)
        material.append(0)
        material.append(Data("p256".utf8))
        material.append(0)
        material.append(publicKeyX963)
        return "tcid1_\(base64URL(Data(SHA256.hash(data: material))))"
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

protocol P256KeyProviding: Sendable {
    func loadPrivateKey() throws -> SecKey?
    func createPrivateKey() throws -> SecKey
}

final class KeychainP256KeyProvider: P256KeyProviding, @unchecked Sendable {
    private let applicationTag: Data

    init(applicationTag: String) {
        self.applicationTag = Data(applicationTag.utf8)
    }

    func loadPrivateKey() throws -> SecKey? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw DeviceIdentityError.keychain(status)
        }
        guard let result, CFGetTypeID(result) == SecKeyGetTypeID() else {
            throw DeviceIdentityError.invalidStoredKey
        }
        return (result as! SecKey)
    }

    func createPrivateKey() throws -> SecKey {
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: applicationTag,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ],
        ]

        if let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) {
            return key
        }

        if let error {
            let retainedError = error.takeRetainedValue()
            let status = OSStatus(CFErrorGetCode(retainedError))
            if status == errSecDuplicateItem,
               let existing = try loadPrivateKey() {
                return existing
            }
            if CFErrorGetDomain(retainedError) as String == NSOSStatusErrorDomain {
                throw DeviceIdentityError.keychain(status)
            }
            throw DeviceIdentityError.keyGeneration(retainedError.localizedDescription)
        }
        throw DeviceIdentityError.keyGeneration("Security.framework did not return an error")
    }
}

public final class DeviceIdentityStore: @unchecked Sendable {
    public static let defaultApplicationTag = "com.touchcode.mac.device-identity.v1"

    private let provider: any P256KeyProviding
    private let lock = NSLock()
    private var cachedPrivateKey: SecKey?

    public convenience init(applicationTag: String = defaultApplicationTag) {
        self.init(provider: KeychainP256KeyProvider(applicationTag: applicationTag))
    }

    init(provider: any P256KeyProviding) {
        self.provider = provider
    }

    public func loadOrCreate(displayName: String) throws -> DeviceIdentity {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName.count <= 128 else {
            throw DeviceIdentityError.invalidDisplayName
        }

        lock.lock()
        defer { lock.unlock() }
        let privateKey = try privateKeyLocked()
        let publicKey = try publicKeyX963(privateKey: privateKey)
        return try DeviceIdentity(publicKeyX963: publicKey, displayName: normalizedName)
    }

    public func sign(transcript: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        let privateKey = try privateKeyLocked()
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw DeviceIdentityError.signingUnsupported
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, transcript as CFData, &error) else {
            let description = error?.takeRetainedValue().localizedDescription
                ?? "Security.framework did not return an error"
            throw DeviceIdentityError.signingFailed(description)
        }
        return signature as Data
    }

    private func privateKeyLocked() throws -> SecKey {
        if let cachedPrivateKey {
            return cachedPrivateKey
        }

        let privateKey = try provider.loadPrivateKey() ?? provider.createPrivateKey()
        _ = try publicKeyX963(privateKey: privateKey)
        cachedPrivateKey = privateKey
        return privateKey
    }

    private func publicKeyX963(privateKey: SecKey) throws -> Data {
        guard let attributes = SecKeyCopyAttributes(privateKey) as? [CFString: Any],
              attributes[kSecAttrKeyType] as? String == kSecAttrKeyTypeECSECPrimeRandom as String,
              attributes[kSecAttrKeyClass] as? String == kSecAttrKeyClassPrivate as String,
              attributes[kSecAttrKeySizeInBits] as? Int == 256,
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw DeviceIdentityError.invalidStoredKey
        }

        var error: Unmanaged<CFError>?
        guard let representation = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            let description = error?.takeRetainedValue().localizedDescription
                ?? "Security.framework did not return an error"
            throw DeviceIdentityError.publicKeyExtraction(description)
        }
        let data = representation as Data
        guard data.count == 65, data.first == 0x04 else {
            throw DeviceIdentityError.invalidStoredKey
        }
        return data
    }
}
