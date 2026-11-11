import PingFrontAdapterKit
import PingFrontCore

/// `Superwall.shared.subscriptionStatus`, reduced to what pingfront's entitlement needs.
enum SWStatus: Sendable, Equatable {
    case unknown
    case inactive
    case active([AccessSnapshot])
}

/// The slice of SuperwallKit the adapter uses.
///
/// The live client wraps `Superwall.shared`.
///
/// There is deliberately no presentation-result check: in SuperwallKit 4.18 `getPresentationResult(forPlacement:)`
/// confirms the experiment assignment, holdouts included, so calling it to report slots would use up holdouts.
@MainActor protocol SuperwallClient: AnyObject {
    /// `Superwall.isInitialized`.
    var isConfigured: Bool { get }
    /// The subscription status now.
    func status() -> SWStatus
    /// Yields when the status may have changed (customer info changed, the app became active).
    func changes() -> AsyncStream<Void>
    /// `Superwall.shared.identify(userId:)`.
    func identify(userId: String)
    /// `Superwall.shared.register(placement:params:handler:)`, waiting for the paywall to close or be skipped.
    func register(placement: String, params: [String: String]) async -> OfferOutcome
}

/// Stands in where SuperwallKit does not build (macOS): never configured.
@MainActor final class NoSuperwall: SuperwallClient {
    var isConfigured: Bool { false }
    func status() -> SWStatus { .unknown }
    func changes() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func identify(userId: String) {}
    func register(placement: String, params: [String: String]) async -> OfferOutcome { .unavailable }
}
