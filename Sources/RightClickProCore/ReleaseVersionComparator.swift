import Foundation

public enum ReleaseVersionComparison: Equatable, Sendable {
    case updateAvailable
    case upToDate
    case unknown
}

public enum ReleaseVersionComparator {
    public static func compare(currentVersion: String, latestTag: String) -> ReleaseVersionComparison {
        guard
            let current = ParsedReleaseVersion(currentVersion),
            let latest = ParsedReleaseVersion(latestTag)
        else {
            return .unknown
        }

        let componentCount = max(current.components.count, latest.components.count)
        let currentComponents = current.components.padding(toAtLeast: componentCount, with: 0)
        let latestComponents = latest.components.padding(toAtLeast: componentCount, with: 0)

        if latestComponents.lexicographicallyPrecedes(currentComponents) {
            return .upToDate
        }

        return latestComponents == currentComponents ? .upToDate : .updateAvailable
    }
}

private struct ParsedReleaseVersion: Equatable {
    let components: [Int]

    init?(_ rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .dropPrefix("v")
            .split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0]

        let parsedComponents = normalized.split(separator: ".", omittingEmptySubsequences: false).map { component -> Int? in
            guard !component.isEmpty, component.allSatisfy(\.isNumber) else {
                return nil
            }
            return Int(component)
        }

        guard !parsedComponents.isEmpty, parsedComponents.allSatisfy({ $0 != nil }) else {
            return nil
        }

        let numericComponents = parsedComponents.compactMap { $0 }
        guard numericComponents.contains(where: { $0 >= 0 }) else {
            return nil
        }

        self.components = numericComponents.padding(toAtLeast: 3, with: 0)
    }
}

private extension String {
    func dropPrefix(_ prefix: Character) -> String {
        guard first?.lowercased() == String(prefix).lowercased() else {
            return self
        }
        return String(dropFirst())
    }
}

private extension Array where Element == Int {
    func padding(toAtLeast minimumCount: Int, with value: Int) -> [Int] {
        guard count < minimumCount else {
            return self
        }
        return self + Array(repeating: value, count: minimumCount - count)
    }
}
