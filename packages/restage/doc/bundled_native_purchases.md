# Bundled native purchases

Call `Restage.configure` at app startup before showing store-backed paywalls.
The bundled native gateway requires a `baseUrl` so it can create a durable
purchase intent before opening store UI and report the transaction afterward.
It currently accepts auto-renewing subscriptions only.
Google Play prepaid base plans are not accepted.

For the bundled gateway, Restage listens for native store updates outside the
lifetime of a paywall. It reports an observed transaction before asking
StoreKit or Google Play to complete it. If the app exits first, StoreKit's
unfinished transactions or Google Play's owned-purchase query supplies the
evidence again when the app starts. Configure-owned StoreKit 1 promotional
offers fail closed rather than opening store UI without the required binding.

This durability boundary belongs only to the bundled gateway. Custom
receipt-bearing `BillingGateway` implementations and the RevenueCat adapter
retain ownership of their own receipt recovery and store-completion durability.
