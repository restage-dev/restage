import 'dart:async';

import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/render_bundles/push_target.dart';
import 'package:test/test.dart';

void main() {
  test('naming nothing takes the caller default', () {
    final resolved = resolveBundlePushTarget(
      environment: null,
      personal: false,
      withKey: false,
    );
    expect(resolved.refusal, isNull);
    expect(resolved.target!.named, isFalse);
    expect(resolved.target!.environment, isNull);
    expect(resolved.target!.personal, isFalse);
  });

  test('a key with no target still takes the caller default', () {
    final resolved = resolveBundlePushTarget(
      environment: null,
      personal: false,
      withKey: true,
    );
    expect(resolved.refusal, isNull);
    expect(resolved.target!.named, isFalse);
  });

  test('an environment slug names an environment head', () {
    final resolved = resolveBundlePushTarget(
      environment: 'staging',
      personal: false,
      withKey: false,
    );
    expect(resolved.target!.environment, 'staging');
    expect(resolved.target!.personal, isFalse);
    expect(resolved.target!.named, isTrue);
  });

  test('a personal push names no environment', () {
    final resolved = resolveBundlePushTarget(
      environment: null,
      personal: true,
      withKey: false,
    );
    expect(resolved.target!.personal, isTrue);
    expect(resolved.target!.environment, isNull);
  });

  test('two targets at once is refused', () {
    final resolved = resolveBundlePushTarget(
      environment: 'staging',
      personal: true,
      withKey: false,
    );
    expect(resolved.target, isNull);
    expect(resolved.refusal!.message, contains('Name one target'));
  });

  test('a key has no personal head to push to', () {
    final resolved = resolveBundlePushTarget(
      environment: null,
      personal: true,
      withKey: true,
    );
    expect(resolved.target, isNull);
    expect(
      resolved.refusal!.message,
      contains('A key moves the head of the environment it is bound to'),
    );
  });

  test('a malformed environment is refused with its grammar', () {
    for (final slug in <String>[
      'Staging',
      'user',
      '-staging',
      'staging-',
      'staging/../admin',
      '',
    ]) {
      final resolved = resolveBundlePushTarget(
        environment: slug,
        personal: false,
        withKey: false,
      );
      expect(resolved.target, isNull, reason: slug);
      expect(resolved.refusal!.message, contains('Refusing the environment'));
    }
  });

  test('the target refusals name each caller\'s own form', () {
    String refusal({required bool withKey, SelectorSyntax? syntax}) => runZoned(
      () => resolveBundlePushTarget(
        environment: withKey ? null : 'staging',
        personal: true,
        withKey: withKey,
      ).refusal!.message,
      zoneValues: syntax == null ? null : selectorSyntaxZoneValues(syntax),
    );

    expect(
      refusal(withKey: false),
      contains(
        '`restage build push --env <slug>` for an environment head, or '
        '`restage build push --personal` for your own',
      ),
    );
    expect(
      refusal(withKey: true, syntax: SelectorSyntax.console),
      contains('sign in, then type `/restage build push --personal`.'),
    );
    expect(
      refusal(withKey: true, syntax: SelectorSyntax.mcp),
      contains('sign in, then call restage_push_build with personal: true.'),
    );
  });
}
