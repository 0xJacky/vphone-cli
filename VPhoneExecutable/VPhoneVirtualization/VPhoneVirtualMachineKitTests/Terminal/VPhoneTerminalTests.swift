import Foundation
import Testing
import VPhoneDesignKit
@testable import VPhoneVirtualMachineKit

// MARK: - Wire

@Suite("Terminal wire")
struct VPhoneTerminalWireTests {
    @Test
    func `the request target carries the size and the machine name`() {
        let target = VPhoneTerminalWire.requestTarget(
            size: .init(columns: 132, rows: 43),
            machineName: "research 26",
        )
        #expect(target == "/v1/terminal?cols=132&rows=43&name=research%2026")
        #expect(VPhoneTerminalWire.requestTarget(size: .fallback, machineName: nil) == "/v1/terminal?cols=80&rows=24")
    }

    @Test
    func `sizes are clamped to what vphoned accepts`() {
        #expect(VPhoneTerminalWire.Size(columns: 0, rows: -3) == .init(columns: 1, rows: 1))
        #expect(VPhoneTerminalWire.Size(columns: 5000, rows: 1001) == .init(columns: 1000, rows: 1000))
    }

    @Test
    func `a resize is one JSON control message`() throws {
        let data = VPhoneTerminalWire.resizeMessage(.init(columns: 100, rows: 30))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "resize")
        #expect(object["cols"] as? Int == 100)
        #expect(object["rows"] as? Int == 30)
    }

    @Test
    func `large input is cut into frames vphoned takes whole`() {
        #expect(VPhoneTerminalWire.inputFrames(Data()).isEmpty)
        #expect(VPhoneTerminalWire.inputFrames(Data("ls\r".utf8)) == [Data("ls\r".utf8)])
        let paste = Data((0 ..< 150_000).map { UInt8($0 % 251) })
        let frames = VPhoneTerminalWire.inputFrames(paste)
        #expect(frames.map(\.count) == [65536, 65536, 18928])
        #expect(Data(frames.joined()) == paste)
    }

    @Test
    func `guest messages decode`() {
        func message(_ json: String) -> VPhoneTerminalWire.Message? {
            VPhoneTerminalWire.Message(json: Data(json.utf8))
        }
        #expect(message(#"{"type":"started","pid":412,"shell":"/var/jb/usr/bin/bash","layout":"rootless","user":"mobile"}"#)
            == .started(pid: 412, shell: "/var/jb/usr/bin/bash", layout: "rootless", user: "mobile"))
        #expect(message(#"{"type":"exit","status":3}"#) == .exited(status: 3, signal: nil))
        #expect(message(#"{"type":"exit","signal":9}"#) == .exited(status: nil, signal: 9))
        #expect(message(#"{"type":"error","code":"no_shell","message":"Install the bootstrap"}"#)
            == .failed(code: "no_shell", message: "Install the bootstrap"))
        #expect(message(#"{"type":"something-new"}"#) == nil)
        #expect(message("not json") == nil)
    }
}

// MARK: - Session State

@Suite("Terminal session state")
struct VPhoneTerminalSessionStateTests {
    @Test
    func `a shell starts, runs and exits`() {
        var state = VPhoneTerminalSessionState.connecting
        #expect(state.isLive)
        #expect(state.tone == .warning)

        state.apply(.started(pid: 1, shell: "/usr/bin/bash", layout: "roothide", user: "mobile"))
        #expect(state == .running(shell: "/usr/bin/bash"))
        #expect(state.tone == .success)
        #expect(state.notice == nil)

        state.apply(.exited(status: 2, signal: nil))
        #expect(state == .exited(status: 2, signal: nil))
        #expect(!state.isLive)
        #expect(!state.closesTab)
        #expect(state.notice?.contains("2") == true)

        // A connection that closes after the exit changes nothing.
        state.connectionClosed(reason: nil)
        #expect(state == .exited(status: 2, signal: nil))
    }

