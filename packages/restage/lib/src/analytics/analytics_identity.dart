import 'package:restage/src/billing/anonymous_token.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The SDK-owned four-level analytics identity.
///
/// - [anonymousId] — stable per install, resettable via [reset]; the
///   cross-session retention/cohort actor (pseudonymous, no IDFA/GAID join).
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

  /// `shared_preferences` key for the persisted pseudonymous id. Distinct from
  /// the billing anonymous-token key — this is the analytics cohort actor.
  static const _anonymousIdKey = 'restage.analytics.anonymous_id';

  final Future<SharedPreferences> Function() _prefsProvider;
  final String Function() _newId;

  int _generation = 0;
  String? _anonymousIdCache;
  int? _anonymousIdResolutionGeneration;
  Future<String>? _anonymousIdResolution;
  String? _sessionId;
  String? _userId;

  /// The current surface-presentation session id, or null when no surface is
  /// presented. Set by the surface host on mount, cleared on dismiss.
  String? surfaceSessionId;

  /// Returns the persisted pseudonymous id, minting + persisting one on first run.
  Future<String> anonymousId() {
    final cached = _anonymousIdCache;
    if (cached != null) return Future<String>.value(cached);

    final generation = _generation;
    final resolution = _anonymousIdResolution;
    if (resolution != null && _anonymousIdResolutionGeneration == generation) {
      return resolution;
    }

    late final Future<String> newResolution;
    newResolution = _resolveAnonymousId(generation).whenComplete(() {
      if (_anonymousIdResolutionGeneration == generation &&
          identical(_anonymousIdResolution, newResolution)) {
        _anonymousIdResolutionGeneration = null;
        _anonymousIdResolution = null;
      }
    });
    _anonymousIdResolutionGeneration = generation;
    _anonymousIdResolution = newResolution;
    return newResolution;
  }

  Future<String> _resolveAnonymousId(int generation) async {
    final prefs = await _prefsProvider();
    final persisted = prefs.getString(_anonymousIdKey);
    if (persisted != null && persisted.isNotEmpty) {
      if (_generation == generation) _anonymousIdCache = persisted;
      return persisted;
    }

    final fresh = _newId();
    if (_generation != generation) return fresh;

    await prefs.setString(_anonymousIdKey, fresh);
    if (_generation == generation) {
      _anonymousIdCache = fresh;
    } else {
      await _repairCurrentAnonymousIdPersistence();
    }
    return fresh;
  }

  Future<void> _repairCurrentAnonymousIdPersistence() async {
    while (true) {
      final generation = _generation;
      final current = _anonymousIdCache;
      if (current == null) return;

      final prefs = await _prefsProvider();
      if (_generation != generation || _anonymousIdCache != current) continue;

      await prefs.setString(_anonymousIdKey, current);
      if (_generation == generation && _anonymousIdCache == current) return;
    }
  }

  /// The resolved pseudonymous id if [anonymousId] has completed at least once,
  /// else null. Synchronous — for the hot event-fire path, which captures a
  /// snapshot without awaiting.
  String? get cachedAnonymousId => _anonymousIdCache;

  /// Monotonic actor generation for internal SDK race fences.
  int get generation => _generation;

  /// The current app-session id (minted lazily on first read).
  String get sessionId => _sessionId ??= _newId();

  /// Rotates the app-session id (a new launch / post-idle resume).
  void rotateSession() => _sessionId = _newId();

  /// The opt-in customer user id, or null.
  String? get userId => _userId;

  /// Attaches the customer's [userId] to subsequent events.
  void identify(String userId) => _userId = userId;

  /// Resets the pseudonymous actor immediately: mints a fresh [anonymousId],
  /// clears [userId] and the current surface presentation, and rotates the app
  /// session. Persistence completes asynchronously after the in-memory privacy
  /// boundary has taken effect.
  Future<void> reset() async {
    final generation = ++_generation;
    _anonymousIdResolutionGeneration = null;
    _anonymousIdResolution = null;
    final fresh = _newId();
    _anonymousIdCache = fresh;
    _userId = null;
    rotateSession();
    surfaceSessionId = null;

    final prefs = await _prefsProvider();
    if (_generation != generation) return;
    await prefs.setString(_anonymousIdKey, fresh);
    if (_generation != generation) {
      await _repairCurrentAnonymousIdPersistence();
    }
  }

  /// Mints a fresh per-event idempotency id (UUIDv4).
  String newEventId() => _newId();
}
