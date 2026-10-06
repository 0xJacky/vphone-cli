import Testing
@testable import VPhoneDesignKit

/// How a disabled button looks, whatever its variant.
@Suite("DesignKit button")
struct DKButtonTests {
    @Test
    func `bordered and filled buttons turn into a gray well when disabled`() {
        for variant in [DKButtonVariant.secondary, .primary, .danger, .pressed, .recording] {
            #expect(DKButtonStyle.disabledShowsWell(variant), "\(variant)")
        }
    }

    @Test
    func `borderless buttons only gray their text when disabled`() {
        for variant in [DKButtonVariant.ghost, .ghostOn, .plain] {
            #expect(!DKButtonStyle.disabledShowsWell(variant), "\(variant)")
        }
    }

    @Test
    func `every variant has a disabled look`() {
        #expect(DKButtonVariant.allCases.count == 8)
    }
}
