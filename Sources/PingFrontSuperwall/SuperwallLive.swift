#if canImport(SuperwallKit)
    import Foundation
    import PingFrontAdapterKit
    import PingFrontCore
    import SuperwallKit

    /// The live Superwall client (iOS).
    @MainActor final class SuperwallLive: SuperwallClient {
        var isConfigured: Bool { Superwall.isInitialized }

        func status() -> SWStatus {
            switch Superwall.shared.subscriptionStatus {
            case .unknown: .unknown
            case .inactive: .inactive
            case .active(let entitlements): .active(entitlements.map(Self.access))
            }
        }

        func changes() -> AsyncStream<Void> {
            AsyncStream { continuation in
                // Owned by the stream: cancelled when the adapter stops iterating.
                let info = Task { @MainActor in
                    for await _ in Superwall.shared.customerInfoStream { continuation.yield() }
                }
                let active = Task { @MainActor in
                    for await _ in AppSignals.becameActive() { continuation.yield() }
                }
                continuation.onTermination = { _ in
                    info.cancel()
                    active.cancel()
                }
            }
        }

        func identify(userId: String) { Superwall.shared.identify(userId: userId) }

        func register(placement: String, params: [String: String]) async -> OfferOutcome {
            await withCheckedContinuation { continuation in
                let once = ResumeOnce(continuation)
                let handler = PaywallPresentationHandler()
                let dismissed: @Sendable (PaywallInfo, PaywallResult) -> Void = { info, result in
                    // Closed only to show the next paywall: wait for that one.
                    guard info.closeReason != .forNextPaywall else { return }
                    once.resume(Self.outcome(result))
                }
                let skipped: @Sendable (PaywallSkippedReason) -> Void = { _ in once.resume(.unavailable) }
                let failed: @Sendable (any Error) -> Void = { _ in once.resume(.failed(.store)) }
                handler.onDismiss(dismissed)
                handler.onSkip(skipped)
                handler.onError(failed)
                Superwall.shared.register(placement: placement, params: params, handler: handler)
            }
        }

        /// A restore bought nothing, so it counts as closing the paywall.
        nonisolated static func outcome(_ result: PaywallResult) -> OfferOutcome {
            switch result {
            case .purchased: .purchased
            case .declined, .restored: .cancelled
            }
        }

        nonisolated static func access(_ entitlement: SuperwallKit.Entitlement) -> AccessSnapshot {
            AccessSnapshot(
                productId: entitlement.latestProductId, isActive: entitlement.isActive, isLifetime: entitlement.isLifetime ?? false,
                isTrial: entitlement.offerType == .trial, willRenew: entitlement.willRenew ?? true,
                isInGracePeriod: entitlement.state == .inGracePeriod, hasBillingIssue: entitlement.state == .inBillingRetryPeriod,
                expiresAt: entitlement.expiresAt)
        }
    }
#endif
