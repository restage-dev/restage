import 'dart:convert';

import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
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
          'reason': 'paidPlanRequired',
        },
      });

      final decoded = decodeGenericTypedException(body);

      expect(decoded, isA<UnauthorizedAccess>());
      final unauthorized = decoded! as UnauthorizedAccess;
      expect(unauthorized.resource, 'project:demo');
      expect(unauthorized.reason, UnauthorizedReason.paidPlanRequired);
    });

    test('a Custom-plan refusal names the route to Custom', () {
      final body = jsonEncode({
        'className': 'UnauthorizedException',
        'data': {
          '__className__': 'UnauthorizedException',
          'resource': 'custom-plan:organization:1',
          'reason': 'customPlanRequired',
        },
      });

      final decoded = decodeGenericTypedException(body)! as UnauthorizedAccess;

      expect(decoded.reason, UnauthorizedReason.customPlanRequired);
      expect(
        unauthorizedSentence(decoded.reason),
        'SSO comes with the Custom plan. Talk to us about Custom: '
        'contact@restage.dev',
      );
    });

    test('an UnauthorizedException without a reason is a missing role', () {
      final body = jsonEncode({
        'className': 'UnauthorizedException',
        'data': {'resource': 'project:demo'},
      });

      final decoded = decodeGenericTypedException(body)! as UnauthorizedAccess;

      expect(decoded.reason, UnauthorizedReason.roleMissing);
      expect(
        renderApiError(RestageApiException(403, body)).message,
        contains('Your role in this organization'),
      );
    });

    test('decodes TargetSelectionRefusedException with its candidates', () {
      final body = jsonEncode({
        'className': 'TargetSelectionRefusedException',
        'data': {
          '__className__': 'TargetSelectionRefusedException',
          'reason': 'environmentOnBothPlanes',
          'environmentSlug': 'production',
          'candidates': {
            'items': [
              {
                'environmentTargetId': 12,
                'namedEnvironmentId': 9,
                'environmentSlug': 'production',
                'runtimePlane': 'sandbox',
              },
            ],
          },
        },
      });

      final decoded =
          decodeGenericTypedException(body)! as TargetSelectionRefused;

      expect(decoded.reason, TargetSelectionRefusal.environmentOnBothPlanes);
      expect(decoded.environmentSlug, 'production');
      expect(decoded.candidates.single.environmentTargetId, 12);
      expect(
        renderApiError(
          RestageApiException(400, body),
          syntax: SelectorSyntax.mcp,
        ).message,
        contains('runtimePlane: sandbox or live'),
      );
    });

    test('returns null for a retired className', () {
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
    final outcome = renderApiError(const RestageApiException(400, body));
    expect(outcome.exitCode, 1);
    expect(outcome.message, contains('WelcomeFlow'));
    expect(outcome.message, contains('the rule'));
  });

  group('renderApiError', () {
    test('a typed surface refusal reads as its sentence', () {
      const body =
          '{"className":"SurfaceNotFoundException",'
          '"data":{"surfaceSlug":"welcome"}}';
      final outcome = renderApiError(const RestageApiException(404, body));
      expect(outcome.exitCode, 1);
      expect(outcome.message, "Surface 'welcome' not found.");
    });

    test('an untyped 401 reads as a stale credential for each syntax', () {
      const error = RestageApiException(401, 'nope');
      expect(renderApiError(error).message, contains('restage login'));
      expect(
        renderApiError(error, syntax: SelectorSyntax.mcp).message,
        contains('restage_login'),
      );
    });

    test('anything else is an HTTP failure with exit 2', () {
      const error = RestageApiException(500, 'boom');
      final cli = renderApiError(error);
      expect(cli.exitCode, 2);
      expect(cli.message, 'Could not contact the backend: HTTP 500 — boom');
      final mcp = renderApiError(error, syntax: SelectorSyntax.mcp);
      expect(mcp.exitCode, 2);
      expect(mcp.message, isNot(contains('boom')));
    });
  });
}
