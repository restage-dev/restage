import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
}) async {
  final buffer = StringBuffer()
    ..writeln('project: $project')
    ..writeln('app: $app');
  if (defaultEnvironment != null) {
    buffer.writeln('defaultEnvironment: $defaultEnvironment');
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

/// Locate the repo's real `first_run` onboarding fixture directory
/// (`apps/examples/assets/onboarding`), walking up from the current
/// working directory (the package dir under `dart test`).
Directory locateOnboardingFixtures() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final candidate = Directory(
      p.join(dir.path, 'apps', 'examples', 'assets', 'onboarding'),
    );
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'Could not locate apps/examples/assets/onboarding from '
    '${Directory.current.path}',
  );
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
Future<String> seedSurfaceFlow(
  Directory dir, {
  String type = 'onboarding',
  String slug = 'first_run',
}) async {
  final src = locateOnboardingFixtures();
  final flowsDst = Directory(p.join(dir.path, 'assets', type, 'flows'));
  final screensDst = Directory(p.join(dir.path, 'assets', type, 'screens'));
  await flowsDst.create(recursive: true);
  await screensDst.create(recursive: true);

  final flowJson = await File(
    p.join(src.path, 'flows', 'first_run.flow.json'),
  ).readAsString();
  final flowPath = p.join(flowsDst.path, '$slug.flow.json');
  await File(flowPath).writeAsString(flowJson);

  final doc = FlowDocumentCodec.decodeJson(flowJson);
  for (final artifact in doc.screenArtifacts.values) {
    await File(
      p.join(src.path, 'screens', artifact.path),
    ).copy(p.join(screensDst.path, artifact.path));
    final sidecarName =
        '${p.basenameWithoutExtension(artifact.path)}.capability.json';
    await File(
      p.join(src.path, 'screens', sidecarName),
    ).copy(p.join(screensDst.path, sidecarName));
  }
  return flowPath;
}

/// Build an [http.Client] that returns the same response for every
/// request, computed by [handler]. Useful when the test only cares
/// about a single round-trip.
http.Client mockHttpClient(
  http.Response Function(http.Request request) handler,
) => MockClient((req) async => handler(req));

/// One scripted response per HTTP call. The Nth request to the
/// [http.Client] returns the response produced by `steps[N]`. Asserts
/// (via `test`'s `fail`) on overrun, so tests catch unexpected backend
/// chatter.
typedef ScriptStep = http.Response Function(http.Request request);

/// Build an [http.Client] that drives [steps] one response per call.
http.Client scriptedHttpClient(List<ScriptStep> steps) {
  var index = 0;
  return MockClient((request) async {
    if (index >= steps.length) {
      fail('Unexpected backend call ${index + 1}: ${request.url}');
    }
    final step = steps[index];
    final response = step(request);
    index++;
    return response;
  });
}
