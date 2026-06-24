/// Wire "enums" for the analytics event contract.
///
/// These are modelled as **unknown-preserving strings**, not Dart `enum`s, on
/// purpose: the contract is frozen and forward-compatible, so a value added in
/// a later SDK / surface must never break an older reader (SDK, the
/// event-stream schema, or an analytics-warehouse column). Each type below is a
/// namespace of canonical string constants plus a `known` set used only for
/// soft validation — an unrecognised value is always *preserved*, never
/// rejected.
library;

/// The surface that emitted an event. Wire string, unknown-preserving.
///
/// `null` on the wire denotes an app-wide / server event (no surface).
abstract final class AnalyticsSurface {
  AnalyticsSurface._();

  /// Paywall surface (the default).
  static const String paywall = 'paywall';

  /// Onboarding flow surface.
  static const String onboarding = 'onboarding';

  /// In-app message surface.
  static const String message = 'message';

  /// Survey surface.
  static const String survey = 'survey';

  /// App-wide source (lifecycle/entitlement events fired with no surface).
  static const String app = 'app';

  /// Billing/subscription-lifecycle source (server webhook path).
  static const String billing = 'billing';

  /// The recognised surface vocabulary. Membership is advisory — decoders
  /// preserve any string (forward-compat).
  static const Set<String> known = <String>{
    paywall,
    onboarding,
    message,
    survey,
    app,
    billing,
  };

  /// Whether [value] is a recognised surface. A `false` result is not an error.
  static bool isKnown(String value) => known.contains(value);
}

/// Who produced an event. **Server-stamped** — never read from a client
/// envelope. A public-key ingest path stamps [client]; only an internal /
/// secret-key path may stamp [server].
abstract final class AnalyticsSource {
  AnalyticsSource._();

  /// Emitted by the SDK in a customer app (public-key ingest).
  static const String client = 'client';

  /// Emitted server-side (subscription lifecycle, secret-key path).
  static const String server = 'server';

  /// The source vocabulary.
  static const Set<String> known = <String>{client, server};

  /// Whether [value] is a recognised source.
  static bool isKnown(String value) => known.contains(value);
}

/// Sampling tier. **Server-derived** from the taxonomy registry — never read
/// from a client envelope (a client must not force `tier1` past sampling).
abstract final class AnalyticsTier {
  AnalyticsTier._();

  /// Keep-all lifecycle/conversion/error events.
  static const String tier1 = 'tier1';

  /// Coalesced per-session summary events.
  static const String tier2 = 'tier2';

  /// The tier vocabulary.
  static const Set<String> known = <String>{tier1, tier2};

  /// Whether [value] is a recognised tier.
  static bool isKnown(String value) => known.contains(value);
}

/// Reporting platform carried in `AnalyticsAppContext`. Wire string,
/// unknown-preserving — the `known` set is informational.
abstract final class AnalyticsPlatform {
  AnalyticsPlatform._();

  /// iOS.
  static const String ios = 'ios';

  /// Android.
  static const String android = 'android';

  /// macOS.
  static const String macos = 'macos';

  /// Web.
  static const String web = 'web';

  /// Windows.
  static const String windows = 'windows';

  /// Linux.
  static const String linux = 'linux';

  /// The common platform vocabulary. Advisory — any string is preserved.
  static const Set<String> known = <String>{
    ios,
    android,
    macos,
    web,
    windows,
    linux,
  };

  /// Whether [value] is a recognised platform.
  static bool isKnown(String value) => known.contains(value);
}
