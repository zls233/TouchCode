import Foundation
import TouchCodeIdentity

do {
    guard CommandLine.arguments == [CommandLine.arguments[0], "sign"] else {
        throw IdentityHelperProtocolError.invalidBase64URL
    }
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard let encodedTranscript = String(data: input, encoding: .utf8) else {
        throw IdentityHelperProtocolError.invalidUTF8
    }
    let transcript = try IdentityHelperProtocol.decodeTranscript(encodedTranscript)
    let signature = try DeviceIdentityStore().sign(transcript: transcript)
    FileHandle.standardOutput.write(Data(DeviceIdentityDerivation.base64URL(signature).utf8))
} catch {
    FileHandle.standardError.write(Data("TouchCode identity helper failed: \(error)\n".utf8))
    exit(2)
}
