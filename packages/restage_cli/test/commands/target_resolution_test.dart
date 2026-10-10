import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

void main() {
  test('selectors resolve from one admitted scope read', () async {
    final api = _TargetApi([_target(id: 12, plane: 'sandbox')]);
    final resolved = await resolveTargetInteractively(
      api: api,
      interactive: const NonInteractive(),
      projectSlug: 'alpha',
      appSlug: 'mobile',
      environmentSlug: 'production',
      organizationSlug: 'restage',
      organizationId: 7,
    );
    expect(api.methods, ['read']);
    expect(api.args.single, {'organizationId': 7});
    expect(resolved.organizationId, 7);
    expect(resolved.appId, 5);
    expect(resolved.target.environmentTargetId, 12);
    expect(resolved.planeIsImplicit, isTrue);
  });

  test('a non-interactive ambiguity refuses without another read', () async {
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
        isA<TargetSelectionException>().having(
          (error) => error.message,
          'message',
          contains('--plane <sandbox|live>'),
        ),
      ),
    );
    expect(api.methods, ['read']);
  });

  test('an explicit plane selects the same scope target', () async {
    final api = _TargetApi([
      _target(id: 12, plane: 'sandbox'),
      _target(id: 13, plane: 'live'),
    ]);
    final resolved = await resolveTargetInteractively(
      api: api,
      interactive: const NonInteractive(),
      projectSlug: 'alpha',
      appSlug: 'mobile',
      environmentSlug: 'production',
      runtimePlane: RuntimePlane.live,
    );
    expect(api.methods, ['read']);
    expect(resolved.target.runtimePlane, RuntimePlane.live);
    expect(resolved.planeIsImplicit, isFalse);
  });

  test(
    'interactive ambiguity asks among targets in the same snapshot',
    () async {
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
      expect(api.methods, ['read']);
      expect(resolved.target.environmentTargetId, 13);
      expect(resolved.planeIsImplicit, isFalse);
    },
  );
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
    expect(endpointName, 'scope');
    expect(methodName, 'read');
    methods.add(methodName);
    this.args.add(args);
    return {
      'organizationId': 7,
      'session': {
        'memberships': [
          {
            'organizationId': 7,
            'slug': 'restage',
            'name': 'Restage',
            'role': 'admin',
          },
        ],
        'workspaceExperiences': <Object>[],
      },
      'projects': [
        {'id': 1, 'slug': 'alpha', 'name': 'Alpha'},
      ],
      'apps': [
        {'id': 5, 'projectId': 1, 'slug': 'mobile', 'name': 'Mobile'},
      ],
      'environments': [
        for (final target in targets)
          {
            'id': target['environmentTargetId'],
            'appId': 5,
            'namedEnvironmentId': 9,
            'slug': 'production',
          },
      ],
      'environmentTargets': targets,
      'surfaces': <Object>[],
    };
  }

  @override
  void close() {}
}
