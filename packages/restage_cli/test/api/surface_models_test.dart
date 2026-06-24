import 'dart:convert';

import 'package:restage_cli/src/api/surface_models.dart';
import 'package:test/test.dart';

void main() {
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
  });
}
