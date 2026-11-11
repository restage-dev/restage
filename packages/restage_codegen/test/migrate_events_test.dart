import 'dart:io';

import 'package:restage_codegen/src/migrate_events.dart';
import 'package:test/test.dart';

const _fixtures = 'test/fixtures/migrate_events';

String _read(String name) => File('$_fixtures/$name').readAsStringSync();

void main() {
  for (final name in [
    'surface',
    'paywall',
    'state',
    'refused',
    'shapes',
    'shadowed',
  ]) {
    test('$name migrates to its golden, and again changes nothing', () {
      final expected = _read('$name.expect');
      expect(migrateEvents(_read('$name.input')).source, expected);
      final again = migrateEvents(expected);
      expect(again.changed, isFalse);
      expect(again.source, expected);
    });
  }

  test('a paywall event becomes a constant on its class', () {
    final result = migrateEvents(_read('paywall.input'));
    expect(result.rewritten, 4);
    expect(result.declared, [
      'Offer.closeEvent',
      'Offer.continueEvent',
      'Offer.restorePurchases',
    ]);
    expect(result.refusals, isEmpty);
  });

  test('a call with no context, name or class refuses with the fix', () {
    final result = migrateEvents(_read('refused.input'));
    expect(result.changed, isFalse);
    final messages = [
      for (final refusal in result.refusals)
        '${refusal.line}:${refusal.column}: ${refusal.message}',
    ];
    expect(messages, hasLength(3));
    expect(
      messages[0],
      '6:26: `surfaceEvent(...)` is called where no BuildContext is in '
      'scope. Try passing the BuildContext of the widget that builds '
      'the button into this code and calling `context.surfaceEvent(...)` '
      'on it.',
    );
    expect(
      messages[1],
      "9:27: `paywallEvent('orphan')` is called outside a class, so the "
      'migration has nowhere to declare the event. Try declaring '
      "`static const myEvent = SurfaceEvent<void>('orphan');` on the "
      'surface class and calling '
      '`context.surfaceEvent(Surface.myEvent)`.',
    );
    expect(
      messages[2],
      '18:29: `paywallEvent` names its event with something other than a '
      "string literal, so the migration can't declare it. Try declaring "
      "`static const myEvent = SurfaceEvent<void>('my_event');` and "
      'calling `context.surfaceEvent(myEvent)`.',
    );
  });

  test("names what it can't rewrite and where a route context goes", () {
    final result = migrateEvents(_read('shapes.input'));
    expect(result.declared, [
      'Offer.continueEvent',
      'Quiet.hush',
      'Bare.bare',
    ]);
    expect(
      [for (final r in result.refusals) r.message],
      [
        startsWith('`paywallEvent(...)` is in the static method `badge`'),
        startsWith(
          '`surfaceEvent(...)` is inside a builder whose context '
          'parameter is `_`',
        ),
      ],
    );
    expect(
      [for (final n in result.notes) n.message],
      [
        startsWith(
          '`route.surfaceEvent(...)` uses the context of a route '
          'builder.',
        ),
      ],
    );
  });

  test("a function of the app's own with a helper's name stays", () {
    expect(migrateEvents(_read('shadowed.input')).changed, isFalse);
  });

  test('a library that does not import restage is left alone', () {
    const source = 'void f() => surfaceEvent(1);\n';
    final result = migrateEvents(source);
    expect(result.changed, isFalse);
    expect(result.refusals, isEmpty);
    expect(result.source, source);
  });

  test('the command prints each file and the review note', () async {
    final dir = Directory.systemTemp.createTempSync('migrate_events_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/offer.dart').writeAsStringSync(_read('paywall.input'));
    File('${dir.path}/plans.dart').writeAsStringSync(_read('refused.input'));

    final first = await Process.run('dart', [
      'run',
      'bin/migrate_events.dart',
      dir.path,
    ]);
    expect(first.exitCode, 1, reason: '${first.stderr}');
    final out = '${first.stdout}';
    expect(
      out,
      contains(
        '${dir.path}/offer.dart: rewrote 4 calls, declared Offer.closeEvent, '
        'Offer.continueEvent, Offer.restorePurchases',
      ),
    );
    expect(out, contains('${dir.path}/plans.dart:6:26: '));
    expect(out, contains('Migrated 1 file; 3 calls left to change by hand.'));
    expect(out, contains('review each event and decide which it is.'));
    expect(
      File('${dir.path}/offer.dart').readAsStringSync(),
      _read('paywall.expect'),
    );

    File('${dir.path}/plans.dart').deleteSync();
    final second = await Process.run('dart', [
      'run',
      'bin/migrate_events.dart',
      dir.path,
    ]);
    expect(second.exitCode, 0, reason: '${second.stderr}');
    expect('${second.stdout}'.trim(), 'Nothing to migrate.');
  });
}
