import PingFrontAdapterKit
public import PingFrontCore

/// A Superwall placement the team can send as an offer card.
public struct SuperwallPlacement: Sendable, Equatable {
    /// The placement name, as in the Superwall dashboard.
    ///
    /// It is also the slot id (characters outside `A-Z a-z 0-9 _ . -` become `_`).
    public var placement: String
    /// The title the team sees in the dashboard (at most 60 characters).
    public var title: String
    /// The kind of offer.
    public var kind: OfferSlot.Kind
    /// The products the paywall sells, shown on the slot.
    ///
    /// The slot is unavailable once the person owns all of them.
    public var products: [OfferSlot.Product]
    /// Parameters passed to `register(placement:params:)`, for audience filters.
    public var params: [String: String]

    /// Creates a placement.
    public init(
        _ placement: String, title: String, kind: OfferSlot.Kind = .standard, products: [OfferSlot.Product] = [],
        params: [String: String] = [:]
    ) {
        self.placement = placement
        self.title = title
        self.kind = kind
        self.products = products
        self.params = params
    }
}

/// How Superwall knows who the person is, so Superwall webhooks match them.
public enum SuperwallIdentity: Sendable, Equatable {
    /// Your app calls `Superwall.shared.identify(userId:)` with the id it passes to `PingFront.shared.identify`.
    case appManaged
    /// The adapter identifies Superwall with `PingFront.shared.storeAccountToken`, for apps without their own user
    /// ids. Superwall then also passes it as `appAccountToken`, so App Store notifications match too.
    case storeAccountToken
}

extension PingFrontModule {
    /// Superwall: each placement becomes an offer slot, an offer card registers its placement, and the subscription
    /// status becomes the person's entitlement.
    ///
    /// - Configure Superwall (`Superwall.configure`) before or right after pingfront; the adapter waits for it.
    /// - Slots are always reported as available, unless the person owns every listed product: SuperwallKit's
    ///   presentation-result check confirms experiment assignments and would use up holdouts, so the adapter never
    ///   calls it. Audiences and holdouts decide when the card is tapped; a skipped paywall is `.unavailable`.
    /// - Superwall paywalls carry their own offers, so a card's `StoreOffer` is ignored.
    /// - The adapter never purchases or finishes transactions (Superwall or your purchase controller does) and
    ///   reports no store events: the Superwall webhook delivers them.
    ///
    /// - Parameters:
    ///   - placements: The placements the team can offer.
    ///   - identity: Who identifies the person to Superwall.
    ///   - reportsEntitlement: Report Superwall's subscription status as the entitlement. Turn it off when another
    ///     module (RevenueCat, StoreKit) already reports it.
    /// - Returns: The module, for `config.use(_:)`.
    public static func superwall(
        placements: [SuperwallPlacement], identity: SuperwallIdentity = .appManaged, reportsEntitlement: Bool = true
    ) -> PingFrontModule {
        PingFrontModule(id: "pingfront.superwall") { context in
            #if canImport(SuperwallKit)
                let client: any SuperwallClient = SuperwallLive()
            #else
                let client: any SuperwallClient = NoSuperwall()
            #endif
            let adapter = SuperwallAdapter(
                client: client, host: ContextHost(context), placements: placements, identity: identity,
                reportsEntitlement: reportsEntitlement)
            context.setOfferHandler(adapter)
            context.run { await adapter.run() }
        }
    }
}
