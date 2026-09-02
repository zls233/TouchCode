import Foundation
import Testing
@testable import TouchCodeMac

struct TrustedDevicesTests {
    @Test
    func trustedPeerDecodesFriendlyMetadataWithoutUsingItAsIdentity() throws {
        let data = Data(
            """
            {
              "relationshipId": "relationship-1",
              "peerDeviceId": "tcid1_cryptographic-device-id",
              "peerPublicKeyX963": "not-presented-by-settings",
              "displayName": "Studio iPad",
              "firstPairedAt": 1756800000000,
              "lastSeenAt": 1756886400000,
              "version": 1
            }
            """.utf8
        )

        let peer = try JSONDecoder().decode(TrustedPeer.self, from: data)

        #expect(peer.id == "tcid1_cryptographic-device-id")
        #expect(peer.displayName == "Studio iPad")
        #expect(peer.firstPairedAt == 1_756_800_000_000)
        #expect(peer.lastSeenAt == 1_756_886_400_000)
    }
}
