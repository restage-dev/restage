import 'package:restage/src/billing/anonymous_token.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The SDK-owned four-level analytics identity.
///
/// - [anonymousId] — stable per install, resettable via [reset]; the
///   cross-session retention/cohort actor (anonymous, no IDFA/GAID join).
/// - [sessionId] — per app-session, rotated on [rotateSession] (a new launch /
///   idle window).
/// - [surfaceSessionId] — per surface presentation (mount→dismiss); set by the
///   surface host.
/// - [userId] — opt-in, set via [identify], cleared on [reset].
///
/// Persistence mirrors the SDK's existing anonymous-token store: best-effort
/// `shared_preferences`, re-minted on uninstall. The [prefsProvider] and [newId]
/// seams are injected by tests.
class AnalyticsIdentity {
  /// Creates an identity. [prefsProvider] defaults to
  /// [SharedPreferences.getInstance]; [newId] defaults to a UUIDv4 generator.
  AnalyticsIdentity({
    Future<SharedPreferences> Function()? prefsProvider,
    String Function()? newId,
  })  : _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
        _newId = newId ?? AnonymousTokenStore.generateUuidV4;

  /// `shared_preferences` key for the persisted anonymous id. Distinct from the
  /// billing anonymous-token key — this is the analytics cohort actor.
  static const _anonymousIdKey = 'restage.analytics.anonymous_id';

  final Future<SharedPreferences> Function() _prefsProvider;
  final String Function() _newId;

  String? _anonymousIdCache;
  String? _sessionId;
  String? _userId;

  /// The current surface-presentation session id, or null when no surface is
  /// presented. Set by the surface host on mount, cleared on dismiss.
  String? surfaceSessionId;

  /// Returns the persisted anonymous id, minting + persisting one on first run.
  Future<String> anonymousId() async {
    final cached = _anonymousIdCache;
    if (cached != null) return cached;
    final prefs = await _prefsProvider();
    final persisted = prefs.getString(_anonymousIdKey);
    if (persisted != null && persisted.isNotEmpty) {
      _anonymousIdCache = persisted;
      return persisted;
    }
    return _mintAnonymousId(prefs);
  }

  Future<String> _mintAnonymousId(SharedPreferences prefs) async {
    final fresh = _newId();
    await prefs.setString(_anonymousIdKey, fresh);
    _anonymousIdCache = fresh;
    return fresh;
  }

  /// The resolved anonymous id if [anonymousId] has completed at least once,
  /// else null. Synchronous — for the hot event-fire path, which captures a
  /// snapshot without awaiting.
  String? get cachedAnonymousId => _anonymousIdCache;

  /// The current app-session id (minted lazily on first read).
  String get sessionId => _sessionId ??= _newId();

  /// Rotates the app-session id (a new launch / post-idle resume).
  void rotateSession() => _sessionId = _newId();

  /// The opt-in customer user id, or null.
  String? get userId => _userId;

  /// Attaches the customer's [userId] to subsequent events.
  void identify(String userId) => _userId = userId;

  /// Resets the anonymous actor: mints a fresh [anonymousId], clears [userId],
  /// and rotates the session — the privacy "forget me" primitive.
  Future<void> reset() async {
    final prefs = await _prefsProvider();
    await _mintAnonymousId(prefs);
    _userId = null;
    rotateSession();
  }

  /// Mints a fresh per-event idempotency id (UUIDv4).
  String newEventId() => _newId();
}
