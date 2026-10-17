import Foundation
import Darwin
import idevice

/// Read the actual provisioning profiles installed on the paired iPhone via
/// MobileDevice misagent. SideStore's profile-only refresh updates these
/// installed profiles without replacing our embedded.mobileprovision.
enum MXInstalledProvisionReader {
    /// Run on a background queue; tunnel operations are synchronous.
    static func installedExpiration(pairingPath: String, deviceIP: String, bundleID: String) -> Date? {
        guard !pairingPath.isEmpty, !deviceIP.isEmpty, !bundleID.isEmpty else { return nil }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else { return nil }

        var pairingHandle: OpaquePointer?
        if let error = pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            idevice_error_free(error)
            return nil
        }
        guard let pairingHandle else { return nil }
        defer { rp_pairing_file_free(pairingHandle) }

        var adapter: OpaquePointer?
        var handshake: OpaquePointer?
        let tunnelError = withUnsafePointer(to: &address) { addressPtr in
            addressPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    "MXProfileCheck",
                    pairingHandle,
                    nil, nil,
                    &adapter, &handshake
                )
            }
        }
        if let tunnelError {
            idevice_error_free(tunnelError)
            return nil
        }
        defer {
            if let handshake { rsd_handshake_free(handshake) }
            if let adapter { adapter_free(adapter) }
        }
        guard let adapter, let handshake else { return nil }

        var misagent: OpaquePointer?
        if let error = misagent_connect_rsd(adapter, handshake, &misagent) {
            idevice_error_free(error)
            return nil
        }
        guard let misagent else { return nil }
        defer { misagent_client_free(misagent) }

        var profiles: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?
        var lengths: UnsafeMutablePointer<Int>?
        var count: Int = 0
        if let error = misagent_copy_all(misagent, &profiles, &lengths, &count) {
            idevice_error_free(error)
            return nil
        }
        defer {
            if let profiles, let lengths {
                misagent_free_profiles(profiles, lengths, count)
            }
        }
        guard let profiles, let lengths, count > 0, count < 500 else { return nil }

        var best: Date?
        for i in 0..<count {
            guard let pointer = profiles[i], lengths[i] > 0, lengths[i] < 4_000_000 else { continue }
            let data = Data(bytes: pointer, count: lengths[i])
            guard let profile = parsedProfile(data) else { continue }
            guard let entitlements = profile["Entitlements"] as? [String: Any] else { continue }

            let identifier = (entitlements["application-identifier"] as? String)
                ?? (entitlements["com.apple.application-identifier"] as? String)
            guard let identifier,
                  identifier == bundleID || identifier.hasSuffix("." + bundleID) else { continue }
            guard let expiration = profile["ExpirationDate"] as? Date else { continue }
            if best == nil || expiration > best! {
                best = expiration
            }
        }
        return best
    }

    private static func parsedProfile(_ data: Data) -> [String: Any]? {
        let xmlStart = Data("<?xml".utf8)
        let plistEnd = Data("</plist>".utf8)
        guard let start = data.range(of: xmlStart),
              let end = data.range(of: plistEnd, in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any]
    }
}
