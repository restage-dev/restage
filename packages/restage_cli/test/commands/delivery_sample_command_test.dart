import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_cli/src/commands/delivery_command.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as m
    show RuntimePlane;
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

const operationId = '4d1f28ea-0c97-4d87-8fd7-15164749e440';
const sampleId = '86505cf7-c04b-45d0-83c8-529ec1b8db1c';

TargetCoordinate sampleTarget({
  bool live = false,
  int appId = 8,
  int? targetId,
  int? namedId,
}) => TargetCoordinate(
  organizationId: OrganizationId(7),
  appId: ApplicationId(appId),
  environmentTargetId: EnvironmentTargetId(targetId ?? (live ? 13 : 12)),
  namedEnvironmentId: NamedEnvironmentId(namedId ?? (live ? 23 : 22)),
  runtimePlane: live ? m.RuntimePlane.live : m.RuntimePlane.sandbox,
);

Uint8List samplePng([int red = 0]) {
  final out = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String name, List<int> data) {
    final body = [...ascii.encode(name), ...data];
    var crc = 0xffffffff;
    for (final byte in body) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320);
      }
    }
    final length = ByteData(4)..setUint32(0, data.length);
    final checksum = ByteData(4)..setUint32(0, crc ^ 0xffffffff);
    out
      ..add(length.buffer.asUint8List())
      ..add(body)
      ..add(checksum.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, 1)
    ..setUint32(4, 1)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert([0, red, 0, 0, 255]));
  chunk('IEND', const []);
  return out.takeBytes();
}

