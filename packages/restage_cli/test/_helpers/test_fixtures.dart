import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw_formats;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Encode a small, ordinary, uninstrumented RFW library for publish tests.
Uint8List ordinaryRfwBlob() => rfw_formats.encodeLibraryBlob(
  rfw_formats.parseLibraryFile('''
import restage.core;
widget Preview = Text(text: "ordinary");
'''),
);

/// Write a stub credential to [store]. Used by command tests that need
/// the CLI to behave as signed-in.
Future<void> seedCredential(
  FileCredentialStore store, {
  String endpoint = 'http://localhost:8080/',
  String authToken = 'kid:secret',
}) async {
  await store.write(
    Credential(
      endpoint: endpoint,
      kind: CredentialKind.authKey,
      authToken: authToken,
    ),
  );
}

/// Write a `restage_config.yaml` to [dir]. [defaultEnvironment] is
/// omitted when null.
Future<void> seedRestageConfig(
  Directory dir,
  String project,
  String app, {
  String? defaultEnvironment,
  String? organization,
  String? endpoint,
  String? dashboardOrigin,
  String? renderBundleOrigin,
}) async {
  final buffer = StringBuffer()
    ..writeln('project: $project')
    ..writeln('app: $app');
  if (defaultEnvironment != null) {
    buffer.writeln('defaultEnvironment: $defaultEnvironment');
  }
  if (organization != null) {
    buffer.writeln('organization: $organization');
  }
  if (endpoint != null) {
    buffer.writeln('endpoint: $endpoint');
  }
  if (dashboardOrigin != null) {
    buffer.writeln('dashboardOrigin: $dashboardOrigin');
  }
  if (renderBundleOrigin != null) {
    buffer.writeln('renderBundleOrigin: $renderBundleOrigin');
  }
  await File(
    p.join(dir.path, 'restage_config.yaml'),
  ).writeAsString(buffer.toString());
}

/// Write [bytes] to `<dir>/assets/paywalls/<name>.rfw`, plus the capability
/// manifest sidecar the codegen emits alongside it (so the publish path's
/// derived-floor read resolves). [minClient] is the derived built-in floor the
/// sidecar records (default a non-baseline value so a test asserting it proves
/// the floor came from the sidecar, not a hardcoded default).
Future<void> seedRfw(
  Directory dir,
  String name,
  List<int> bytes, {
  int minClient = 2,
  List<LibraryRequirement> requiredLibraries = const [],
}) async {
  final target = File(p.join(dir.path, 'assets', 'paywalls', '$name.rfw'));
  await target.parent.create(recursive: true);
  await target.writeAsBytes(bytes);
  await seedCapabilitySidecar(
    target.path,
    minClient: minClient,
    requiredLibraries: requiredLibraries,
  );
}

/// Write the capability sidecar (`<stem>.capability.json`) next to the compiled
/// blob at [rfwPath] — mirrors what the codegen emits: the derived built-in
/// floor + required libraries plus the blob's content hash. The blob must
/// already exist at [rfwPath] (the hash is computed from it). Pass
/// [blobSha256Override] to write a deliberately-wrong hash (the stale-sidecar
/// case).
Future<void> seedCapabilitySidecar(
  String rfwPath, {
  int minClient = 2,
  List<LibraryRequirement> requiredLibraries = const [],
  String? blobSha256Override,
}) async {
  final blob = await File(rfwPath).readAsBytes();
  final sidecar = File(
    p.join(
      p.dirname(rfwPath),
      '${p.basenameWithoutExtension(rfwPath)}.capability.json',
    ),
  );
  await sidecar.writeAsString(
    jsonEncode(
      CapabilitySidecar(
        blobSha256: blobSha256Override ?? CapabilitySidecar.hashBlob(blob),
        manifest: CapabilityManifest(
          builtInFloor: minClient,
          requiredLibraries: requiredLibraries,
        ),
      ).toJson(),
    ),
  );
}