    @Test
    func `only a clean exit closes the tab`() {
        var clean = VPhoneTerminalSessionState.running(shell: "/bin/sh")
        clean.apply(.exited(status: 0, signal: nil))
        #expect(clean.closesTab)

        var killed = VPhoneTerminalSessionState.running(shell: "/bin/sh")
        killed.apply(.exited(status: nil, signal: 9))
        #expect(!killed.closesTab)
        #expect(killed.tone == .idle)
    }

    @Test
    func `a guest without a shell fails the tab with its message`() {
        var state = VPhoneTerminalSessionState.connecting
        state.apply(.failed(code: "no_shell", message: "Install the bootstrap"))
        #expect(state == .failed("Install the bootstrap"))
        #expect(state.tone == .danger)
        #expect(state.notice == "Install the bootstrap")
        // The close that follows keeps the guest's reason.
        state.connectionClosed(reason: "closed")
        #expect(state == .failed("Install the bootstrap"))
    }

    @Test
    func `losing the connection disconnects a running shell and fails a pending one`() {
        var running = VPhoneTerminalSessionState.running(shell: "/bin/sh")
        running.connectionClosed(reason: nil)
        #expect(running == .disconnected)
        #expect(running.tone == .danger)

        var pending = VPhoneTerminalSessionState.connecting
        pending.connectionClosed(reason: "HTTP 400")
        #expect(pending == .failed("HTTP 400"))
    }

    @Test
    func `messages out of order are ignored`() {
        var state = VPhoneTerminalSessionState.exited(status: 0, signal: nil)
        state.apply(.started(pid: 2, shell: "/bin/sh", layout: nil, user: nil))
        #expect(state == .exited(status: 0, signal: nil))
    }
}

// MARK: - Tabs

@Suite("Terminal tabs")
struct VPhoneTerminalTabListTests {
    @Test
    func `tabs are numbered after the machine and start over when all close`() {
        var list = VPhoneTerminalTabList<Int>()
        #expect(list.add(1) == 1)
        #expect(list.add(2) == 2)
        #expect(list.add(3) == 3)
        #expect(VPhoneTerminalTabList<Int>.title(machine: "research-26", number: 1) == "research-26")
        #expect(VPhoneTerminalTabList<Int>.title(machine: "research-26", number: 2) == "research-26 (2)")

        // Numbers go on from the highest open tab.
        list.remove(2)
        #expect(list.add(4) == 4)
        list.remove(3)
        list.remove(4)
        #expect(list.add(5) == 2)

        list.remove(1)
        list.remove(5)
        #expect(list.isEmpty)
        #expect(list.add(6) == 1)
    }

    @Test
    func `a new tab is selected and closing it selects a neighbour`() {
        var list = VPhoneTerminalTabList<Int>()
        list.add(1)
        list.add(2)
        list.add(3)
        #expect(list.selection == 3)

        list.selection = 2
        list.remove(2)
        #expect(list.selection == 3)
        list.remove(3)
        #expect(list.selection == 1)
        // Closing a tab that is not selected keeps the selection.
        list.add(4)
        list.selection = 1
        list.remove(4)
        #expect(list.selection == 1)
        list.remove(1)
        #expect(list.selection == nil)
    }

    @Test
    func `keeping the strip's tabs drops the closed ones and follows its order`() {
        var list = VPhoneTerminalTabList<Int>()
        list.add(1)
        list.add(2)
        list.add(3)
        let dropped = list.keep([3, 1])
        #expect(dropped == [2])
        #expect(list.ids == [3, 1])
        #expect(list.number(of: 3) == 3)
        #expect(list.number(of: 2) == nil)
    }
}

// MARK: - Availability

@Suite("Terminal availability")
struct VPhoneTerminalAvailabilityTests {
    @Test
    func `the terminal needs a connected agent with the capability`() {
        #expect(VPhoneTerminalAvailability(capabilities: []) == .notConnected)
        #expect(VPhoneTerminalAvailability(capabilities: ["apps", "files"]) == .unsupported)
        #expect(VPhoneTerminalAvailability(capabilities: ["apps", "terminal"]) == .available)
        #expect(VPhoneTerminalAvailability.available.reason == nil)
        #expect(VPhoneTerminalAvailability.notConnected.reason != nil)
        #expect(VPhoneTerminalAvailability.unsupported.reason?.contains("terminal") == true)
    }
}
