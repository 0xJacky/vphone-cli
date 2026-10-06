import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import Virtualization

// MARK: - Connection

/// One terminal's WebSocket to vphoned, on a VSOCK connection of its own.
///
/// Everything here is thread-safe: Ghostty hands keystrokes and sizes over on
/// its own threads, and output goes straight back to Ghostty from the event
/// loop without passing through the main actor. Input typed before the
/// connection is up waits, up to `maximumPendingInput` bytes.
final class VPhoneTerminalConnection: @unchecked Sendable {
    struct Handlers: Sendable {
        /// Shell output, in order, on the event loop.
        var output: @Sendable (Data) -> Void
        /// A control message from the guest, in order with the output.
        var message: @Sendable (VPhoneTerminalWire.Message) -> Void
        /// Called once, when the connection is gone; with a reason when it
        /// never opened.
        var closed: @Sendable (String?) -> Void
    }

    /// One loop serves every terminal of the VM: they are light.
    private static let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private static let maximumPendingInput = 64 * 1024

    private let lock = NSLock()
    private var handlers: Handlers?
    private var channel: Channel?
    private var socket: VPhoneTerminalSocket?
    private var isOpen = false
    private var isClosing = false
    private var didReportClose = false
    private var pendingInput = Data()
    private var latestSize: VPhoneTerminalWire.Size?
    private var sentSize: VPhoneTerminalWire.Size?

    func setHandlers(_ handlers: Handlers) {
        lock.withLock { self.handlers = handlers }
    }

    /// The last size Ghostty reported, which a new connection opens with.
    var size: VPhoneTerminalWire.Size? {
        lock.withLock { latestSize }
    }

    // MARK: Opening

    /// Starts the WebSocket handshake for `target` on `socket`. The socket is
    /// kept, and closed, with the connection.
    func start(socket connection: VZVirtioSocketConnection, size: VPhoneTerminalWire.Size, machineName: String?) {
        let socket = VPhoneTerminalSocket(connection)
        let target = VPhoneTerminalWire.requestTarget(size: size, machineName: machineName)
        let closing = lock.withLock {
            self.socket = socket
            sentSize = size
            return isClosing
        }
        guard !closing else {
            socket.close()
            return
        }
        // NIO owns a duplicate; Virtualization's descriptor stays with `socket`.
        let descriptor = dup(connection.fileDescriptor)
        guard descriptor >= 0 else {
            socket.close()
            report(closed: String(cString: strerror(errno)))
            return
        }
        ClientBootstrap(group: Self.group)
            .channelInitializer { [self] channel in
                let upgrader = NIOWebSocketClientUpgrader(maxFrameSize: 1 << 20) { [self] channel, _ in
                    // The refusal handler reads HTTP; frames must not reach it.
                    channel.pipeline.removeHandler(name: VPhoneTerminalRefusalHandler.name).flatMapThrowing {
                        try channel.pipeline.syncOperations.addHandlers([
                            NIOWebSocketFrameAggregator(
                                minNonFinalFragmentSize: 1,
                                maxAccumulatedFrameCount: 32,
                                maxAccumulatedFrameSize: 1 << 20,
                            ),
                            VPhoneTerminalFrameHandler(connection: self),
                        ])
                    }
                }
                let upgrade: NIOHTTPClientUpgradeSendableConfiguration = (
                    upgraders: [upgrader],
                    completionHandler: { _ in },
                )
                return channel.pipeline.addHTTPClientHandlers(withClientUpgrade: upgrade).flatMapThrowing {
                    try channel.pipeline.syncOperations.addHandler(
                        VPhoneTerminalRefusalHandler(connection: self),
                        name: VPhoneTerminalRefusalHandler.name,
                    )
                }
            }
            .withConnectedSocket(descriptor)
            .whenComplete { [self] result in
                switch result {
                case let .success(channel):
                    let closing = lock.withLock {
                        self.channel = channel
                        return isClosing
                    }
                    guard !closing else {
                        channel.close(promise: nil)
                        return
                    }
                    var head = HTTPRequestHead(version: .http1_1, method: .GET, uri: target)
                    // vphoned admits only its own loopback names.
                    head.headers.add(name: "Host", value: "vphoned")
                    head.headers.add(name: "Content-Length", value: "0")
                    channel.write(HTTPClientRequestPart.head(head), promise: nil)
                    channel.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
                case let .failure(error):
                    socket.close()
                    report(closed: String(describing: error))
                }
            }
    }

    /// Called on the event loop once the WebSocket replaces HTTP.
    fileprivate func upgraded(_ channel: Channel) {
        let (input, resize) = lock.withLock { () -> (Data, VPhoneTerminalWire.Size?) in
            isOpen = true
            self.channel = channel
            let input = pendingInput
            pendingInput = Data()
            let resize = latestSize != nil && latestSize != sentSize ? latestSize : nil
            if resize != nil {
                sentSize = resize
            }
            return (input, resize)
        }
        if let resize {
            write(VPhoneTerminalWire.resizeMessage(resize), opcode: .text, on: channel)
        }
        for frame in VPhoneTerminalWire.inputFrames(input) {
            write(frame, opcode: .binary, on: channel)
        }
    }

