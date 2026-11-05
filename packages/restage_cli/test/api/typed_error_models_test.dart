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

    test('an unreachable organization is named by the MCP caller id', () {
      final body = jsonEncode({
        'className': 'OrganizationNotFoundException',
        'data': {
          '__className__': 'OrganizationNotFoundException',
          'organizationId': 99,
        },
      });
      expect(
        renderApiError(
          RestageApiException(400, body),
          syntax: SelectorSyntax.mcp,
        ).message,
        'No organization `99` is available to this account. Check '
        '`organizationId`, or sign in again with `restage_login`.',
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
      expect(
        cli.message,
        'The Restage backend returned an error (HTTP 500). Try again; if it '
        'keeps happening, report it.',
      );
      final mcp = renderApiError(error, syntax: SelectorSyntax.mcp);
      expect(mcp.exitCode, 2);
      expect(mcp.message, isNot(contains('boom')));
    });
  });

  test('a fit confirmation says why each build cannot show the version', () {
    // Every other failure kind: code, token, label, sentence.
    const others = [
      (
        'hostingMismatch',
        'hostingMismatch@single/inline;flow/inline',
        'flow',
        'This version is a flow, and this placement doesn\'t show flows. '
            'Try publishing it to a placement that does.',
      ),
      (
        'hostingMismatch',
        'hostingMismatch@flow/presented;flow/inline',
        'presented',
        'This version can be shown only on a route of its own, and this '
            "placement doesn't show it that way. Try publishing it to a "
            'placement that does.',
      ),
      (
        'missingHostField',
        'missingHostField:_h0123456789',
        'plan.name',
        "This version reads `plan.name`, which this build doesn't compute. "
            'Try removing `plan.name` from the version, or releasing an app '
            'build that computes it.',
      ),
      (
        'missingHostField',
        'missingHostField:userName',
        'userName',
        "This build doesn't pass `userName` to this placement. Try removing "
            "`userName` from the version, or passing it in the placement's "
            '`context` in a new app build.',
      ),
      (
        'missingWidget',
        'missingWidget:acme.ui:Badge',
        'acme.ui:Badge',
        "This build doesn't include the widget `acme.ui:Badge`. Try removing "
            'it from the version, or releasing an app build that includes it.',
      ),
      (
        'builtInFloor',
        'builtInFloor@3;2',
        null,
        "This build's built-in widgets are older than the version needs. Try "
            'releasing an app build made with a newer Restage SDK.',
      ),
      (
        'changedIsland',
        'changedIsland:app.islands:Badge@w0001',
        'Badge in PlanPicker',
        'This build changed the app code of `Badge in PlanPicker`. Try '
            'republishing the version to show it on this build.',
      ),
      (
        'somethingNew',
        'somethingNew',
        null,
        "This build can't show the version for a reason this `restage` CLI "
            "doesn't know. Try updating the `restage` CLI.",
      ),
    ];
    final body = jsonEncode({
      'className': 'SurfaceFitNeedsConfirmationException',
      'data': {
        '__className__': 'SurfaceFitNeedsConfirmationException',
        'verdict': 'someFit',
        'environment': 'production',
        'share': 0.5,
        'builds': {
          'items': [
            {
              'platform': 'ios',
              'appVersion': '2.3.0',
              'uploaded': false,
              'fits': true,
            },
            {
              'platform': 'ios',
              'appVersion': '2.2.0',
              'uploaded': false,
              'fits': false,
              'reasons': [
                {
                  'token': 'unproducedHostField:_hT',
                  'code': 'unproducedHostField',
                  'label': 'plan.name',
                  'build': 'PlanPicker.build',
                  'condition': 'offer != null',
                  'plain': "when there's an offer",
                  'location': 'lib/plans.dart:12:9',
                },
                {
                  'token': 'unproducedIsland:app.islands:Badge',
                  'code': 'unproducedIsland',
                  'label': 'Badge in PlanPicker',
                  'build': 'PlanPicker.build',
                  'condition': 'offer != null',
                  'plain': "when there's an offer",
                  'location': 'lib/plans.dart:12:9',
                },
                for (final (code, token, label, _) in others)
                  {'token': token, 'code': code, 'label': ?label},
              ],
            },
          ],
        },
      },
    });
    final reasons = [
      '    `plan.name` is shown where `PlanPicker.build` doesn\'t compute it. '
          'The build computes it only when `offer != null` '
          '(lib/plans.dart:12:9). Try showing it only in that case, or '
          'computing it before that `if`.',
      '    `Badge` is placed where `PlanPicker.build` doesn\'t create it. The '
          'build creates it only when `offer != null` (lib/plans.dart:12:9). '
          'Try placing it only in that case, or creating it before that '
          '`if`.',
      for (final (_, _, _, sentence) in others) '    $sentence',
    ];
    for (final (syntax, last) in [
      (SelectorSyntax.cli, 'Use --yes to go ahead.'),
      (SelectorSyntax.mcp, 'Call again with acceptFit: true to go ahead.'),
    ]) {
      expect(typedErrorSentence(body, syntax: syntax)!.split('\n'), [
        'Not every app version can show this.',
        '50% of users are on versions that can.',
        '  ios 2.2.0',
        ...reasons,
        last,
      ]);
    }
  });
}
