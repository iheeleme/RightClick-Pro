import Foundation

public enum FinderExtensionInstallSignature {
    public static func make(appexURL: URL, hostBundleURL: URL? = nil) -> String {
        let standardizedAppexURL = appexURL.standardizedFileURL
        let infoURL = standardizedAppexURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        let executableURL = standardizedAppexURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(executableName(infoURL: infoURL))

        var components = [
            "appexPath=\(standardizedAppexURL.path)",
            "appex=\(resourceFingerprint(for: standardizedAppexURL))",
            "info=\(resourceFingerprint(for: infoURL))",
            "executable=\(resourceFingerprint(for: executableURL))",
            "shortVersion=\(infoValue("CFBundleShortVersionString", infoURL: infoURL) ?? "unknown")",
            "build=\(infoValue("CFBundleVersion", infoURL: infoURL) ?? "unknown")"
        ]

        if let hostBundleURL {
            components.append("host=\(resourceFingerprint(for: hostBundleURL.standardizedFileURL))")
        }

        return components.joined(separator: "|")
    }

    private static func executableName(infoURL: URL) -> String {
        infoValue("CFBundleExecutable", infoURL: infoURL) ?? "RightClickProFinderExtension"
    }

    private static func infoValue(_ key: String, infoURL: URL) -> String? {
        guard
            let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = plist as? [String: Any],
            let value = dictionary[key] as? String,
            !value.isEmpty
        else {
            return nil
        }

        return value
    }

    private static func resourceFingerprint(for url: URL) -> String {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .creationDateKey,
            .fileResourceIdentifierKey,
            .fileSizeKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return "missing"
        }

        let resourceID = values.fileResourceIdentifier.map { String(describing: $0) } ?? "no-resource-id"
        let createdAt = values.creationDate.map { "\($0.timeIntervalSince1970)" } ?? "no-created-at"
        let modifiedAt = values.contentModificationDate.map { "\($0.timeIntervalSince1970)" } ?? "no-modified-at"
        let fileSize = values.fileSize.map(String.init) ?? "no-size"

        return [
            "id:\(resourceID)",
            "created:\(createdAt)",
            "modified:\(modifiedAt)",
            "size:\(fileSize)"
        ].joined(separator: ",")
    }
}
