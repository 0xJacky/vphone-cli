import Darwin
import Foundation
import NIOCore
import NIOPosix
import NIOWebSocket
import VphonedNative

// MARK: - Wire

/// The host Terminal window's shells. Each shell is one WebSocket on
/// `/v1/terminal?cols=<n>&rows=<n>[&name=<machine>]`, and lives exactly as long
/// as that connection: closing it hangs the shell up.
///
/// - Binary frames carry terminal bytes: host to guest is keyboard input,
///   guest to host is the shell's output.
/// - Text frames carry JSON control messages. The host sends
///   `{"type":"resize","cols":n,"rows":n}`. The guest sends
///   `{"type":"started","pid":n,"shell":path,"layout":…,"user":"mobile"}` once
///   the shell runs, `{"type":"exit","status":n}` (or `"signal":n`) when it
///   ends, and `{"type":"error","code":…,"message":…}` when none could start;
///   the connection then closes.
///
/// A dedicated connection keeps a busy shell's output out of the RPC and event
/// channel and gives each direction VSOCK's own flow control.
enum GuestTerminalWire {
    static let path = "/v1/terminal"
    /// More would only be a runaway client.
    static let maximumSessions = 16
    static let sizeRange: ClosedRange<Int> = 1 ... 1000

    static func isTerminal(_ uri: String) -> Bool {
        uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first == Substring(path)
    }

    struct OpenRequest {
        var columns = 80
        var rows = 24
        var name: String?
    }

    static func openRequest(from uri: String) -> OpenRequest {
        var request = OpenRequest()
        let items = URLComponents(string: "http://vphoned\(uri)")?.queryItems ?? []
        for item in items {
            switch item.name {
            case "cols": request.columns = clampedSize(item.value, fallback: request.columns)
            case "rows": request.rows = clampedSize(item.value, fallback: request.rows)
            case "name": request.name = item.value.flatMap(promptName)
            default: break
            }
        }
        return request
    }

