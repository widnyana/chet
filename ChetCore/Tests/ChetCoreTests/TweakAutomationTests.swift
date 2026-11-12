import Foundation
import Testing

@testable import ChetCore

struct TweakAutomationTests {
    @Test func resolvedValueIsTotalOverToggles() {
        for tweak in TweakCatalog.all {
            switch tweak.control {
            case .toggle(let on, let off):
                #expect(tweak.control.resolvedValue(for: .on) == on)
                #expect(tweak.control.resolvedValue(for: .off) == off)
            default:
                #expect(tweak.control.resolvedValue(for: .on) == nil)
                #expect(tweak.control.resolvedValue(for: .off) == nil)
            }
        }
    }

    @Test func resolvedValueDeletesTheKeyWhenOffIsAbsent() {
        let control = TweakControl.toggle(on: .boolean(true), off: nil)
        #expect(control.resolvedValue(for: .on) == .boolean(true))
        #expect(control.resolvedValue(for: .off) == nil)
    }
}
