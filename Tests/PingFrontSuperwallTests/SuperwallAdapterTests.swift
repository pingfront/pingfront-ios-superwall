import Foundation
import PingFrontAdapterKit
import PingFrontAdapterTestSupport
import PingFrontCore
import Testing

@testable import PingFrontSuperwall

/// Records every call the adapter makes to Superwall.
@MainActor final class FakeSuperwall: SuperwallClient {
    var isConfigured = true
    var current: SWStatus = .unknown
    var registerOutcome: OfferOutcome = .purchased
    private(set) var registered: [(placement: String, params: [String: String])] = []
    private(set) var identified: [String] = []
    private(set) var statusReads = 0
    private var signal: AsyncStream<Void>.Continuation?

    func status() -> SWStatus {
        statusReads += 1
        return current
    }

    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        signal = continuation
        return stream
    }

    func change(to status: SWStatus) {
        current = status
        signal?.yield()
    }

    func identify(userId: String) { identified.append(userId) }

    func register(placement: String, params: [String: String]) async -> OfferOutcome {
        registered.append((placement, params))
        return registerOutcome
    }
}

@Suite("Superwall adapter")
@MainActor struct SuperwallAdapterTests {
    let client = FakeSuperwall()
    let host = FakeHost()
    let placements = [
        SuperwallPlacement(
            "winback offer", title: "Come back for 50% off", kind: .winback,
            products: [OfferSlot.Product(id: "pro.annual", price: "€29.99", period: "P1Y")], params: ["source": "pingfront"]),
        SuperwallPlacement("upgrade", title: " "),
    ]

    func adapter(identity: SuperwallIdentity = .appManaged, reportsEntitlement: Bool = true, sleep: @escaping Sleep = noSleep)
        -> SuperwallAdapter
    {
        SuperwallAdapter(
            client: client, host: host, placements: placements, identity: identity, reportsEntitlement: reportsEntitlement, sleep: sleep)
    }

    @Test("Each placement becomes a slot with its title, kind and products")
    func slots() {
        adapter().refresh()
        let slots = host.lastOffers ?? []
        #expect(slots.map(\.id) == ["winback_offer", "upgrade"])
        #expect(slots[0].title == "Come back for 50% off")
        #expect(slots[0].kind == .winback)
        #expect(slots[0].products.map(\.id) == ["pro.annual"])
        #expect(slots[1].title == "upgrade")
        #expect(slots.allSatisfy { $0.isAvailable })
    }

    @Test("Reporting slots never registers a placement, so experiments and holdouts are untouched")
    func leavesExperimentsAlone() async {
        let adapter = adapter(sleep: yieldingSleep)
        let task = Task { await adapter.run() }
        #expect(await settle { host.lastOffers?.count == 2 })
        client.change(to: .active([AccessSnapshot(productId: "pro.monthly", isActive: true)]))
        host.setToken(sampleToken)
        #expect(await settle { host.entitlements.last?.state == .active && host.offers.count >= 2 })
        task.cancel()
        #expect(client.registered.isEmpty)
    }

    @Test("A slot is unavailable once the person owns every listed product")
    func availability() {
        client.current = .active([AccessSnapshot(productId: "pro.annual", isActive: true)])
        adapter().refresh()
        #expect(host.lastOffers?.map(\.isAvailable) == [false, true])
    }

    @Test("Subscription status maps to the entitlement with source superwall")
    func entitlement() {
        let adapter = adapter()
        adapter.refresh()
        #expect(host.entitlements.isEmpty)  // unknown: nothing to report yet
        client.current = .inactive
        adapter.refresh()
        client.current = .active([
            AccessSnapshot(productId: "pro.monthly", isActive: true, isTrial: true),
            AccessSnapshot(productId: "pro.annual", isActive: true, isInGracePeriod: true),
        ])
        adapter.refresh()
        #expect(host.entitlements.map(\.state) == [.none, .trial])
        #expect(host.entitlements.allSatisfy { $0.source == .superwall })
        #expect(host.entitlements.last?.productId == "pro.monthly")
    }

    @Test("reportsEntitlement false leaves the entitlement to another module")
    func noEntitlement() {
        client.current = .inactive
        adapter(reportsEntitlement: false).refresh()
        #expect(host.entitlements.isEmpty)
        #expect(host.lastOffers?.count == 2)
    }

    @Test("Identity storeAccountToken identifies Superwall with the token, once per person")
    func identifiesWithToken() {
        let adapter = adapter(identity: .storeAccountToken)
        adapter.tokenChanged(nil)
        adapter.tokenChanged(sampleToken)
        adapter.tokenChanged(sampleToken)
        #expect(client.identified == [tokenString(sampleToken)])
    }

    @Test("Identity appManaged never calls identify")
    func appManaged() {
        adapter().tokenChanged(sampleToken)
        #expect(client.identified.isEmpty)
    }

    @Test("A card registers its placement with the configured params and returns the outcome")
    func registers() async {
        client.registerOutcome = .cancelled
        let outcome = await adapter().handle(CardTap(offerId: "winback_offer"))
        #expect(outcome == .cancelled)
        #expect(client.registered.map(\.placement) == ["winback offer"])
        #expect(client.registered.first?.params == ["source": "pingfront"])
    }

    @Test("A card's store offer is ignored: the Superwall paywall carries its own offers")
    func ignoresStoreOffer() async {
        let offer = StoreOffer(kind: .promotional, id: "save50", productId: "pro.annual")
        #expect(await adapter().handle(CardTap(offerId: "upgrade", storeOffer: offer)) == .purchased)
        #expect(client.registered.map(\.placement) == ["upgrade"])
    }

    @Test("An unknown placement, or Superwall not configured, is unavailable without registering")
    func unavailable() async {
        let adapter = adapter()
        #expect(await adapter.handle(CardTap(offerId: "nope")) == .unavailable)
        client.isConfigured = false
        #expect(await adapter.handle(CardTap(offerId: "upgrade")) == .unavailable)
        #expect(client.registered.isEmpty)
    }

    @Test("run stays idle when Superwall is never configured")
    func idle() async {
        client.isConfigured = false
        await adapter().run()
        #expect(host.offers.isEmpty && host.entitlements.isEmpty && client.statusReads == 0)
    }
}
