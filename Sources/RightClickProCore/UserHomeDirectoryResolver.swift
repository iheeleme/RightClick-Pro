import Foundation

enum UserHomeDirectoryResolver {
    /// Returns the login user's real home directory instead of the sandbox
    /// container home that FileManager may report inside app/extension targets.
    static func realUserHomeDirectory(
        processHomeDirectory: URL,
        override: URL? = nil
    ) -> URL {
        if let override {
            return override
        }
        if let home = realUserHomePath(), !home.isEmpty {
            return URL(fileURLWithPath: home)
        }
        return processHomeDirectory
    }

    private static func realUserHomePath() -> String? {
        guard let pw = getpwuid(getuid())?.pointee.pw_dir else {
            return nil
        }
        return String(cString: pw)
    }
}