    // MARK: Sending

    /// Keystrokes and pastes for the shell.
    func send(_ input: Data) {
        let channel: Channel? = lock.withLock {
            guard !isClosing else { return nil }
            guard isOpen else {
                if pendingInput.count + input.count <= Self.maximumPendingInput {
                    pendingInput.append(input)
                }
                return nil
            }
            return self.channel
        }
        guard let channel else { return }
        for frame in VPhoneTerminalWire.inputFrames(input) {
            write(frame, opcode: .binary, on: channel)
        }
    }

    /// The terminal's grid size; sent only when it changed.
    func resize(_ size: VPhoneTerminalWire.Size) {
        let channel: Channel? = lock.withLock {
            latestSize = size
            guard isOpen, !isClosing, sentSize != size else { return nil }
            sentSize = size
            return self.channel
        }
        guard let channel else { return }
        write(VPhoneTerminalWire.resizeMessage(size), opcode: .text, on: channel)
    }

    /// Ends the session: the guest hangs the shell up when the connection goes.
    func close() {
        let (channel, socket, wasOpen) = lock.withLock { () -> (Channel?, VPhoneTerminalSocket?, Bool) in
            guard !isClosing else { return (nil, nil, false) }
            isClosing = true
            return (self.channel, self.socket, isOpen)
        }
        guard let channel else {
            socket?.close()
            report(closed: nil)
            return
        }
        if wasOpen {
            var code = channel.allocator.buffer(capacity: 2)
            code.writeInteger(UInt16(1000), endianness: .big)
            let frame = WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: .random(), data: code)
            channel.writeAndFlush(frame).whenComplete { _ in channel.close(promise: nil) }
        } else {
            channel.close(promise: nil)
        }
    }

    private func write(_ data: Data, opcode: WebSocketOpcode, on channel: Channel) {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        // A client masks every frame it sends (RFC 6455 §5.3).
        channel.writeAndFlush(WebSocketFrame(fin: true, opcode: opcode, maskKey: .random(), data: buffer), promise: nil)
    }

    // MARK: Receiving

    fileprivate func received(output: ByteBuffer) {
        guard let handlers = lock.withLock({ handlers }), output.readableBytes > 0 else { return }
        handlers.output(Data(output.readableBytesView))
    }

    fileprivate func received(message: VPhoneTerminalWire.Message) {
        lock.withLock { handlers }?.message(message)
    }

    fileprivate func channelClosed(reason: String?) {
        let socket = lock.withLock { () -> VPhoneTerminalSocket? in
            isOpen = false
            isClosing = true
            channel = nil
            return self.socket
        }
        socket?.close()
        report(closed: reason)
    }

    private func report(closed reason: String?) {
        let handlers = lock.withLock { () -> Handlers? in
            guard !didReportClose else { return nil }
            didReportClose = true
            isClosing = true
            let handlers = self.handlers
            self.handlers = nil
            return handlers
        }
        handlers?.closed(reason)
    }
}

// MARK: - Socket

/// Keeps Virtualization's socket, and so its descriptor, alive while NIO
/// uses a duplicate of it.
private final class VPhoneTerminalSocket: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: VZVirtioSocketConnection?

    init(_ connection: VZVirtioSocketConnection) {
        self.connection = connection
    }

    func close() {
        lock.withLock {
            connection?.close()
            connection = nil
        }
    }
}

// MARK: - Handlers

/// Before the upgrade: anything but `101 Switching Protocols` is a refusal.
private final class VPhoneTerminalRefusalHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart
    static let name = "vphone.terminal.refusal"

    private let connection: VPhoneTerminalConnection
    private var reason: String?

    init(connection: VPhoneTerminalConnection) {
        self.connection = connection
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if case let .head(head) = unwrapInboundIn(data) {
            reason = VPhoneLocalization.format("The guest refused the terminal (HTTP %ld).", head.status.code)
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        reason = reason ?? String(describing: error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        connection.channelClosed(reason: reason ?? VPhoneLocalization.text("The guest closed the connection."))
        context.fireChannelInactive()
    }
}

/// After the upgrade: output and control messages in, close handling.
private final class VPhoneTerminalFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let connection: VPhoneTerminalConnection
    private var reason: String?

    init(connection: VPhoneTerminalConnection) {
        self.connection = connection
    }

    func handlerAdded(context: ChannelHandlerContext) {
        connection.upgraded(context.channel)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .binary:
            connection.received(output: frame.unmaskedData)
        case .text:
            let buffer = frame.unmaskedData
            if let message = VPhoneTerminalWire.Message(json: Data(buffer.readableBytesView)) {
                if case let .failed(_, text) = message {
                    reason = text
                }
                connection.received(message: message)
            }
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, maskKey: .random(), data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .connectionClose:
            // Answer the guest's close; it waits for this side to drop the
            // connection so none of its last output is lost.
            let channel = context.channel
            let echo = WebSocketFrame(fin: true, opcode: .connectionClose, maskKey: .random(), data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(echo)).whenComplete { _ in channel.close(promise: nil) }
        default:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        connection.channelClosed(reason: reason)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error _: Error) {
        context.close(promise: nil)
    }
}
