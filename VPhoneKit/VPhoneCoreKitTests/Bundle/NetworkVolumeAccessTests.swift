import Darwin
import Foundation
import Testing
@testable import VPhoneCoreKit

struct NetworkVolumeAccessTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func temporaryDirectoryIsLocal() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(!VPhoneNetworkVolumeAccess.isNetworkVolume(dir))
    }

    @Test func probeCreatesAndRemovesItsFile() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(VPhoneNetworkVolumeAccess.probe(directory: dir, timeout: 5) == .writable)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    @Test func aBlockedOpenTimesOut() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let started = Date()
        let outcome = VPhoneNetworkVolumeAccess.probe(directory: dir, timeout: 0.3) { _ in
            Thread.sleep(forTimeInterval: 5)
            return 0
        }
        #expect(outcome == .timedOut)
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func aFailedOpenReportsItsErrno() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(VPhoneNetworkVolumeAccess.probe(directory: dir, timeout: 5) { _ in EACCES } == .failed(EACCES))
    }

    @Test func aMissingDirectoryFailsWithoutWaiting() {
        let dir = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(VPhoneNetworkVolumeAccess.probe(directory: dir, timeout: 5) == .failed(ENOENT))
    }

    @Test func theMessageNamesTheDirectoryAndTheSetting() {
        let message = VPhoneNetworkVolumeAccess.consentMessage(
            directory: URL(fileURLWithPath: "/Users/u/.vphone/machines/m/MachineState"), waited: 30,
        )
        #expect(message.contains("/Users/u/.vphone/machines/m/MachineState"))
        #expect(message.contains("Network Volumes"))
        #expect(message.contains("30s"))
    }
}
