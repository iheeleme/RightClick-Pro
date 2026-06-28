import Foundation

public enum FullDiskAccessAdvisor {
    public static let guidance = "请在系统设置 > 隐私与安全性 > 完全磁盘访问权限中允许 RightClick Pro，然后重试。"

    public static func userFacingMessage(for error: Error) -> String {
        let message = error.localizedDescription
        guard isLikelyPermissionError(error) else {
            return message
        }
        return "\(message)\n\(guidance)"
    }

    public static func isLikelyPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            let permissionCodes: Set<Int> = [
                NSFileReadNoPermissionError,
                NSFileWriteNoPermissionError
            ]
            if permissionCodes.contains(nsError.code) {
                return true
            }
        }

        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(EACCES) || nsError.code == Int(EPERM)
        }

        let lowercased = nsError.localizedDescription.lowercased()
        return lowercased.contains("operation not permitted") ||
            lowercased.contains("permission denied") ||
            lowercased.contains("not authorized")
    }

    public static func checkRepresentativeAccess(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) -> Bool {
        let homeDirectory = homeDirectory ?? UserHomeDirectoryResolver.realUserHomeDirectory(
            processHomeDirectory: fileManager.homeDirectoryForCurrentUser
        )
        let protectedURLs = [
            homeDirectory.appendingPathComponent("Library/Mail"),
            homeDirectory.appendingPathComponent("Library/Messages"),
            homeDirectory.appendingPathComponent("Library/Safari"),
            homeDirectory.appendingPathComponent("Library/Application Support/com.apple.TCC")
        ]

        return protectedURLs.contains { url in
            do {
                _ = try fileManager.contentsOfDirectory(atPath: url.path)
                return true
            } catch {
                return false
            }
        }
    }
}
