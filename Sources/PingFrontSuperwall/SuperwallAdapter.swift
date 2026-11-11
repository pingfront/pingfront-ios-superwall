import Foundation
import PingFrontAdapterKit
import PingFrontCore
import os

/// Reports the configured placements as offer slots and Superwall's subscription status as the entitlement, and
/// registers the placement when an offer card is tapped.
@MainActor final class SuperwallAdapter: OfferHandling {
    private let client: any SuperwallClient
    private let host: any AdapterHost
    private let placements: [SuperwallPlacement]
    private let identity: SuperwallIdentity
    private let reportsEntitlement: Bool
    private let sleep: Sleep
    private let log = AdapterLog.logger("superwall")
    let slots: SlotPublisher
    /// The user id last passed to `identify`, if the adapter identifies.
    private(set) var identifiedAs: String?

    init(
        client: any SuperwallClient, host: any AdapterHost, placements: [SuperwallPlacement], identity: SuperwallIdentity,
        reportsEntitlement: Bool, sleep: @escaping Sleep = liveSleep
    ) {
        self.client = client
        self.host = host
        self.placements = placements
        self.identity = identity
        self.reportsEntitlement = reportsEntitlement
        self.sleep = sleep
        slots = SlotPublisher(host: host, source: .superwall)
    }

    /// Runs until cancelled: waits for `Superwall.configure`, then follows the token and the subscription status.
    func run() async {
        guard await Readiness.wait(until: { [client] in client.isConfigured }, sleep: sleep) else {
            log.error("Superwall is not configured, so the adapter is idle. Call Superwall.configure before PingFront.configure.")
            return
        }
        async let tokens: Void = watchTokens()
        refresh()
        for await _ in client.changes() { refresh() }
        await tokens
    }

    private func watchTokens() async {
        for await token in host.storeAccountTokenChanges() { tokenChanged(token) }
    }

    func tokenChanged(_ token: UUID?) {
        guard let token else { return }
        if identity == .storeAccountToken {
            let userId = tokenString(token)
            if userId != identifiedAs {
                client.identify(userId: userId)
                identifiedAs = userId
            }
        }
        refresh(force: true)
    }

    /// Reports the entitlement and the slots' availability from the current status.
    func refresh(force: Bool = false) {
        let status = client.status()
        if reportsEntitlement, let entitlement = Self.entitlement(status) { host.setEntitlement(entitlement) }
        slots.publish(makeSlots(owned: Self.owned(status)), force: force)
    }

    func makeSlots(owned: Set<String>) -> [OfferSlot] {
        placements.map { placement in
            OfferSlot(
                id: SlotRules.id(placement.placement), title: SlotRules.title(placement.title, fallback: placement.placement),
                kind: placement.kind, isAvailable: SlotRules.isAvailable(products: placement.products.map(\.id), owned: owned),
                products: placement.products.map { SlotRules.product(id: $0.id, price: $0.price, period: $0.period, trial: $0.trial) })
        }
    }

    func handle(_ request: OfferRequest) async -> OfferOutcome { await handle(CardTap(request)) }

    func handle(_ card: CardTap) async -> OfferOutcome {
        guard client.isConfigured else {
            log.error("Offer card not shown: Superwall is not configured.")
            return .unavailable
        }
        guard let placement = placements.first(where: { SlotRules.id($0.placement) == card.offerId }) else {
            log.error("Offer card not shown: no configured placement matches \(card.offerId, privacy: .public).")
            return .unavailable
        }
        // The paywall carries its own offers: `card.storeOffer` is not redeemed here.
        let outcome = await client.register(placement: placement.placement, params: placement.params)
        refresh()
        return outcome
    }

    /// `nil` while Superwall does not know yet.
    static func entitlement(_ status: SWStatus) -> Entitlement? {
        switch status {
        case .unknown: nil
        case .inactive: Entitlement(state: .none, source: .superwall)
        case .active(let access): EntitlementRules.entitlement(from: access, source: .superwall)
        }
    }

    static func owned(_ status: SWStatus) -> Set<String> {
        guard case .active(let access) = status else { return [] }
        return Set(access.filter(\.isActive).compactMap(\.productId))
    }
}
