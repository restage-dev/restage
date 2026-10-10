import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:test/test.dart';

void main() {
  test('target lists join exact app environment ids, not shared names', () {
    final scope = ProgrammaticScopeSnapshot({
      'organizationId': 7,
      'session': {
        'memberships': <Object>[],
        'workspaceExperiences': <Object>[],
      },
      'projects': [
        {'id': 1, 'slug': 'project', 'name': 'Project'},
      ],
      'apps': [
        {'id': 5, 'projectId': 1, 'slug': 'mobile', 'name': 'Mobile'},
        {'id': 6, 'projectId': 1, 'slug': 'tablet', 'name': 'Tablet'},
      ],
      'environments': [
        {'id': 12, 'appId': 5, 'namedEnvironmentId': 9, 'slug': 'production'},
        {'id': 13, 'appId': 6, 'namedEnvironmentId': 9, 'slug': 'production'},
      ],
      'environmentTargets': [
        {
          'environmentTargetId': 12,
          'namedEnvironmentId': 9,
          'environmentSlug': 'production',
          'runtimePlane': 'sandbox',
        },
        {
          'environmentTargetId': 13,
          'namedEnvironmentId': 9,
          'environmentSlug': 'production',
          'runtimePlane': 'live',
        },
      ],
      'surfaces': <Object>[],
    });

    expect(
      scope
          .targets(projectSlug: 'project', appSlug: 'mobile')
          .map((target) => target.environmentTargetId),
      [12],
    );
  });
}