PlacementScreenCaptureV1 sampleCapture(Uint8List png) {
  final host = SurfaceHostContractV1(
    hosting: const SurfaceHostingV1(
      contentKind: SurfaceContentKindV1.single,
      presentation: SurfacePresentationV1.inline,
    ),
    providedContext: const SurfaceScreenHostDataSchema.empty(),
    handledEvents: SurfaceScreenEventSchema(events: const []),
  );
  final capability = InstalledCapability(
    builtInCatalogVersion: 4,
    installedLibraries: const [],
  );
  final key = PlacementKeyV1.named(slug: 'welcome');
  final build = PlacementBuildContractV1(
    platform: 'ios',
    mounts: [
      PlacementMountRequestV1(key: key, hostContractHash: host.contentHash),
    ],
    contractsByHash: {host.contentHash: host},
    installedCapability: capability,
    installedCapabilityHash: capability.contentHash,
  );
  return PlacementScreenCaptureV1(
    buildContract: build,
    appBuildContractHash: build.appBuildContractHash,
    screenLabel: 'Welcome',
    captureScope: PlacementScreenCaptureScopeV1.explicitBoundary,
    logicalViewport: PlacementLogicalSizeV1.fromLogical(width: 1, height: 1),
    rasterScale: PlacementRasterScaleV1.fromRequestedScale(1),
    pngWidth: 1,
    pngHeight: 1,
    pngByteLength: png.length,
    pngSha256: 'sha256:${sha256.convert(png)}',
    mounts: [
      PlacementSampleMountV1(
        key: key,
        hostContractHash: host.contentHash,
        rect: PlacementLogicalRectV1.fromLogical(
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
        occurrenceIndex: 0,
      ),
    ],
  );
}

PlacementSampleDraftV1 sampleDraft(TargetCoordinate target, Uint8List png) {
  final capture = sampleCapture(png);
  final manifest = capture.bindTarget(target);
  return PlacementSampleDraftV1(
    manifest: manifest,
    buildContract: capture.buildContract,
    reviewedDigest: manifest.reviewDigest,
  );
}

PlacementSampleUploadTicketV1 sampleTicket(PlacementSampleDraftV1 draft) =>
    PlacementSampleUploadTicketV1(
      ticketId: 'dc0bdfb5-d815-4e7b-8d9f-76647d28c68b',
      manifestDigest: draft.manifestDigest,
      imageSha256: draft.manifest.pngSha256,
      expiresAtMicros: DateTime.utc(2027).microsecondsSinceEpoch,
      limits: PlacementSampleUploadLimitsV1(),
    );

void main() {
  test(
    'registered commands import without mutation then review store bind read and delete exact evidence',
    () async {
      final h = await SampleCommandHarness.create();
      addTearDown(h.dispose);
      final png = samplePng();
      final draft = sampleDraft(sampleTarget(), png);
      final ticket = sampleTicket(draft);
      final stored = PlacementSampleStoredV1(
        sampleId: sampleId,
        manifestDigest: draft.manifestDigest,
        imageSha256: draft.manifest.pngSha256,
      );
      final ref = PlacementScreenSampleRefV1(
        target: draft.manifest.target,
        sampleId: sampleId,
        appBuildContractHash: draft.manifest.appBuildContractHash,
        manifestDigest: draft.manifestDigest,
        imageSha256: draft.manifest.pngSha256,
        screenLabel: 'Welcome',
        bindingRevision: 2,
      );
      h.responses.addAll([
        ticket.canonicalBytes,
        stored.canonicalBytes,
        ref.canonicalBytes,
        PlacementSampleReadResultV1(
          sampleId: sampleId,
          status: PlacementSampleStatusV1.bound,
          manifest: draft.manifest,
          ref: ref,
          bindingRevision: 2,
        ).canonicalBytes,
        png,
        PlacementSampleDeleteResultV1(
          sampleId: sampleId,
          status: PlacementSampleDeletionStatusV1.removed,
          bindingRevision: 3,
        ).canonicalBytes,
      ]);
      final capturePath = await h.file(
        'capture.json',
        sampleCapture(png).canonicalBytes,
      );
      final pngPath = await h.file('capture.png', png);
      final draftPath = '${h.directory.path}/draft.json';
      final ticketPath = '${h.directory.path}/ticket.json';
      final storedPath = '${h.directory.path}/stored.json';
      expect(
        await h.run([
          'import',
          '--manifest',
          capturePath,
          '--png',
          pngPath,
          '--out',
          draftPath,
        ]),
        0,
      );
      expect(h.calls, isEmpty);
      expect(await File(draftPath).readAsBytes(), draft.canonicalBytes);
      expect(
        await h.run([
          'review',
          '--draft',
          draftPath,
          '--png',
          pngPath,
          '--reviewed-digest',
          draft.reviewedDigest,
          '--operation-id',
          operationId,
          '--out',
          ticketPath,
        ]),
        0,
      );
      final prepare = PlacementSamplePrepareV1.fromCanonicalBytes(
        h.requestBytes(h.calls.single),
      );
      expect(prepare.manifest.target, sampleTarget());
      expect(prepare.buildContract, sampleCapture(png).buildContract);
      expect(prepare.reviewedDigest, draft.reviewedDigest);
      expect(await File(ticketPath).readAsBytes(), ticket.canonicalBytes);
      expect(
        await h.run([
          'upload',
          '--ticket',
          ticketPath,
          '--png',
          pngPath,
          '--out',
          storedPath,
        ]),
        0,
      );
      expect(h.calls.last['pngBytes'], encodeByteDataWire(png));
      expect(
        await h.run([
          'bind',
          '--stored',
          storedPath,
          '--operation-id',
          operationId,
          '--expected-binding-revision',
          '1',
        ]),
        0,
      );
      final bind = PlacementSampleBindV1.fromCanonicalBytes(
        h.requestBytes(h.calls.last),
      );
      expect(bind.expectedBindingRevision, 1);
      expect(bind.sampleId, sampleId);
      expect(await h.run(['show', '--sample-id', sampleId]), 0);
      final download = '${h.directory.path}/download.png';
      expect(
        await h.run(['download', '--sample-id', sampleId, '--out', download]),
        0,
      );
      expect(await File(download).readAsBytes(), png);
      expect(
        await h.run([
          'delete',
          '--sample-id',
          sampleId,
          '--operation-id',
          operationId,
          '--expected-binding-revision',
          '2',
        ]),
        0,
      );
      expect(h.calls.map((call) => call['method']), [
        'prepare',
        'store',
        'bind',
        'read',
        'readImage',
        'delete',
      ]);
      for (final call in h.calls) {
        expect(call['organizationId'], 7);
        expect(call['environmentTargetId'], 12);
        expect(call['runtimePlane'], 'sandbox');
        expect(call['projectSlug'], 'p');
        expect(call['appSlug'], 'a');
      }
    },
  );

  test('--yes alone cannot create explicit sample review consent', () async {
    final h = await SampleCommandHarness.create();
    addTearDown(h.dispose);
    final png = samplePng();
    final draft = sampleDraft(sampleTarget(), png);
    final path = await h.file('draft.json', draft.canonicalBytes);
    final image = await h.file('capture.png', png);
    expect(
      await h.run([
        'review',
        '--draft',
        path,
        '--png',
        image,
        '--out',
        '${h.directory.path}/ticket.json',
      ], yes: true),
      1,
    );
    expect(h.calls, isEmpty);
    expect(h.stderr.toString(), contains('--reviewed-digest'));
  });

  test(
    'a valid swapped PNG refuses before store after an accepted review',
    () async {
      final h = await SampleCommandHarness.create();
      addTearDown(h.dispose);
      final png = samplePng();
      final draft = sampleDraft(sampleTarget(), png);
      final ticketPath = '${h.directory.path}/ticket.json';
      final draftPath = await h.file('draft.json', draft.canonicalBytes);
      final image = await h.file('capture.png', png);
      h.responses.add(sampleTicket(draft).canonicalBytes);
      expect(
        await h.run([
          'review',
          '--draft',
          draftPath,
          '--png',
          image,
          '--reviewed-digest',
          draft.reviewedDigest,
          '--operation-id',
          operationId,
          '--out',
          ticketPath,
        ]),
        0,
      );
      await File(image).writeAsBytes(samplePng(255));
      expect(
        await h.run([
          'upload',
          '--ticket',
          ticketPath,
          '--png',
          image,
          '--out',
          '${h.directory.path}/stored.json',
        ]),
        1,
      );
      expect(h.calls.map((call) => call['method']), ['prepare']);
      expect(
        h.stderr.toString(),
        contains('does not match the reviewed ticket'),
      );
    },
  );

  test(
    'sample prepare uses the actual live guard and admits the exact approved control',
    () async {
      final h = await SampleCommandHarness.create();
      addTearDown(h.dispose);
      final png = samplePng();
      final draft = sampleDraft(sampleTarget(live: true), png);
      final path = await h.file('draft.json', draft.canonicalBytes);
      final image = await h.file('capture.png', png);
      final args = [
        'review',
        '--draft',
        path,
        '--png',
        image,
        '--reviewed-digest',
        draft.reviewedDigest,
        '--operation-id',
        operationId,
        '--out',
        '${h.directory.path}/ticket.json',
      ];
      expect(await h.run(args, live: true), 1);
      expect(h.calls, isEmpty);
      h.responses.add(sampleTicket(draft).canonicalBytes);
      expect(await h.run(args, live: true, yes: true), 0);
      expect(h.calls.single['method'], 'prepare');
    },
  );

  test(
    'typed sample unavailability stays a refusal without a new association',
    () async {
      final h = await SampleCommandHarness.create();
      addTearDown(h.dispose);
      h.refusal = http.Response(
        jsonEncode({
          'className': 'PlacementSampleUnavailableException',
          'data': {'reason': 'expired'},
        }),
        400,
      );
      expect(await h.run(['show', '--sample-id', sampleId]), 1);
      expect(h.stderr.toString(), contains('expired'));
      expect(h.calls.single['method'], 'read');
    },
  );
}

class SampleCommandHarness {
  SampleCommandHarness(this.directory, this.store);
  final Directory directory;
  final FileCredentialStore store;
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  final calls = <Map<String, dynamic>>[];
  final responses = <List<int>>[];
  http.Response? refusal;

  static Future<SampleCommandHarness> create() async {
    final directory = await Directory.systemTemp.createTemp('delivery_sample_');
    final store = FileCredentialStore('${directory.path}/credentials');
    await seedCredential(store);
    return SampleCommandHarness(directory, store);
  }

  Future<String> file(String name, List<int> bytes) async {
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Uint8List requestBytes(Map<String, dynamic> call) =>
      decodeByteDataWire(call['requestBytes'], malformed: FormatException.new);

  Future<int?> run(List<String> args, {bool yes = false, bool live = false}) {
    final client = mockHttpClient((request) {
      expect(request.url.path, '/placementSample');
      calls.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (refusal != null) return refusal!;
      expect(
        responses,
        isNotEmpty,
        reason: 'No response for an extra sample operation',
      );
      return http.Response(
        jsonEncode(encodeByteDataWire(responses.removeAt(0))),
        200,
      );
    });
    final runner = CommandRunner<int>('restage', '')
      ..argParser.addFlag('yes', negatable: false);
    runner.addCommand(
      DeliveryCommand(
        stdout: stdout,
        stderr: stderr,
        interactive: const NonInteractive(),
        credentialStore: store,
        httpClient: client,
      ),
    );
    return runner.run([
      if (yes) '--yes',
      'delivery',
      'sample',
      ...args,
      '-C',
      directory.path,
      '--project',
      'p',
      '--app',
      'a',
      '--env',
      live ? 'production' : 'staging',
      '--plane',
      live ? 'live' : 'sandbox',
      '--json',
    ]);
  }

  Future<void> dispose() => directory.delete(recursive: true);
}
