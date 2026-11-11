import PingFrontCore
import PingFrontSuperwall
import Testing

@Suite("Superwall module")
struct SuperwallModuleTests {
    @Test("The README's setup compiles and names the module pingfront.superwall")
    func module() {
        let module: PingFrontModule = .superwall(placements: [SuperwallPlacement("winback_offer", title: "Come back for 50% off")])
        let tokenIdentified: PingFrontModule = .superwall(placements: [], identity: .storeAccountToken, reportsEntitlement: false)
        #expect(module.id == "pingfront.superwall")
        #expect(tokenIdentified.id == "pingfront.superwall")
        #expect(SuperwallPlacement("p", title: "P").kind == .standard)
    }
}
