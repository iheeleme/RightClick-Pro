import Foundation

/// 每个请求独立落盘，锁覆盖读取、交付和确认，防止多消费者重复领取。
public struct PendingCommandRunQueue: Sendable {
    private let directory: URL

    public init(paths: RightClickProStoragePaths) {
        directory = paths.baseURL.appendingPathComponent("pending-command-runs", isDirectory: true)
    }

    public func enqueue(_ request: PendingCommandRunRequest) throws {
        try FileTransactionLock.withLock(at: directory.appendingPathComponent(".lock")) {
            try JSONFileStore<PendingCommandRunRequest>(url: requestURL(request.id)).save(request)
        }
    }

    @discardableResult
    public func consumeNext(_ receive: (PendingCommandRunRequest) throws -> Void) throws -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        return try FileTransactionLock.withLock(at: directory.appendingPathComponent(".lock")) {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            var requests: [PendingCommandRunRequest] = []
            var readError: Error?
            for url in urls where url.pathExtension == "json" {
                do {
                    let request = try JSONFileStore<PendingCommandRunRequest>(url: url).loadRequired()
                    guard url.lastPathComponent == requestURL(request.id).lastPathComponent else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    requests.append(request)
                } catch {
                    readError = error
                }
            }
            requests.sort { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.createdAt < rhs.createdAt
            }
            guard let request = requests.first else {
                if let readError { throw readError }
                return false
            }
            try receive(request)
            try FileManager.default.removeItem(at: requestURL(request.id))
            return true
        }
    }

    private func requestURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
