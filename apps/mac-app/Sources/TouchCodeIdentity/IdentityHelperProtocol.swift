import Foundation

public enum IdentityHelperProtocolError: Error, Equatable, Sendable {
    case invalidUTF8
    case invalidBase64URL
    case transcriptTooLarge
}

public enum IdentityHelperProtocol {
    public static let maximumTranscriptBytes = 64 * 1_024

    public static func decodeTranscript(_ value: String) throws -> Data {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              }) else {
            throw IdentityHelperProtocolError.invalidBase64URL
        }

        var padded = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        padded.append(String(repeating: "=", count: (4 - padded.count % 4) % 4))
        guard let data = Data(base64Encoded: padded),
              DeviceIdentityDerivation.base64URL(data) == value else {
            throw IdentityHelperProtocolError.invalidBase64URL
        }
        guard data.count <= maximumTranscriptBytes else {
            throw IdentityHelperProtocolError.transcriptTooLarge
        }
        return data
    }
}
