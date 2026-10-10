import 'dart:convert';

import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:test/test.dart';

void main() {
  group('decodeGenericTypedException', () {
    test('decodes ProjectNotFoundException', () {
      final body = jsonEncode({
        'className': 'ProjectNotFoundException',
        'data': {'__className__': 'ProjectNotFoundException', 'slug': 'demo'},
      });

      final decoded = decodeGenericTypedException(body);

      expect(decoded, isA<ProjectNotFound>());
      expect((decoded! as ProjectNotFound).projectSlug, 'demo');
    });

    test('decodes AppNotFoundException', () {
      final body = jsonEncode({
        'className': 'AppNotFoundException',
        'data': {
          '__className__': 'AppNotFoundException',
          'appSlug': 'mobile',
          'projectSlug': 'demo',
        },
      });

      final decoded = decodeGenericTypedException(body);

      expect(decoded, isA<AppNotFound>());
      final app = decoded! as AppNotFound;
      expect(app.appSlug, 'mobile');
      expect(app.projectSlug, 'demo');
    });

    test('decodes UnauthorizedException', () {
      final body = jsonEncode({
        'className': 'UnauthorizedException',
        'data': {
          '__className__': 'UnauthorizedException',
          'resource': 'project:demo',
        },
      });

      final decoded = decodeGenericTypedException(body);

      expect(decoded, isA<UnauthorizedAccess>());
      expect((decoded! as UnauthorizedAccess).resource, 'project:demo');
    });

    test('returns null for a paywall-specific className', () {
      final body = jsonEncode({
        'className': 'PaywallNotFoundException',
        'data': {
          '__className__': 'PaywallNotFoundException',
          'paywallSlug': 'missing',
        },
      });
      expect(decodeGenericTypedException(body), isNull);
    });

    test('returns null for an unknown className', () {
      final body = jsonEncode({
        'className': 'BananaException',
        'data': {'__className__': 'BananaException', 'foo': 'bar'},
      });
      expect(decodeGenericTypedException(body), isNull);
    });

    test('returns null for a non-JSON body', () {
      expect(decodeGenericTypedException('not json'), isNull);
    });

    test('returns null for a JSON body without className', () {
      expect(decodeGenericTypedException('{"foo":"bar"}'), isNull);
    });

    test('returns null for an empty body', () {
      expect(decodeGenericTypedException(''), isNull);
    });
  });

  group('exception toString', () {
    test('generic typed exceptions surface their identifying fields', () {
      expect(
        const ProjectNotFound(projectSlug: 'demo').toString(),
        contains('demo'),
      );
      expect(
        const AppNotFound(appSlug: 'mobile', projectSlug: 'demo').toString(),
        allOf(contains('mobile'), contains('demo')),
      );
      expect(
        const UnauthorizedAccess(resource: 'project:demo').toString(),
        contains('project:demo'),
      );
    });
  });

  test('a refused surface id decodes and renders its rule', () {
    const body =
        '{"className":"SurfaceSlugRejectedException",'
        '"data":{"slug":"WelcomeFlow","reason":"the rule"}}';
    final typed = decodeGenericTypedException(body);
    expect(typed, isA<SurfaceSlugRejected>());
    final outcome = renderGenericTypedError(
      const RestageApiException(400, body),
    );
    expect(outcome!.exitCode, 1);
    expect(outcome.message, contains('WelcomeFlow'));
    expect(outcome.message, contains('the rule'));
  });
}
