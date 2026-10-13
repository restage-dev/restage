import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('render bundle head', () {
    test('accepts environment slugs and bounded personal handles', () {
      const references = {
        'dev': RenderBundleHeadKind.environment,
        'staging': RenderBundleHeadKind.environment,
        'prod': RenderBundleHeadKind.environment,
        'user/a': RenderBundleHeadKind.personal,
        'user/alice': RenderBundleHeadKind.personal,
        'user/alice-smith': RenderBundleHeadKind.personal,
        'user/alice_smith': RenderBundleHeadKind.personal,
        'user/a1234567890123456789012345678901': RenderBundleHeadKind.personal,
      };
      for (final entry in references.entries) {
        expect(isValidRenderBundleHead(entry.key), isTrue, reason: entry.key);
        final head = parseRenderBundleHead(entry.key);
        expect(head.kind, entry.value, reason: entry.key);
        expect(head.text, entry.key, reason: entry.key);
      }
    });

    test('rejects every value outside the accepted set', () {
      for (final reference in [
        '',
        ' dev',
        'dev ',
        'Dev',
        'dev/',
        '-dev',
        'dev-',
        'user',
        'user/',
        'user//alice',
        'user/Alice',
        'user/-alice',
        'user/alice-',
        'user/alice/bob',
        'user/a12345678901234567890123456789012',
        'a1234567890123456789012345678901234',
      ]) {
        expect(
          isValidRenderBundleHead(reference),
          isFalse,
          reason: reference,
        );
        expect(
          () => parseRenderBundleHead(reference),
          throwsFormatException,
          reason: reference,
        );
      }
    });

    test('an environment can never shadow the personal prefix', () {
      expect(isValidRenderBundleEnvironmentSlug('user'), isFalse);
      expect(
        () => RenderBundleHead.environment('user'),
        throwsFormatException,
      );
    });

    test('the two kinds expose only their own label', () {
      final environment = parseRenderBundleHead('staging');
      expect(environment.environmentSlug, 'staging');
      expect(environment.handle, isNull);

      final personal = parseRenderBundleHead('user/alice');
      expect(personal.handle, 'alice');
      expect(personal.environmentSlug, isNull);
      expect(personal.label, 'alice');
    });

    test('equal references compare equal', () {
      expect(
        parseRenderBundleHead('user/alice'),
        RenderBundleHead.personal('alice'),
      );
      expect(
        parseRenderBundleHead('staging'),
        isNot(RenderBundleHead.personal('staging')),
      );
    });
  });

  group('handle from an address', () {
    test('reduces the local part to the handle grammar', () {
      expect(renderBundleHandleFromEmail('Alice.Smith@example.com'),
          'alice-smith');
      expect(renderBundleHandleFromEmail('alice+bundles@example.com'),
          'alice-bundles');
      expect(renderBundleHandleFromEmail('a_b-c@example.com'), 'a_b-c');
      expect(renderBundleHandleFromEmail('alice'), 'alice');
    });

    test('trims separators the reduction leaves at either end', () {
      expect(renderBundleHandleFromEmail('.alice.@example.com'), 'alice');
      expect(renderBundleHandleFromEmail('---alice---@example.com'), 'alice');
    });

    test('clips an over-long local part to a legal handle', () {
      final handle = renderBundleHandleFromEmail(
        '${'a' * 40}@example.com',
      );
      expect(handle, 'a' * renderBundleHandleMaxLength);
      expect(isValidRenderBundleHandle(handle!), isTrue);
    });

    test('answers null when nothing legal remains', () {
      expect(renderBundleHandleFromEmail('...@example.com'), isNull);
      expect(renderBundleHandleFromEmail('@example.com'), isNull);
      expect(renderBundleHandleFromEmail(''), isNull);
    });
  });
}
