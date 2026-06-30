import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

private enum CommandRunClientResponse: Sendable {
    case success(CommandRunSnapshot)
    case failure(String)

    init(_ response: Result<CommandRunSnapshot, Error>) {
        switch response {
        case .success(let snapshot):
            self = .success(snapshot)
        case .failure(let error):
            self = .failure(error.localizedDescription)
        }
    }
}


@MainActor
final class CommandRunViewModel: ObservableObject {
    enum RunStatus: Equatable {
        case preparing
        case running
        case succeeded(Int32)
        case failed(Int32)
        case timedOut
        case stopped
        case error(String)

        var title: String {
            switch self {
            case .preparing:
                return "准备中"
            case .running:
                return "运行中"
            case .succeeded:
                return "已完成"
            case .failed:
                return "失败"
            case .timedOut:
                return "已超时"
            case .stopped:
                return "已停止"
            case .error:
                return "错误"
            }
        }

        var color: Color {
            switch self {
            case .preparing, .running:
                return SettingsTheme.accent
            case .succeeded:
                return .green
            case .failed, .timedOut, .error:
                return .red
            case .stopped:
                return .orange
            }
        }
    }

    @Published var title = "命令运行"
    @Published var command = ""
    @Published var workingDirectory = ""
    @Published var output = ""
    @Published var status: RunStatus = .preparing
    @Published var exitCode: Int32?
    @Published var durationText = "—"

    private let request: PendingCommandRunRequest
    private let onFinish: () -> Void
    private let actionRunnerClient = RightClickProActionRunnerXPCClient()
    private var didNotifyFinish = false
    private var pollTask: Task<Void, Never>?

    init(
        request: PendingCommandRunRequest,
        onFinish: @escaping () -> Void
    ) {
        self.request = request
        self.onFinish = onFinish
    }

    deinit {
        pollTask?.cancel()
    }

    func start() {
        guard pollTask == nil, !statusIsTerminal else {
            return
        }

        status = .preparing
        actionRunnerClient.startCommandRun(request) { [weak self] result in
            guard let viewModel = self else {
                return
            }
            let response = CommandRunClientResponse(result)
            DispatchQueue.main.async { [weak viewModel, response] in
                guard let viewModel else { return }
                switch response {
                case .success(let snapshot):
                    viewModel.apply(snapshot: snapshot)
                    if !snapshot.status.isTerminal {
                        viewModel.scheduleStatusPolling()
                    }
                case .failure(let errorMessage):
                    viewModel.status = .error(errorMessage)
                    viewModel.output = "运行失败：\(errorMessage)\n"
                    viewModel.notifyFinishIfNeeded()
                }
            }
        }
    }

    func stop() {
        actionRunnerClient.stopCommandRun(runID: request.id) { [weak self] result in
            guard let viewModel = self else {
                return
            }
            let response = CommandRunClientResponse(result)
            DispatchQueue.main.async { [weak viewModel, response] in
                guard let viewModel else { return }
                switch response {
                case .success(let snapshot):
                    viewModel.apply(snapshot: snapshot)
                case .failure(let errorMessage):
                    viewModel.status = .error(errorMessage)
                    viewModel.output += "\n停止命令失败：\(errorMessage)\n"
                    viewModel.notifyFinishIfNeeded()
                }
            }
        }
    }

    private var statusIsTerminal: Bool {
        switch status {
        case .preparing, .running:
            return false
        case .succeeded, .failed, .timedOut, .stopped, .error:
            return true
        }
    }

    private func scheduleStatusPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, let self else {
                    return
                }
                self.pollStatus()
            }
        }
    }

    private func pollStatus() {
        actionRunnerClient.commandRunStatus(runID: request.id) { [weak self] result in
            guard let viewModel = self else {
                return
            }
            let response = CommandRunClientResponse(result)
            DispatchQueue.main.async { [weak viewModel, response] in
                guard let viewModel else { return }
                switch response {
                case .success(let snapshot):
                    viewModel.apply(snapshot: snapshot)
                case .failure(let errorMessage):
                    viewModel.pollTask?.cancel()
                    viewModel.pollTask = nil
                    viewModel.status = .error(errorMessage)
                    viewModel.output += "\n读取命令状态失败：\(errorMessage)\n"
                    viewModel.notifyFinishIfNeeded()
                }
            }
        }
    }

    private func apply(snapshot: CommandRunSnapshot) {
        title = snapshot.title
        command = snapshot.command
        workingDirectory = snapshot.workingDirectory
        output = snapshot.combinedOutput
        exitCode = snapshot.exitCode
        durationText = formattedDuration(milliseconds: snapshot.durationMilliseconds)
        status = runStatus(for: snapshot)

        if snapshot.status.isTerminal {
            pollTask?.cancel()
            pollTask = nil
            notifyFinishIfNeeded()
        }
    }

    private func runStatus(for snapshot: CommandRunSnapshot) -> RunStatus {
        switch snapshot.status {
        case .preparing:
            return .preparing
        case .running:
            return .running
        case .succeeded:
            return .succeeded(snapshot.exitCode ?? 0)
        case .failed:
            return .failed(snapshot.exitCode ?? 1)
        case .timedOut:
            return .timedOut
        case .stopped:
            return .stopped
        case .error:
            return .error(snapshot.errorMessage ?? "命令运行失败")
        }
    }

    private func formattedDuration(milliseconds: Int?) -> String {
        guard let milliseconds else {
            return "—"
        }
        return String(format: "%.1fs", Double(milliseconds) / 1000)
    }

    private func notifyFinishIfNeeded() {
        guard !didNotifyFinish else {
            return
        }
        didNotifyFinish = true
        onFinish()
    }

}

@MainActor
final class CommandRunWindowCoordinator {
    static let shared = CommandRunWindowCoordinator()
    private var windows: [UUID: NSWindow] = [:]

    func open(
        request: PendingCommandRunRequest,
        paths: RightClickProStoragePaths,
        onFinish: @escaping () -> Void
    ) {
        let viewModel = CommandRunViewModel(request: request, onFinish: onFinish)
        let view = CommandRunWindow(viewModel: viewModel)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppMetadata.displayName) 命令运行"
        window.isReleasedWhenClosed = false
        window.backgroundColor = SettingsTheme.windowBackgroundColor
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        windows[request.id] = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.windows[request.id] = nil
            }
        }

        viewModel.start()
    }
}

struct CommandRunWindow: View {
    @ObservedObject var viewModel: CommandRunViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "terminal")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SettingsTheme.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.title)
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.ink)
                    Text(viewModel.workingDirectory.isEmpty ? "准备工作目录..." : viewModel.workingDirectory)
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Text(viewModel.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.status.color)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(viewModel.status.color.opacity(0.1), in: Capsule())

                Text(viewModel.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SettingsTheme.muted)
                    .frame(width: 64, alignment: .trailing)

                Button {
                    viewModel.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!isRunning)
            }
            .padding(18)
            .background(SettingsTheme.windowBackground)

            Divider()

            ScrollView {
                Text(viewModel.output.isEmpty ? "等待命令输出..." : viewModel.output)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SettingsTheme.commandOutputText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .background(SettingsTheme.commandOutputBackground)
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    private var isRunning: Bool {
        if case .running = viewModel.status {
            return true
        }
        return false
    }
}

