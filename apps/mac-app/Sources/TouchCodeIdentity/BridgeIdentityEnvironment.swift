import Foundation

public enum BridgeIdentityEnvironmentError: Error, Equatable, Sendable {
    case encodingFailed
    case valueTooLarge
}

public enum BridgeIdentityEnvironment {
    public static let variableName = "TOUCHCODE_HOST_IDENTITY_JSON"
    public static let maximumValueBytes = 4_096

    public static func encode(_ identity: DeviceIdentity) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(identity)
        guard data.count <= maximumValueBytes else {
            throw BridgeIdentityEnvironmentError.valueTooLarge
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw BridgeIdentityEnvironmentError.encodingFailed
        }
        return value
    }
}
