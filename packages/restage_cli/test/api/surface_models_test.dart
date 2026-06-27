import 'dart:convert';

import 'package:restage_cli/src/api/surface_models.dart';
import 'package:test/test.dart';

void main() {
  group('SurfaceStatusResult', () {
    test('fromJson decodes status + versions', () {
      final result = SurfaceStatusResult.fromJson({
        'surfaceType': 'paywall',
        'surfaceSlug': 'pro',
        'environmentSlug': 'production',
        'liveVersion': 2,
        'locked': false,
        'deliveryShape': 'blob',
        'versions': [
          {
            'version': 2,
            'publishedAt': '2026-06-25T00:00:00.000Z',
            'contentHash': 'abc',
            'isActive': true,
          },
          {
            'version': 1,
            'publishedAt': '2026-06-24T00:00:00.000Z',
            'contentHash': 'def',
            'isActive': false,
          },
        ],
        '__className__': 'SurfaceStatusView',
      });
      expect(result.liveVersion, 2);
      expect(result.locked, isFalse);
      expect(result.supportsRollback, isTrue);
      expect(result.versions, hasLength(2));
      expect(result.versions.first.isActive, isTrue);
    });

    test('supportsRollback is false for a flow surface', () {
      final result = SurfaceStatusResult.fromJson({
        'surfaceType': 'onboarding',
        'surfaceSlug': 'welcome',
        'environmentSlug': 'production',
        'liveVersion': null,
        'locked': true,
        'deliveryShape': 'flow',
        'versions': <dynamic>[],
      });
      expect(result.supportsRollback, isFalse);
      expect(result.liveVersion, isNull);
    });
  });

  group('decodeSurfaceTypedException', () {
    test('decodes SurfaceNotFoundException', () {
      final body = jsonEncode({
        'className': 'SurfaceNotFoundException',
        'data': {
          '__className__': 'SurfaceNotFoundException',
          'surfaceSlug': 'first_run',
        },
      });

      final decoded = decodeSurfaceTypedException(body);

      expect(decoded, isA<SurfaceNotFound>());
      expect((decoded! as SurfaceNotFound).surfaceSlug, 'first_run');
    });

    test('decodes SurfacePublishConflictException', () {
      final body = jsonEncode({
        'className': 'SurfacePublishConflictException',
        'data': {
          '__className__': 'SurfacePublishConflictException',
          'surfaceSlug': 'first_run',
          'environmentSlug': 'dev',
        },
      });

      final decoded = decodeSurfaceTypedException(body);

      expect(decoded, isA<SurfacePublishConflict>());
      final conflict = decoded! as SurfacePublishConflict;
      expect(conflict.surfaceSlug, 'first_run');
      expect(conflict.environmentSlug, 'dev');
    });

    test('decodes EnvironmentNotFoundException', () {
      final body = jsonEncode({
        'className': 'EnvironmentNotFoundException',
        'data': {
          '__className__': 'EnvironmentNotFoundException',
          'environmentSlug': 'qa',
        },
      });

      final decoded = decodeSurfaceTypedException(body);

      expect(decoded, isA<SurfaceEnvironmentNotFound>());
      expect((decoded! as SurfaceEnvironmentNotFound).environmentSlug, 'qa');
    });

    test('decodes SurfaceRollbackUnsupportedException', () {
      final body = jsonEncode({
        'className': 'SurfaceRollbackUnsupportedException',
        'data': {
          '__className__': 'SurfaceRollbackUnsupportedException',
          'surfaceSlug': 'welcome',
        },
      });
      final decoded = decodeSurfaceTypedException(body);
      expect(decoded, isA<SurfaceRollbackUnsupported>());
      expect((decoded! as SurfaceRollbackUnsupported).surfaceSlug, 'welcome');
    });

    test('decodes SurfaceVersionNotFoundException', () {
      // Wire key is 'version', not 'toVersion' — mirrors the real backend body.
      final body = jsonEncode({
        'className': 'SurfaceVersionNotFoundException',
        'data': {
          '__className__': 'SurfaceVersionNotFoundException',
          'surfaceSlug': 'pro',
          'environmentSlug': 'production',
          'version': 5,
        },
      });
      final decoded = decodeSurfaceTypedException(body);
      expect(decoded, isA<SurfaceVersionNotFound>());
      final e = decoded! as SurfaceVersionNotFound;
      expect(e.surfaceSlug, 'pro');
      expect(e.toVersion, 5); // CLI field is toVersion; wire field is version
    });

    test('SurfaceVersionNotFoundException with missing fields returns null '
        '(defensive)', () {
      // Missing 'version' field — decoder must return null, not throw.
      final body = jsonEncode({
        'className': 'SurfaceVersionNotFoundException',
        'data': {
          '__className__': 'SurfaceVersionNotFoundException',
          'surfaceSlug': 'pro',
          // 'version' intentionally absent
        },
      });
      expect(decodeSurfaceTypedException(body), isNull);
    });

    test('returns null for a paywall className (does not overload)', () {
      final body = jsonEncode({
        'className': 'PaywallNotFoundException',
        'data': {
          '__className__': 'PaywallNotFoundException',
          'paywallSlug': 'missing',
        },
      });
      expect(decodeSurfaceTypedException(body), isNull);
    });

    test('returns null for an unknown className', () {
      final body = jsonEncode({
        'className': 'BananaException',
        'data': {'__className__': 'BananaException', 'foo': 'bar'},
      });
      expect(decodeSurfaceTypedException(body), isNull);
    });

    test('returns null for a non-JSON body', () {
      expect(decodeSurfaceTypedException('not json'), isNull);
    });

    test('returns null for a JSON body without className', () {
      expect(decodeSurfaceTypedException('{"foo":"bar"}'), isNull);
    });

    test('returns null for an empty body', () {
      expect(decodeSurfaceTypedException(''), isNull);
    });
  });

  group('exception toString', () {
    test('SurfaceNotFound surfaces the slug', () {
      const e = SurfaceNotFound(surfaceSlug: 'first_run');
      expect(e.toString(), contains('first_run'));
    });

    test('SurfacePublishConflict surfaces both fields', () {
      const e = SurfacePublishConflict(
        surfaceSlug: 'first_run',
        environmentSlug: 'dev',
      );
      expect(e.toString(), contains('first_run'));
      expect(e.toString(), contains('dev'));
    });

    test('SurfaceEnvironmentNotFound surfaces the slug', () {
      const e = SurfaceEnvironmentNotFound(environmentSlug: 'qa');
      expect(e.toString(), contains('qa'));
    });

    test('SurfaceRollbackUnsupported surfaces the slug', () {
      const e = SurfaceRollbackUnsupported(surfaceSlug: 'welcome');
      expect(e.toString(), contains('welcome'));
    });

    test('SurfaceVersionNotFound surfaces slug + version', () {
      const e = SurfaceVersionNotFound(surfaceSlug: 'pro', toVersion: 5);
      expect(e.toString(), contains('pro'));
      expect(e.toString(), contains('5'));
    });
  });
}
