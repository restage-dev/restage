import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/render_bundle_coverage_sentence.dart';
import 'package:test/test.dart';

void main() {
  RenderBundleHeadDiscovery head(Map<String, int> libraries) =>
      RenderBundleHeadDiscovery(
        head: 'staging',
        version: 12,
        libraries: libraries,
        updatedAt: DateTime.utc(2030),
      );

  String? sentence({
    required Map<String, int> required,
    RenderBundleHeadDiscovery? head,
    int surfaces = 1,
  }) => renderBundleCoverageSentence(
    required: required,
    headVersion: head?.version,
    registered: head?.libraries ?? const {},
    surfaceCount: surfaces,
    app: 'mobile',
    environment: 'staging',
  );

  test('a surface built from the catalog alone says nothing', () {
    expect(sentence(required: const {}), isNull);
    expect(sentence(required: const {}, head: head(const {})), isNull);
  });

  test('a covered surface says nothing', () {
    expect(
      sentence(
        required: const {'acme.widgets': 2},
        head: head(const {'acme.widgets': 2, 'acme.charts': 1}),
      ),
      isNull,
    );
  });

  test('with no build for the environment the push says so', () {
    expect(
      sentence(required: const {'acme.widgets': 1}),
      'This surface uses widgets from your app (acme.widgets). The dashboard '
      'has no build of mobile for staging yet, so it cannot display them; '
      'run `restage build push --env staging`.',
    );
  });

  test('a build that lacks a library is named with its version', () {
    expect(
      sentence(
        required: const {'acme.widgets': 1, 'acme.charts': 1},
        head: head(const {'acme.widgets': 1}),
        surfaces: 2,
      ),
      'These surfaces use widgets from your app (acme.charts, acme.widgets), '
      "and the dashboard's build of mobile for staging (version 12) does not "
      'include acme.charts; run `restage build push --env staging`.',
    );
  });

  test('a build older than the widgets need is named as older', () {
    expect(
      sentence(
        required: const {'acme.widgets': 3},
        head: head(const {'acme.widgets': 2}),
      ),
      'This surface uses widgets from your app (acme.widgets), and the '
      "dashboard's build of mobile for staging (version 12) is older than "
      'they need; run `restage build push --env staging`.',
    );
  });
}
