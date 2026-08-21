import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Permanent fence over the app-global recording controls removed in the
/// coordinated breaking release.
///
/// These symbols were removed from the public surface, not renamed and not
/// aliased. Re-adding one — even as a deprecated forwarder — must be a
/// deliberate, reviewed act rather than something that slips back in while
/// restoring a call site, so it fails here first.
///
/// The check is source-level because absence is not observable through the
/// type system: a deleted static method is simply not there to assert on.
/// Every negative is paired with a positive control over the same file, so a
/// path typo or an unreadable file fails loudly instead of passing vacuously.
void main() {
  late final String runtimeSource;
  late final String barrelSource;

  setUpAll(() {
    runtimeSource = File('lib/src/runtime/restage.dart').readAsStringSync();
    barrelSource = File('lib/restage.dart').readAsStringSync();
  });

  const removedDeclarations = <String, String>{
    'sdkVersion': 'static const String sdkVersion',
    'identify': 'static void identify(',
    'track': 'static void track(',
    'beginSurfaceSession': 'static void beginSurfaceSession()',
    'endSurfaceSession': 'static void endSurfaceSession()',
  };

  group('removed app-global recording controls stay removed', () {
    for (final entry in removedDeclarations.entries) {
      test('Restage.${entry.key} is not declared', () {
        expect(
          runtimeSource.contains(entry.value),
          isFalse,
          reason: 'Restage.${entry.key} was removed in the breaking release. '
              'Re-introducing it changes the published surface and needs an '
              'explicit decision, not a silent restore.',
        );
      });
    }

    test('none of them are named by the public barrel', () {
      for (final name in removedDeclarations.keys) {
        expect(
          barrelSource.contains(name),
          isFalse,
          reason: '$name reappeared in the public barrel.',
        );
      }
    });
  });

  group('positive controls', () {
    test('the retained facade is still declared', () {
      // If these fail, the fence above is reading the wrong file and its
      // negatives prove nothing.
      for (final retained in <String>[
        'abstract final class Restage',
        'static void reset()',
        'static Stream<RestageEvent> get events',
        'static void fireEvent(RestageEvent event)',
        'bool analyticsEnabled = true',
      ]) {
        expect(
          runtimeSource.contains(retained),
          isTrue,
          reason: 'Expected the runtime source to still declare: $retained',
        );
      }
    });

    test('the public barrel is still the real barrel', () {
      expect(
          barrelSource.contains("export 'src/runtime/restage.dart'"), isTrue);
    });
  });

  test('reset is not documented as a forget-me primitive', () {
    // It never was one: it is local, tells the server nothing, and erases
    // nothing already uploaded. The old wording invited a host to answer a
    // deletion request by calling it, so the phrasing is fenced rather than
    // left to be reintroduced by someone shortening the doc comment.
    expect(
      runtimeSource.toLowerCase().contains('forget me'),
      isFalse,
      reason: 'reset() must not be described as a "forget me" primitive.',
    );
    // Positive control: the corrected limits are still stated.
    expect(
      runtimeSource.contains('does **not** erase'),
      isTrue,
      reason: 'Expected reset() to still document what it does not do.',
    );
  });

  test('firing an event does not call the recording bridge directly', () {
    // The host event stream and the recording path are separate concerns: the
    // recording runtime registers a sink for itself. Collapsing them back into
    // a hard call re-couples a retained public surface to a runtime that is
    // scheduled for replacement.
    expect(runtimeSource.contains('_bridgeEventToAnalytics(event);'), isFalse);
    expect(
      runtimeSource.contains('_recordingSink = _bridgeEventToAnalytics;'),
      isTrue,
    );
    expect(runtimeSource.contains('_recordingSink?.call(event);'), isTrue);
  });
}
