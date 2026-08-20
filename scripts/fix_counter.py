from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
side_store_swift = root / "SideStoreSupport/SideStore.swift"
text = side_store_swift.read_text(encoding="utf-8")

old = '''        if let record {
            defaults.set(record.expirationDate, forKey: managedExpirationKey)
        } else {
            defaults.removeObject(forKey: managedExpirationKey)
        }
'''

new = '''        // Counter source of truth: use the actual installed host provisioning
        // profile as well as SideStore's database record. The guest app can run
        // with a virtualized Bundle.main, so reading its own bundle hierarchy can
        // leave the countdown stuck on the pre-refresh expiry.
        let hostExpiration = installedHostProvisioningExpirationDate()
        let counterExpiration = [record?.expirationDate, hostExpiration]
            .compactMap { $0 }
            .max()

        if let counterExpiration {
            defaults.set(counterExpiration, forKey: managedExpirationKey)
        } else {
            defaults.removeObject(forKey: managedExpirationKey)
        }
'''

if old not in text:
    raise RuntimeError("Counter metadata block not found")
text = text.replace(old, new, 1)

needle = '''    private static func refreshExtensionProfileExists() -> Bool {
'''
helper = '''    private static func installedHostProvisioningExpirationDate() -> Date? {
        let profileURL = UserDefaults.lcMainBundle().bundleURL
            .appendingPathComponent("embedded.mobileprovision", isDirectory: false)

        guard let data = try? Data(contentsOf: profileURL) else { return nil }
        let xmlStart = Data("<?xml".utf8)
        let plistEnd = Data("</plist>".utf8)
        guard let startRange = data.range(of: xmlStart),
              let endRange = data.range(
                of: plistEnd,
                options: [],
                in: startRange.lowerBound..<data.endIndex
              )
        else { return nil }

        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
              ),
              let dictionary = plist as? [String: Any]
        else { return nil }

        return dictionary["ExpirationDate"] as? Date
    }

'''

if needle not in text:
    raise RuntimeError("Counter helper insertion point not found")
text = text.replace(needle, helper + needle, 1)
side_store_swift.write_text(text, encoding="utf-8")
print("Fixed MX Location certificate countdown source at", side_store_swift)
