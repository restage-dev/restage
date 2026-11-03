import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:meta/meta.dart';

import '../early/early_request.dart';

/// The platform's device facts and install identity, read once per process.
@internal
abstract final class NativeFacts {
  // Under `flutter test` there is no platform to ask, and a channel call would
  // wait on the test clock.
  static bool get _underFlutterTest {
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } on Object {
      return false;
    }
  }

  /// Whether a platform exists to ask; false under `flutter test`, where the
  /// callers skip the read without a turn of the event loop.
  static bool get available => !_underFlutterTest;

  /// Facts a test supplies in place of the platform's.
  @visibleForTesting
  static Map<String, Object?>? debugFacts;

  /// The pair a test's platform hands out after a reset.
  @visibleForTesting
  static ({String nonce, int createdAtMicros}) Function()?
      debugResetRegistration;

  static Future<Map<String, Object?>?>? _read;
  static ({String nonce, int createdAtMicros})? _registration;

  /// All facts the platform reported, or null where it has none.
  static Future<Map<String, Object?>?> read() => _read ??= debugFacts != null
      ? Future.value(debugFacts)
      : _underFlutterTest
          ? Future.value(null)
          : EarlyRequest.facts();

  /// One fact by name, or null.
  static Future<Object?> fact(String name) async => (await read())?[name];

  /// The install's registration identity from the platform, taken from the
  /// facts already read.
  static Future<({String nonce, int createdAtMicros})?> registration() async {
    if (_registration case final held?) return held;
    if (debugFacts == null && _underFlutterTest) return null;
    final facts = await read();
    final nonce = facts?['registrationNonce'];
    final created = facts?['registrationCreatedAtMicros'];
    if (nonce is String && created is int) {
      return _registration = (nonce: nonce, createdAtMicros: created);
    }
    return _registration = await EarlyRequest.registration();
  }

  /// A new registration identity from the platform, after a refusal.
  static Future<({String nonce, int createdAtMicros})?>
      resetRegistration() async {
    final reset = debugResetRegistration;
    if (reset != null) return _registration = reset();
    if (_underFlutterTest) return null;
    return _registration = await EarlyRequest.resetRegistration();
  }

  /// Forgets the read, as a new process would.
  static void reset() {
    _read = null;
    _registration = null;
  }
}
