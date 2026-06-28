import Foundation

public enum FinderSyncScope {
    public static var globalRoot: URL {
        URL(fileURLWithPath: "/")
    }

    public static func syncRoots() -> [URL] {
        [globalRoot]
    }

    public static func contextIsInGlobalScope(_ context: FinderContext) -> Bool {
        true
    }
}
