# pingfront for Superwall

The Superwall adapter for the [pingfront iOS SDK](https://github.com/pingfront/pingfront-ios). The Superwall
placements you list become offer slots your team can send as offer cards, and a card registers the placement. It is
its own Swift package, so an app that adds it fetches Superwall and nothing from the other vendors.

The adapter:

- reports your paywalls as offer slots, so your team can send them as offer cards;
- opens the Superwall paywall when the person taps an offer card;
- reports the Superwall entitlement as the person's entitlement;
- links the person to Superwall so its webhooks match them on pingfront's server.

It leaves transactions to Superwall (it never finishes one) and reports no store events: Superwall's webhook
delivers purchases, renewals and lapses.

## Install

In Xcode, choose File > Add Package Dependencies, enter `https://github.com/pingfront/pingfront-ios-superwall`, and add the
**PingFrontSuperwall** product to your app target. In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/pingfront/pingfront-ios-superwall", from: "1.0.0"),
],
// and in your target:
dependencies: [.product(name: "PingFrontSuperwall", package: "pingfront-ios-superwall")]
```

It brings in the pingfront SDK (`pingfront-ios`), the shared adapter kit (`pingfront-ios-adapter-kit`) and
Superwall's `Superwall-iOS` (SuperwallKit), 4.18.3 or later in major 4. iOS 17 or later, Swift 6.

## Set up

```swift
import PingFrontSuperwall
Superwall.configure(apiKey: "pk_…")
PingFront.configure("pk_live_…") { $0.use(.superwall(placements: [SuperwallPlacement("winback_offer", title: "Come back for 50% off")])) }
```

Configure Superwall before or right after `PingFront.configure`. The adapter waits up to a minute for it, then
stays idle and logs why.

## How it works

- **Offer slots:** one per placement you list, with its title, kind and products. A slot is unavailable once the
  person owns every product you listed for it.
- **Availability is not checked with Superwall:** in SuperwallKit 4.18, `getPresentationResult(forPlacement:)`
  confirms the experiment assignment, holdouts included. Calling it to report slots would use up holdouts, so the
  adapter never calls it. Audiences and holdouts decide when the card is tapped.
- **Offer cards:** `Superwall.shared.register(placement:params:)`. The outcome is:
  - `purchased` after a purchase;
  - `cancelled` when the person closes the paywall or restores;
  - `unavailable` when Superwall skips it (holdout, no audience match, unknown placement);
  - `failed` on an error.
- **Store offers:** ignored. Superwall paywalls carry their own offers.
- **Entitlement:** `Superwall.shared.subscriptionStatus`, refreshed when customer info changes and when the app
  becomes active; `source: superwall`. Pass `reportsEntitlement: false` when RevenueCat or StoreKit already
  reports it.
- **Identity:**
  - by default your app calls `Superwall.shared.identify(userId:)` with the id it passes to
    `PingFront.shared.identify`. The server matches Superwall's `appUserId` against a verified user id or a store
    account token.
  - `identity: .storeAccountToken` (for apps without their own user ids) identifies Superwall with the store
    account token. Superwall then also passes it as `appAccountToken`, so App Store notifications match too.

## Reference

The public API. Everything else is internal.

| Symbol | What it is |
| --- | --- |
| `PingFrontModule.superwall(placements:identity:reportsEntitlement:)` | The adapter. Module id `pingfront.superwall`. |
| `SuperwallPlacement` | A placement the team can offer: `placement`, `title`, `kind`, `products`, `params`. |
| `SuperwallPlacement.init(_:title:kind:products:params:)` | Creates a placement. |
| `SuperwallIdentity.appManaged` | Your app identifies Superwall (default). |
| `SuperwallIdentity.storeAccountToken` | The adapter identifies Superwall with the store account token. |

## More

- [Modules and vendor adapters](https://pingfront.sh/docs/modules#revenuecat-superwall-and-adapty) in the pingfront docs.
- Connect Superwall's webhook too: [Store events](https://pingfront.sh/docs/store-events).
- [CHANGELOG.md](CHANGELOG.md). MIT licensed (see `LICENSE`).
