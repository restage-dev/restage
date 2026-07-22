import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:test/test.dart';

void main() {
  test('omitted plane preserves a sole matching target', () async {
    final api = _TargetApi([_target(id: 12, plane: 'sandbox')]);

    final resolved = await resolveEnvironmentTargetContext(
      api: api,
      interactive: const NonInteractive(),
      stderr: StringBuffer(),
      projectSlug: 'alpha',
      appSlug: 'mobile',
      environmentSlug: 'production',
    );

    expect(resolved!.organizationId, 7);
    expect(resolved.appId, 5);
    expect(resolved.target.environmentTargetId, 12);
    expect(api.targetArgs!['appId'], 5);
    expect(api.targetArgs!.containsKey('runtimePlane'), isFalse);
  });

  test('omitted plane fails non-interactive ambiguity', () async {
    final api = _TargetApi([
      _target(id: 12, plane: 'sandbox'),
      _target(id: 13, plane: 'live'),
    ]);
    final stderr = StringBuffer();

    final resolved = await resolveEnvironmentTargetContext(
      api: api,
      interactive: const NonInteractive(),
      stderr: stderr,
      projectSlug: 'alpha',
      appSlug: 'mobile',
      environmentSlug: 'production',
    );

    expect(resolved, isNull);
    expect(stderr.toString(), contains('--plane <sandbox|live>'));
  });

  test('explicit plane is forwarded and selects one exact target', () async {
    final api = _TargetApi([_target(id: 13, plane: 'live')]);

    final resolved = await resolveEnvironmentTargetContext(
      api: api,
      interactive: const NonInteractive(),
      stderr: StringBuffer(),
      projectSlug: 'alpha',
      appSlug: 'mobile',
      environmentSlug: 'production',
      runtimePlane: RuntimePlane.live,
    );

    expect(resolved!.target.environmentTargetId, 13);
    expect(resolved.target.runtimePlane, RuntimePlane.live);
    expect(api.targetArgs!['runtimePlane'], 'live');
  });

  test('interactive ambiguity selects one exact target', () async {
    final api = _TargetApi([
      _target(id: 12, plane: 'sandbox'),
      _target(id: 13, plane: 'live'),
    ]);
    final interactive = RealInteractive(
      readLine: () async => '2',
      stdout: StringBuffer(),
      isInteractiveOverride: true,
    );

    final resolved = await resolveEnvironmentTargetContext(
      api: api,
      interactive: interactive,
      stderr: StringBuffer(),
      projectSlug: 'alpha',
      appSlug: 'mobile',
      environmentSlug: 'production',
    );

    expect(resolved!.target.environmentTargetId, 13);
    expect(resolved.target.runtimePlane, RuntimePlane.live);
    expect(api.targetArgs!.containsKey('runtimePlane'), isFalse);
  });

  test(
    'explicit selection preserves all six exact customer coordinates',
    () async {
      final coordinates = <({int id, int parentId, String slug, String plane})>[
        (id: 101, parentId: 11, slug: 'dev', plane: 'sandbox'),
        (id: 102, parentId: 11, slug: 'dev', plane: 'live'),
        (id: 103, parentId: 12, slug: 'staging', plane: 'sandbox'),
        (id: 104, parentId: 12, slug: 'staging', plane: 'live'),
        (id: 105, parentId: 13, slug: 'prod', plane: 'sandbox'),
        (id: 106, parentId: 13, slug: 'prod', plane: 'live'),
      ];

      for (final coordinate in coordinates) {
        final api = _TargetApi([
          _target(
            id: coordinate.id,
            parentId: coordinate.parentId,
            slug: coordinate.slug,
            plane: coordinate.plane,
          ),
        ]);
        final plane = RuntimePlane.fromWireName(coordinate.plane);

        final resolved = await resolveEnvironmentTargetContext(
          api: api,
          interactive: const NonInteractive(),
          stderr: StringBuffer(),
          projectSlug: 'alpha',
          appSlug: 'mobile',
          environmentSlug: coordinate.slug,
          runtimePlane: plane,
        );

        expect(resolved, isNotNull, reason: '$coordinate');
        expect(resolved!.target.environmentTargetId, coordinate.id);
        expect(resolved.target.namedEnvironmentId, coordinate.parentId);
        expect(resolved.target.environmentSlug, coordinate.slug);
        expect(resolved.target.runtimePlane, plane);
        expect(api.targetArgs!['appId'], 5);
        expect(api.targetArgs!['runtimePlane'], coordinate.plane);
      }
    },
  );
}

Map<String, dynamic> _target({
  required int id,
  required String plane,
  int parentId = 9,
  String slug = 'production',
}) => {
  'environmentTargetId': id,
  'namedEnvironmentId': parentId,
  'environmentSlug': slug,
  'runtimePlane': plane,
};

class _TargetApi implements RestageApi {
  _TargetApi(this.targets);

  final List<Map<String, dynamic>> targets;
  Map<String, dynamic>? targetArgs;

  @override
  Future<dynamic> call(
    String endpointName,
    String methodName,
    Map<String, dynamic> args,
  ) async {
    if (methodName == 'listMine') {
      return <dynamic>[
        {'organizationId': 7, 'slug': 'default', 'name': 'Default'},
      ];
    }
    if (methodName == 'listApps') {
      return <dynamic>[
        {'id': 5, 'slug': 'mobile', 'name': 'Mobile'},
      ];
    }
    if (methodName == 'listEnvironmentTargets') {
      targetArgs = args;
      return targets;
    }
    fail('Unexpected method $methodName');
  }

  @override
  void close() {}
}
