import Testing

@testable import ChetCore

struct AXSelectorTests {
    @Test func emptySelectorMatchesEveryNode() {
        let selector = AXSelector([])
        #expect(selector.isEmpty)
        #expect(selector.matches())
        #expect(
            selector.matches(
                id: "save", role: "AXButton", desc: "Save", title: "Save", value: "Save",
                enabled: false))
    }

    @Test func keyedTermRequiresTheKeyedValue() {
        let selector = AXSelector(["id=save"])
        #expect(selector.matches(id: "save"))
        #expect(!selector.matches(id: "cancel"))
        #expect(!selector.matches())
        #expect(AXSelector(["title=Settings"]).matches(title: "Settings"))
        #expect(!AXSelector(["title=Settings"]).matches(title: ""))
        #expect(AXSelector(["description=Back"]).matches(desc: "Back"))
        #expect(AXSelector(["desc=Back"]).matches(desc: "Back"))
    }

    @Test func enabledTermMatchesParsedBooleans() {
        #expect(AXSelector(["enabled=true"]).matches(enabled: true))
        #expect(!AXSelector(["enabled=true"]).matches(enabled: false))
        #expect(AXSelector(["enabled=1"]).matches(enabled: true))
        #expect(AXSelector(["enabled=false"]).matches(enabled: false))
        #expect(AXSelector(["enabled=0"]).matches(enabled: false))
        #expect(!AXSelector(["enabled=false"]).matches(enabled: true))
        #expect(!AXSelector(["enabled=0"]).matches(enabled: true))
        #expect(!AXSelector(["enabled=true"]).matches(enabled: nil))
        #expect(!AXSelector(["enabled=maybe"]).matches(enabled: true))
    }

    @Test func identicalOperandsParseIdentically() {
        let operands = ["id=save", "Beta", "enabled=0"]
        let first = AXSelector(operands)
        let second = AXSelector(operands)
        #expect(first == second)
        #expect(first.terms.map(\.key) == [.id, .contains, .enabled])
        #expect(first.terms.map(\.value) == ["save", "Beta", "0"])
    }

    @Test func bareTermSearchesIdRoleDescriptionTitleAndValue() {
        let selector = AXSelector(["Needle"])
        #expect(selector.matches(id: "a-needle-b"))
        #expect(selector.matches(role: "AXNeedleButton"))
        #expect(selector.matches(desc: "needle"))
        #expect(selector.matches(title: "NEEDLE"))
        #expect(selector.matches(value: "xNeedley"))
    }

    @Test func bareTermMissesWhenNoFieldContainsIt() {
        #expect(
            !AXSelector(["needle"]).matches(
                id: "save", role: "AXButton", desc: "Save", title: "Save", value: "Save"))
        #expect(!AXSelector(["needle"]).matches())
    }

    @Test func contradictoryTermsMatchNothing() {
        let selector = AXSelector(["id=alpha", "id=beta"])
        #expect(!selector.matches(id: "alpha"))
        #expect(!selector.matches(id: "beta"))
        #expect(!selector.matches())
        #expect(!AXSelector(["bogus=alpha"]).matches(id: "alpha"))
    }
}
