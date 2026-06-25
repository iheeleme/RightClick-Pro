import Foundation

public protocol URLOpening {
    func open(_ url: URL) throws
}

public protocol DeveloperAppOpening {
    func open(_ entrypoint: DeveloperEntrypoint, targetURL: URL) throws
}

public enum AppOpeningError: Error, Equatable, LocalizedError {
    case appKitUnavailable
    case cannotOpen(String)

    public var errorDescription: String? {
        switch self {
        case .appKitUnavailable:
            return "当前环境不支持 AppKit 打开动作"
        case .cannotOpen(let target):
            return "无法打开：\(target)"
        }
    }
}

public final class RecordingURLOpener: URLOpening, DeveloperAppOpening {
    public private(set) var openedURLs: [URL] = []
    public private(set) var openedApps: [(DeveloperEntrypoint, URL)] = []

    public init() {}

    public func open(_ url: URL) throws {
        openedURLs.append(url)
    }

    public func open(_ entrypoint: DeveloperEntrypoint, targetURL: URL) throws {
        openedApps.append((entrypoint, targetURL))
    }
}

#if canImport(AppKit)
import AppKit

public struct NSWorkspaceURLOpener: URLOpening, DeveloperAppOpening {
    public init() {}

    public func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw AppOpeningError.cannotOpen(url.path)
        }
    }

    public func open(_ entrypoint: DeveloperEntrypoint, targetURL: URL) throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entrypoint.bundleIdentifier) else {
            throw AppOpeningError.cannotOpen(entrypoint.bundleIdentifier)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [targetURL],
            withApplicationAt: appURL,
            configuration: configuration
        ) { _, _ in }
    }
}
#endif
