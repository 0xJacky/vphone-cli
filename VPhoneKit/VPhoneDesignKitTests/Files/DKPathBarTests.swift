import Testing
@testable import VPhoneDesignKit

/// How the path bar splits a path into clickable folders.
@Suite("DesignKit path bar")
struct DKPathBarTests {
    @Test
    func `an absolute path splits into cumulative components`() {
        let components = DKPathComponent.components(of: "/var/mobile")
        #expect(components.map(\.name) == ["var", "mobile"])
        #expect(components.map(\.path) == ["/var", "/var/mobile"])
    }

    @Test
    func `the root has no components`() {
        #expect(DKPathComponent.components(of: "/").isEmpty)
        #expect(DKPathComponent.components(of: "").isEmpty)
    }

    @Test
    func `repeated and trailing slashes are ignored`() {
        let components = DKPathComponent.components(of: "//private///var/mobile/")
        #expect(components.map(\.name) == ["private", "var", "mobile"])
        #expect(components.last?.path == "/private/var/mobile")
    }

    @Test
    func `a relative path stays relative`() {
        let components = DKPathComponent.components(of: "Documents/Inbox")
        #expect(components.map(\.path) == ["Documents", "Documents/Inbox"])
    }

    @Test
    func `component identities stay unique when names repeat`() {
        let components = DKPathComponent.components(of: "/a/a/a")
        #expect(Set(components.map(\.id)).count == 3)
    }

    @Test
    func `names keep spaces and dots`() {
        let components = DKPathComponent.components(of: "/var/mobile/My Files/v1.2")
        #expect(components.map(\.name) == ["var", "mobile", "My Files", "v1.2"])
    }
}
