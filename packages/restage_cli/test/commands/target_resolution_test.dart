import 'dart:convert';

import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  test('selectors go to the server as given', () async {
    final api = _TargetApi([_target(id: 12, plane: 'sandbox')]);

    final resolved = await resolveTargetInteractively(
      api: api,
      interactive: const NonInteractive(),
      projectSlug: 'alpha',
      appSlug: 'mobile',
      environmentSlug: 'production',
      organizationSlug: 'restage',
    );

    expect(api.methods, ['resolveTarget']);
    expect(api.args.single['organizationSlug'], 'restage');
    expect(api.args.single.containsKey('runtimePlane'), isFalse);
    expect(resolved.organizationId, 7);
    expect(resolved.appId, 5);
    expect(resolved.target.environmentTargetId, 12);
    expect(resolved.planeIsImplicit, isTrue);
  });

  test('a non-interactive ambiguity is the typed refusal', () async {
    final api = _TargetApi([
      _target(id: 12, plane: 'sandbox'),
      _target(id: 13, plane: 'live'),
    ]);

    await expectLater(
      resolveTargetInteractively(
        api: api,
        interactive: const NonInteractive(),
        projectSlug: 'alpha',
        appSlug: 'mobile',
        environmentSlug: 'production',
      ),
      throwsA(
        isA<RestageApiException>().having(
          (error) => renderApiError(error).message,
          'message',
          contains('--plane <sandbox|live>'),
        ),
      ),
    );
  });

  test('an explicit plane is forwarded and repeated in hints', () async {
    final api = _TargetApi([_target(id: 13, plane: 'live')]);

    final resolved = await resolveTargetInteractively(
      api: api,
      interactive: const NonInteractive(),
      projectSlug: 'alpha',
      appSlug: 'mobile',
      environmentSlug: 'production',
      runtimePlane: RuntimePlane.live,
    );

    expect(api.args.single['runtimePlane'], 'live');
    expect(resolved.target.runtimePlane, RuntimePlane.live);
    expect(resolved.planeIsImplicit, isFalse);
  });

  test('an interactive ambiguity asks among the candidates', () async {
    final api = _TargetApi([
      _target(id: 12, plane: 'sandbox'),
      _target(id: 13, plane: 'live'),
    ]);
    final interactive = RealInteractive(
      readLine: () async => '2',
      stdout: StringBuffer(),
      isInteractiveOverride: true,
    );

    final resolved = await resolveTargetInteractively(
      api: api,
      interactive: interactive,
      projectSlug: 'alpha',
      appSlug: 'mobile',
      environmentSlug: 'production',
    );

    expect(api.methods, ['resolveTarget', 'resolveTarget']);
    expect(api.args.last['runtimePlane'], 'live');
    expect(api.args.last['environmentTargetId'], 13);
    expect(resolved.target.environmentTargetId, 13);
    expect(resolved.planeIsImplicit, isFalse);
  });
}

Map<String, dynamic> _target({required int id, required String plane}) => {
  'environmentTargetId': id,
  'namedEnvironmentId': 9,
  'environmentSlug': 'production',
  'runtimePlane': plane,
};

class _TargetApi implements RestageApi {
  _TargetApi(this.targets);

  final List<Map<String, dynamic>> targets;
  final methods = <String>[];
  final args = <Map<String, dynamic>>[];

  @override
  Uri get endpoint => Uri.parse('http://localhost/');

  @override
  Credential? get credential => null;

  @override
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async {
    methods.add(methodName);
    this.args.add(args);
    if (methodName != 'resolveTarget') fail('Unexpected method $methodName');
    final response = resolveTargetResponse(args, targets: targets);
    if (response.statusCode != 200) {
      throw RestageApiException(response.statusCode, response.body);
    }
    return jsonDecode(response.body);
  }

  @override
  void close() {}
}