/// The checkout this test is running inside, found by walking up from the
/// current working directory (the package dir under `dart test`) to the
/// nearest `.git`.
///
/// The walk STOPS there, and that bound is the point of this function. An
/// earlier version searched for a fixture directory instead and simply kept
/// walking when it was missing — so in a git worktree it climbed out of the
/// checkout entirely and found the fixture in whatever other checkout happened
/// to sit above it. Tests then passed locally against a tree that was not the
/// tree under test, and failed in CI, which has only one checkout and no
/// neighbour to borrow from. A fixture this can no longer reach must fail
/// loudly rather than resolve somewhere else.
///
/// `.git` is a directory in a clone and a file in a worktree; both count.
Directory locateCheckoutRoot() {
  var dir = Directory.current;
  while (true) {
    final marker = p.join(dir.path, '.git');
    if (Directory(marker).existsSync() || File(marker).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not locate the checkout root (no .git) above '
        '${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// Directory holding the example app's committed surface bundles, inside THIS
/// checkout.
Directory locateExampleBundles() {
  final root = locateCheckoutRoot();
  final bundles = Directory(
    p.join(
      root.path,
      'apps',
      'examples',
      'assets',
      'restage',
      'bundles',
      'lib',
    ),
  );
  if (!bundles.existsSync()) {
    throw StateError(
      'Example bundles are missing from this checkout: ${bundles.path}',
    );
  }
  return bundles;
}

/// Write every entry of the bundle at [bundlePath] into [root], each at its
/// own logical delivery path, and return them by logical path.
///
/// The bundle is the tracked artifact, so its bytes are the same bytes the
/// generator emitted — which is what makes the content hashes inside a flow
/// document agree with the screen blobs seeded beside it.
Future<Map<String, Uint8List>> _unpackBundle(
  Directory root,
  String bundlePath,
) async {
  final bundle = RestageBundleCodec.decode(
    await File(bundlePath).readAsBytes(),
  );
  final written = <String, Uint8List>{};
  for (final entry in bundle.entries) {
    final destination = File(p.join(root.path, entry.logicalPath));
    await destination.parent.create(recursive: true);
    final bytes = entry.bytes;
    await destination.writeAsBytes(bytes);
    written[entry.logicalPath] = bytes;
  }
  return written;
}

/// Copy the real `first_run` flow document and its referenced screen blobs
/// into [dir] under the codegen on-disk layout
/// (`assets/<type>/flows/<slug>.flow.json` + `assets/<type>/screens/*.rfw`).
///
/// Returns the resolved flow JSON path. The blobs are the real committed
/// artifacts, so their SHA-256 content hashes match the flow document — a
/// faithful payload assembles without a stale-blob error. Each screen's
/// capability sidecar is copied alongside its blob, since the flow assembler
/// reads them to union the flow's required libraries.
///
/// Read from the tracked `.rsbundle`s rather than a loose asset tree: the
/// bundles ARE the shipped artifact, and a loose mirror of them is a second
/// copy that can rot or, as happened here, be deleted while the tests that
/// depend on it keep passing against another checkout.
Future<String> seedSurfaceFlow(
  Directory dir, {
  String type = 'onboarding',
  String slug = 'first_run',
}) async {
  final bundles = locateExampleBundles();
  final flowsDst = Directory(p.join(dir.path, 'assets', type, 'flows'));
  final screensDst = Directory(p.join(dir.path, 'assets', type, 'screens'));
  await flowsDst.create(recursive: true);
  await screensDst.create(recursive: true);

  final flowEntries = await _unpackBundle(
    dir,
    p.join(bundles.path, type, 'flows', 'first_run.rsbundle'),
  );
  final flowJson = utf8.decode(
    flowEntries['assets/$type/flows/first_run.flow.json']!,
  );
  final flowPath = p.join(flowsDst.path, '$slug.flow.json');
  await File(flowPath).writeAsString(flowJson);

  final doc = FlowDocumentCodec.decodeJson(flowJson);
  for (final artifact in doc.screenArtifacts.values) {
    await _unpackBundle(
      dir,
      p.join(
        bundles.path,
        type,
        'screens',
        '${p.basenameWithoutExtension(artifact.path)}.rsbundle',
      ),
    );
  }
  return flowPath;
}

// seedPaywallFlow and seedPaywallBlob lived here and are gone. Both read the
// same deleted loose asset tree as the old seed above, both had no callers,
// and neither could have run — so they were not dormant helpers waiting to be
// useful, they were two more ways to resolve a fixture outside this checkout.
// The paywall bundles they wanted are tracked
// (apps/examples/assets/restage/bundles/lib/paywalls/), so rebuilding either
// on top of _unpackBundle is small if a test ever needs one.

/// Build an [http.Client] that returns the same response for every
/// request, computed by [handler]. Useful when the test only cares
/// about a single round-trip.
///
/// Target-aware commands perform two read-only discovery calls before their
/// operation. The shared default keeps pre-target command fixtures focused on
/// the operation they exercise; discovery-specific tests opt out.
http.Client mockHttpClient(
  http.Response Function(http.Request request) handler, {
  bool withDefaultTargetDiscovery = true,
}) => MockClient((request) async {
  if (withDefaultTargetDiscovery) {
    final discovery = _defaultTargetDiscoveryResponse(request);
    if (discovery != null) return discovery;
  }
  return handler(request);
});

/// One scripted response per HTTP call. The Nth request to the
/// [http.Client] returns the response produced by `steps[N]`. Asserts
/// (via `test`'s `fail`) on overrun, so tests catch unexpected backend
/// chatter.
typedef ScriptStep = http.Response Function(http.Request request);

/// Script step for the exact-App discovery now required before target lookup.
http.Response activeAppDiscoveryResponse(
  http.Request request, {
  int appId = 5,
  String appSlug = 'mobile',
  String? projectSlug,
}) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(body['method'], 'listApps');
  if (projectSlug != null) expect(body['projectSlug'], projectSlug);
  return http.Response(
    jsonEncode([
      {'id': appId, 'slug': appSlug, 'name': appSlug},
    ]),
    200,
  );
}

/// Build an [http.Client] that drives [steps] one response per operation call.
/// Target discovery is supplied by default and does not consume a step.
http.Client scriptedHttpClient(
  List<ScriptStep> steps, {
  bool withDefaultTargetDiscovery = true,
}) {
  var index = 0;
  return MockClient((request) async {
    if (withDefaultTargetDiscovery) {
      final discovery = _defaultTargetDiscoveryResponse(request);
      if (discovery != null) return discovery;
    }
    if (index >= steps.length) {
      fail('Unexpected backend call ${index + 1}: ${request.url}');
    }
    final step = steps[index];
    final response = step(request);
    index++;
    return response;
  });
}

http.Response? _defaultTargetDiscoveryResponse(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  switch (body['method']) {
    case 'listMine':
      return http.Response(
        jsonEncode([
          {'organizationId': 7, 'slug': 'restage', 'name': 'Restage'},
        ]),
        200,
      );
    case 'listApps':
      return http.Response(
        jsonEncode([
          {'id': 5, 'slug': 'mobile', 'name': 'Mobile'},
          {'id': 8, 'slug': 'a', 'name': 'A'},
          {'id': 9, 'slug': 'default', 'name': 'Default'},
          {'id': 6, 'slug': 'config-app', 'name': 'Config App'},
          {'id': 7, 'slug': 'flag-app', 'name': 'Flag App'},
        ]),
        200,
      );
    case 'listEnvironmentTargets':
      final allTargets = <Map<String, dynamic>>[
        {
          'environmentTargetId': 11,
          'namedEnvironmentId': 21,
          'environmentSlug': 'dev',
          'runtimePlane': 'sandbox',
        },
        {
          'environmentTargetId': 12,
          'namedEnvironmentId': 22,
          'environmentSlug': 'staging',
          'runtimePlane': 'sandbox',
        },
        {
          'environmentTargetId': 13,
          'namedEnvironmentId': 23,
          'environmentSlug': 'production',
          'runtimePlane': 'live',
        },
      ];
      final plane = body['runtimePlane'] as String?;
      return http.Response(
        jsonEncode([
          for (final target in allTargets)
            if (plane == null || target['runtimePlane'] == plane) target,
        ]),
        200,
      );
  }
  return null;
}