    static func clampedSize(_ value: Any?, fallback: Int) -> Int {
        let number: Int? = switch value {
        case let value as String: Int(value)
        case let value as NSNumber: value.intValue
        default: nil
        }
        guard let number else { return fallback }
        return min(max(number, sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// The machine name for the prompt, reduced to characters that need no
    /// quoting in PS1. Nil when nothing is left.
    static func promptName(_ name: String) -> String? {
        let allowed = name.unicodeScalars.filter { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "-_.".unicodeScalars.contains(scalar))
        }
        let value = String(String.UnicodeScalarView(allowed.prefix(64)))
        return value.isEmpty ? nil : value
    }

    static func message(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}

// MARK: - Shell

enum GuestTerminalError: Error, CustomStringConvertible {
    case noShell
    case tooManySessions
    case spawnFailed(path: String, errno: Int32)

    var code: String {
        switch self {
        case .noShell: "no_shell"
        case .tooManySessions: "too_many_sessions"
        case .spawnFailed: "spawn_failed"
        }
    }

    var description: String {
        switch self {
        case .noShell:
            "This guest has no shell. Install the bootstrap (Apps › Bootstrap › Install Bootstrap…), "
                + "then install OwnGoal Bootstrap for vphone (owngoal-bootstrap-vphone) in Irisin, and open a new tab."
        case .tooManySessions:
            "The guest already runs \(GuestTerminalWire.maximumSessions) terminal sessions. Close one, then try again."
        case let .spawnFailed(path, error):
            "Could not start \(path): \(String(cString: strerror(error)))"
        }
    }
}

/// Which shell a terminal runs, and how.
///
/// Stock iOS has no shell; one comes only from a bootstrap. The roots are
/// searched in the order vphoned itself recognises them: the one
/// `jailbreakInfo()` reports, the RootHide root vphone installs, the rootless
/// `/var/jb`, then a rootful `/`. In each, bash is preferred, then zsh, then sh.
///
/// The shell runs as `mobile` (uid and gid 501, the fixed iOS ids), as a login
/// shell (`-bash`), the way sshd starts it for that user. Its environment is
/// built here instead of inherited: vphoned's own is launchd's root one.
/// RootHide tools see "vroot" paths, the bootstrap's root as `/` (see
/// `GuestIrisinInstaller.runBootstrapTool`), so there PATH and HOME name
/// paths inside it, and the shell starts in the bootstrap's `/var/mobile`.
/// Rootless and rootful shells see real paths, so PATH lists the bootstrap's
/// bin directories before the system's.
struct GuestTerminalShell {
    let path: String
    let layout: String
    let arguments: [String]
    let environment: [String]
    let workingDirectory: String

    static let mobileUser: (name: String, uid: UInt32, gid: UInt32) = ("mobile", 501, 501)
    private static let candidates = ["usr/bin/bash", "bin/bash", "usr/bin/zsh", "bin/zsh", "usr/bin/sh", "bin/sh"]

    static func resolve(promptName: String?) throws -> GuestTerminalShell {
        let detected = GuestAPI.jailbreakInfo()
        var roots: [(root: String, layout: String)] = []
        if let root = detected["jbroot"] as? String, let layout = detected["layout"] as? String {
            roots.append((root, layout))
        }
        roots += [
            (GuestIrisinInstaller.roothideRoot, "roothide"),
            ("/var/jb", "rootless"),
            ("/", "rootful"),
        ]
        var seen = Set<String>()
        for (root, layout) in roots where seen.insert(root).inserted {
            for candidate in candidates {
                let path = root == "/" ? "/" + candidate : root + "/" + candidate
                guard FileManager.default.isExecutableFile(atPath: path) else { continue }
                return make(path: path, root: root, layout: layout, candidate: candidate, promptName: promptName)
            }
        }
        throw GuestTerminalError.noShell
    }

    private static func make(
        path: String,
        root: String,
        layout: String,
        candidate: String,
        promptName: String?,
    ) -> GuestTerminalShell {
        let systemPath = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        let home = "/var/mobile"
        let searchPath: String
        let shellPath: String
        var workingDirectory = home
        switch layout {
        case "roothide":
            searchPath = systemPath
            shellPath = "/" + candidate
            if isDirectory(root + home) {
                workingDirectory = root + home
            }
        case "rootless":
            searchPath = ["/usr/local/sbin", "/usr/local/bin", "/usr/sbin", "/usr/bin", "/sbin", "/bin"]
                .map { root + $0 }.joined(separator: ":") + ":/usr/sbin:/usr/bin:/sbin:/bin"
            shellPath = path
        default:
            searchPath = systemPath
            shellPath = path
        }
        let user = mobileUser.name
        var environment = [
            "HOME=\(home)",
            "USER=\(user)",
            "LOGNAME=\(user)",
            "SHELL=\(shellPath)",
            "PATH=\(searchPath)",
            "TERM=xterm-256color",
            "COLORTERM=truecolor",
            // No LANG: iOS has no en_US.UTF-8 locale, and Procursus readline
            // crashes in _rl_init_locale when a named locale cannot be set.
            // The bootstrap's profile sets the locale it ships.
        ]
        // A profile that sets its own prompt wins; this one is the design's.
        if let promptName, candidate.hasSuffix("bash") {
            environment.append("PS1=\\u@\(promptName) \\W \\$ ")
        } else if let promptName, candidate.hasSuffix("zsh") {
            environment.append("PS1=%n@\(promptName) %1~ %# ")
        }
        let name = (candidate as NSString).lastPathComponent
        return GuestTerminalShell(
            path: path,
            layout: layout,
            arguments: ["-" + name],
            environment: environment,
            workingDirectory: workingDirectory,
        )
    }

    private static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    /// Starts the shell on a new pseudo-terminal. Returns the master side and
    /// the child's pid; the caller reaps the child.
    func spawn(columns: Int, rows: Int) throws -> (master: Int32, pid: pid_t) {
        func cStrings(_ values: [String]) -> [UnsafeMutablePointer<CChar>?] {
            values.map { strdup($0) } + [nil]
        }
        let argv = cStrings(arguments)
        let envp = cStrings(environment)
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var master: Int32 = -1
        var pid: Int32 = 0
        let result = path.withCString { path in
            workingDirectory.withCString { directory in
                argv.withUnsafeBufferPointer { argv in
                    envp.withUnsafeBufferPointer { envp in
                        var request = VPPtySpawnRequest(
                            path: path,
                            argv: argv.baseAddress,
                            envp: envp.baseAddress,
                            cwd: directory,
                            uid: Self.mobileUser.uid,
                            gid: Self.mobileUser.gid,
                            columns: UInt16(clamping: columns),
                            rows: UInt16(clamping: rows),
                        )
                        return vp_pty_spawn(&request, &master, &pid)
                    }
                }
            }
        }
        guard result == 0 else {
            throw GuestTerminalError.spawnFailed(path: path, errno: result)
        }
        return (master, pid)
    }
}

// MARK: - Session Count

/// Sessions open across all connections, for `GuestTerminalWire.maximumSessions`.
final class GuestTerminalSessions: @unchecked Sendable {
    static let shared = GuestTerminalSessions()
    private let lock = NSLock()
    private var count = 0

    func reserve() -> Bool {
        lock.withLock {
            guard count < GuestTerminalWire.maximumSessions else { return false }
            count += 1
            return true
        }
    }

    func release() {
        lock.withLock { count = max(0, count - 1) }
    }
}

// MARK: - Child

/// Waits for one shell to exit and reaps it, so no session leaves a zombie.
/// It stays alive, through `live`, until the child is reaped, even after its
/// session is gone. `hangUp()` ends a shell whose host went away: SIGHUP to its
/// process group, as a closed terminal would send, then SIGKILL if it is still
/// there after a few seconds.
final class GuestTerminalChild: @unchecked Sendable {
    let pid: pid_t
    private let queue = DispatchQueue(label: "vphoned.terminal.child")
    private var source: DispatchSourceProcess?
    private var status: Int32?
    private var onExit: (@Sendable (Int32) -> Void)?

    private static let lock = NSLock()
    private nonisolated(unsafe) static var live: [pid_t: GuestTerminalChild] = [:]

    init(pid: pid_t, onExit: @escaping @Sendable (Int32) -> Void) {
        self.pid = pid
        self.onExit = onExit
        Self.lock.withLock { Self.live[pid] = self }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in self?.reap() }
        self.source = source
        source.activate()
        // A child that exited before the source was registered never fires it.
        queue.async { [weak self] in self?.reap() }
    }

    /// Hangs the shell up. `onExit` is not called afterwards.
    func hangUp() {
        queue.async { [self] in
            onExit = nil
            guard status == nil else { return }
            kill(-pid, SIGHUP)
            kill(pid, SIGHUP)
            queue.asyncAfter(deadline: .now() + 3) { [self] in
                guard status == nil else { return }
                kill(-pid, SIGKILL)
                kill(pid, SIGKILL)
            }
        }
    }

    private func reap() {
        guard status == nil else { return }
        var value: Int32 = 0
        var result: pid_t
        repeat {
            result = waitpid(pid, &value, WNOHANG)
        } while result < 0 && errno == EINTR
        guard result == pid || (result < 0 && errno == ECHILD) else { return }
        status = result == pid ? value : 0
        source?.cancel()
        source = nil
        let handler = onExit
        onExit = nil
        Self.lock.withLock { _ = Self.live.removeValue(forKey: pid) }
        handler?(status ?? 0)
    }
}

// MARK: - WebSocket Handler

/// One terminal session on its WebSocket. Everything runs on the WebSocket
/// channel's event loop: the pseudo-terminal's channel is created on the same
/// loop, so the two hand bytes to each other directly. Each side stops reading
/// while the other cannot take more, so neither buffers without bound.
final class GuestTerminalHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let request: GuestTerminalWire.OpenRequest
    private var webSocket: Channel?
    private var pty: Channel?
    /// A duplicate of the master side for TIOCSWINSZ; NIO owns the others.
    private var control: Int32 = -1
    private var child: GuestTerminalChild?
    private var reserved = false
    private var pending: [ByteBuffer] = []
    private var pendingBytes = 0
    private let maximumPendingBytes = 1 << 20
    private var closing = false
    private var outputEnded = false
    private var exitStatus: Int32?

    init(uri: String) {
        request = GuestTerminalWire.openRequest(from: uri)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let webSocket = context.channel
        self.webSocket = webSocket
        // Input waits until the terminal is there to take it.
        _ = webSocket.setOption(ChannelOptions.autoRead, value: false)
        guard GuestTerminalSessions.shared.reserve() else {
            fail(GuestTerminalError.tooManySessions)
            return
        }
        reserved = true
        let spawned: (master: Int32, pid: pid_t)
        let shell: GuestTerminalShell
        do {
            shell = try GuestTerminalShell.resolve(promptName: request.name)
            spawned = try shell.spawn(columns: request.columns, rows: request.rows)
        } catch {
            fail(error)
            return
        }
        NSLog("vphoned: terminal started %@ (%@) as pid %d", shell.path, shell.layout, spawned.pid)
        let eventLoop = context.eventLoop
        // The child holds this session until it exits or `hangUp()` lets go.
        child = GuestTerminalChild(pid: spawned.pid) { status in
            eventLoop.execute { self.childExited(status) }
        }
        control = dup(spawned.master)
        let output = dup(spawned.master)
        guard control >= 0, output >= 0 else {
            if output >= 0 { close(output) }
            close(spawned.master)
            fail(GuestTerminalError.spawnFailed(path: shell.path, errno: errno))
            return
        }
        NIOPipeBootstrap(group: eventLoop)
            .channelInitializer { [weak self] channel in
                guard let self else { return channel.eventLoop.makeSucceededVoidFuture() }
                return channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(GuestTerminalOutputHandler(session: self))
                }
            }
            .takingOwnershipOfDescriptors(input: spawned.master, output: output)
            .whenComplete { [self] result in
                switch result {
                case let .success(pty):
                    guard !closing, webSocket.isActive else {
                        pty.close(promise: nil)
                        return
                    }
                    self.pty = pty
                    sendMessage([
                        "type": "started", "pid": Int(spawned.pid), "shell": shell.path,
                        "layout": shell.layout, "user": GuestTerminalShell.mobileUser.name,
                    ])
                    for chunk in pending {
                        pty.write(chunk, promise: nil)
                    }
                    pty.flush()
                    pending.removeAll()
                    pendingBytes = 0
                    _ = webSocket.setOption(ChannelOptions.autoRead, value: pty.isWritable)
                case let .failure(error):
                    NSLog("vphoned: terminal could not attach its pty: %@", String(describing: error))
                    child?.hangUp()
                    fail(GuestTerminalError.spawnFailed(path: shell.path, errno: EIO))
                }
            }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard !closing else { return }
        switch frame.opcode {
        case .binary:
            let chunk = frame.unmaskedData
            if let pty {
                pty.writeAndFlush(chunk, promise: nil)
            } else {
                pendingBytes += chunk.readableBytes
                guard pendingBytes <= maximumPendingBytes else {
                    finish(code: 1011)
                    return
                }
                pending.append(chunk)
            }
        case .text:
            var buffer = frame.unmaskedData
            guard let bytes = buffer.readBytes(length: buffer.readableBytes),
                  let object = try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any]
            else { return }
            if object["type"] as? String == "resize" {
                resize(columns: object["cols"], rows: object["rows"])
            }
        case .ping:
            context.writeAndFlush(
                wrapOutboundOut(WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)),
                promise: nil,
            )
        case .connectionClose:
            closing = true
            let webSocket = context.channel
            context.writeAndFlush(
                wrapOutboundOut(WebSocketFrame(fin: true, opcode: .connectionClose, data: frame.unmaskedData)),
            ).whenComplete { _ in
                webSocket.closeAfterPeer()
            }
        default:
            break
        }
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        _ = pty?.setOption(ChannelOptions.autoRead, value: context.channel.isWritable)
        context.fireChannelWritabilityChanged()
    }

    /// The host went away or the session ended: hang the shell up and let go
    /// of everything this session holds.
    func channelInactive(context: ChannelHandlerContext) {
        closing = true
        child?.hangUp()
        child = nil
        pty?.close(promise: nil)
        pty = nil
        if control >= 0 {
            close(control)
            control = -1
        }
        pending.removeAll()
        if reserved {
            reserved = false
            GuestTerminalSessions.shared.release()
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        context.close(promise: nil)
    }

    // MARK: Terminal Side

    /// Called by the output handler, on this event loop.
    func ptyRead(_ buffer: ByteBuffer) {
        guard let webSocket, webSocket.isActive, !closing else { return }
        webSocket.writeAndFlush(WebSocketFrame(fin: true, opcode: .binary, data: buffer), promise: nil)
    }

    func ptyWritabilityChanged(_ writable: Bool) {
        _ = webSocket?.setOption(ChannelOptions.autoRead, value: writable)
    }

    var webSocketIsWritable: Bool {
        webSocket?.isWritable ?? false
    }

    /// The shell's side of the terminal closed: it exited, or closed it. The
    /// exit is reported once the child is reaped too.
    func ptyClosed() {
        outputEnded = true
        if let exitStatus {
            reportExit(exitStatus)
        } else {
            // A shell that closed its terminal but kept running is hung up.
            webSocket?.eventLoop.scheduleTask(in: .seconds(2)) { [weak self] in
                guard let self, exitStatus == nil, !closing else { return }
                child?.hangUp()
                finish(code: 1000)
            }
        }
    }

    private func childExited(_ status: Int32) {
        exitStatus = status
        // The last output can still be in the terminal; it ends right after.
        if outputEnded || pty == nil {
            reportExit(status)
        } else {
            // A background job can keep the terminal open after the shell is
            // gone; the session ends with the shell, as in Terminal.
            webSocket?.eventLoop.scheduleTask(in: .seconds(1)) { [weak self] in
                self?.reportExit(status)
            }
        }
    }

    private func reportExit(_ status: Int32) {
        guard !closing else { return }
        child = nil
        var message: [String: Any] = ["type": "exit"]
        if status & 0x7F == 0 {
            message["status"] = Int((status >> 8) & 0xFF)
        } else {
            message["signal"] = Int(status & 0x7F)
        }
        sendMessage(message)
        finish(code: 1000)
    }

    private func resize(columns: Any?, rows: Any?) {
        guard control >= 0 else { return }
        var size = winsize()
        size.ws_col = UInt16(GuestTerminalWire.clampedSize(columns, fallback: request.columns))
        size.ws_row = UInt16(GuestTerminalWire.clampedSize(rows, fallback: request.rows))
        // The kernel sends SIGWINCH to the terminal's foreground process group.
        _ = ioctl(control, TIOCSWINSZ, &size)
    }

    // MARK: Messages

    private func sendMessage(_ object: [String: Any]) {
        guard let webSocket, webSocket.isActive else { return }
        let data = GuestTerminalWire.message(object)
        var buffer = webSocket.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        webSocket.writeAndFlush(WebSocketFrame(fin: true, opcode: .text, data: buffer), promise: nil)
    }

    private func fail(_ error: Error) {
        let code = (error as? GuestTerminalError)?.code ?? "spawn_failed"
        NSLog("vphoned: terminal refused: %@", String(describing: error))
        sendMessage(["type": "error", "code": code, "message": String(describing: error)])
        finish(code: 1011)
    }

    /// Sends a close frame. The host closes the connection once it has read
    /// everything, which ends the session in `channelInactive`.
    private func finish(code: UInt16) {
        guard !closing, let webSocket, webSocket.isActive else { return }
        closing = true
        var data = webSocket.allocator.buffer(capacity: 2)
        data.writeInteger(code, endianness: .big)
        webSocket.writeAndFlush(WebSocketFrame(fin: true, opcode: .connectionClose, data: data)).whenComplete { _ in
            webSocket.closeAfterPeer()
        }
    }
}

// MARK: - Terminal Output

/// The pseudo-terminal's channel: each read becomes one binary frame.
private final class GuestTerminalOutputHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private weak var session: GuestTerminalHandler?

    init(session: GuestTerminalHandler) {
        self.session = session
    }

    func channelActive(context: ChannelHandlerContext) {
        _ = context.channel.setOption(ChannelOptions.autoRead, value: session?.webSocketIsWritable ?? true)
        context.fireChannelActive()
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        session?.ptyRead(unwrapInboundIn(data))
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        session?.ptyWritabilityChanged(context.channel.isWritable)
        context.fireChannelWritabilityChanged()
    }

    func channelInactive(context: ChannelHandlerContext) {
        session?.ptyClosed()
        context.fireChannelInactive()
    }

    /// Darwin reports a terminal whose last slave descriptor closed as EIO
    /// rather than end of file.
    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        context.close(promise: nil)
    }
}
