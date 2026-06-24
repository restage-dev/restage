import 'dart:convert';

import 'package:restage_cli/src/api/paywall_models.dart';
import 'package:test/test.dart';

void main() {
  group('PaywallSummary.fromJson', () {
    test('decodes the canonical wire shape', () {
      const payload = {
        '__className__': 'PaywallSummary',
        'slug': 'hello',
        'name': 'Hello',
        'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
        'publishedVersionByEnvironment': {'dev': 3, 'staging': 2, 'prod': null},
      };

      final summary = PaywallSummary.fromJson(payload);

      expect(summary.slug, 'hello');
      expect(summary.name, 'Hello');
      expect(
        summary.draftUpdatedAt.toUtc().toIso8601String(),
        '2026-05-01T12:34:56.000Z',
      );
      expect(summary.publishedVersionByEnvironment, {
        'dev': 3,
        'staging': 2,
        'prod': null,
      });
    });

    test('tolerates an absent publishedVersionByEnvironment as empty', () {
      const payload = {
        'slug': 'hello',
        'name': 'Hello',
        'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
      };

      final summary = PaywallSummary.fromJson(payload);

      expect(summary.publishedVersionByEnvironment, isEmpty);
    });

    test('toJson round-trips through fromJson', () {
      final original = PaywallSummary(
        slug: 'p',
        name: 'P',
        draftUpdatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        publishedVersionByEnvironment: const {'dev': 1, 'prod': null},
      );

      final encoded = jsonEncode(original.toJson());
      final round = PaywallSummary.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(round.slug, original.slug);
      expect(round.name, original.name);
      expect(round.draftUpdatedAt, original.draftUpdatedAt);
      expect(
        round.publishedVersionByEnvironment,
        original.publishedVersionByEnvironment,
      );
    });
  });

  group('decodeTypedException', () {
    test('decodes PublishConflictException', () {
      final body = jsonEncode({
        'className': 'PublishConflictException',
        'data': {
          '__className__': 'PublishConflictException',
          'paywallSlug': 'hello',
          'environmentSlug': 'dev',
        },
      });

      final decoded = decodeTypedException(body);

      expect(decoded, isA<PublishConflict>());
      final conflict = decoded! as PublishConflict;
      expect(conflict.paywallSlug, 'hello');
      expect(conflict.environmentSlug, 'dev');
    });

    test('decodes PaywallNotFoundException', () {
      final body = jsonEncode({
        'className': 'PaywallNotFoundException',
        'data': {
          '__className__': 'PaywallNotFoundException',
          'paywallSlug': 'missing',
        },
      });

      final decoded = decodeTypedException(body);

      expect(decoded, isA<PaywallNotFound>());
      expect((decoded! as PaywallNotFound).paywallSlug, 'missing');
    });

    test('decodes EnvironmentNotFoundException', () {
      final body = jsonEncode({
        'className': 'EnvironmentNotFoundException',
        'data': {
          '__className__': 'EnvironmentNotFoundException',
          'environmentSlug': 'qa',
        },
      });

      final decoded = decodeTypedException(body);

      expect(decoded, isA<EnvironmentNotFound>());
      expect((decoded! as EnvironmentNotFound).environmentSlug, 'qa');
    });

    test('returns null for an unknown className', () {
      final body = jsonEncode({
        'className': 'BananaException',
        'data': {'__className__': 'BananaException', 'foo': 'bar'},
      });
      expect(decodeTypedException(body), isNull);
    });

    test('returns null for a non-JSON body', () {
      expect(decodeTypedException('not json'), isNull);
    });

    test('returns null for a JSON body without className', () {
      expect(decodeTypedException('{"foo":"bar"}'), isNull);
    });

    test('returns null for an empty body', () {
      expect(decodeTypedException(''), isNull);
    });
  });

  group('exception toString', () {
    test('PublishConflict surfaces both fields', () {
      const conflict = PublishConflict(
        paywallSlug: 'hello',
        environmentSlug: 'dev',
      );
      expect(conflict.toString(), contains('hello'));
      expect(conflict.toString(), contains('dev'));
    });
  });
}
