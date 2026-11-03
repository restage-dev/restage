import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/delivery/mounted_surface_report.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';

final _screen = DeliverySurfaceTypeId('screen');
final _placement = PlacementKeyV1.generatedDefault(
  surfaceType: _screen,
  slug: 'welcome',
);

MountedSurfaceReport _report({
  DateTime Function()? now,
  List<String>? mirrored,
  String? apiKey,
}) =>
    MountedSurfaceReport(
      now: now ?? () => DateTime.utc(2026, 11, 2, 12),
      mirror: (scope, fragment) async => mirrored?.add(fragment),
      apiKey: apiKey,
    );

Future<void> _record(MountedSurfaceReport report, String slug) =>
    report.record(placement: _placement, surfaceType: _screen, slug: slug);

void main() {
  test('a mount is kept across a kill and reported after the relaunch',
      () async {
    final first = _report();
    await _record(first, 'welcome');
    // A new object over the same storage stands for the relaunched process.
    final relaunched = _report();
    final pending = await relaunched.pending();
    expect(pending, hasLength(1));
    expect(pending.single.slug, 'welcome');
    expect(pending.single.surfaceType, _screen);
    expect(pending.single.month, '2026-11');
    expect(pending.single.placement, _placement);
  });

  test('a surface mounted twice in a month is reported once', () async {
    var now = DateTime.utc(2026, 11, 30, 23, 59);
    final report = _report(now: () => now);
    await _record(report, 'welcome');
    await _record(report, 'welcome');
    await _record(report, 'other');
    expect(await report.pending(), hasLength(2));
    // The same surface in the next month counts again.
    now = DateTime.utc(2026, 12, 1, 0, 1);
    await _record(report, 'welcome');
    final pending = await report.pending();
    expect(pending, hasLength(3));
    expect(
      pending.where((e) => e.slug == 'welcome').map((e) => e.month).toSet(),
      {'2026-11', '2026-12'},
    );
  });

  test('a report holds at most 64 surfaces, dropping the oldest', () async {
    final report = _report();
    for (var i = 0; i < 70; i++) {
      await _record(report, 'surface-$i');
    }
    final pending = await report.pending();
    expect(pending, hasLength(kMaximumMountedSinceSurfaces));
    expect(pending.first.slug, 'surface-6');
    expect(pending.last.slug, 'surface-69');
    // What is stored is bounded the same way.
    expect(await _report().pending(), hasLength(kMaximumMountedSinceSurfaces));
  });

  test('an acknowledged report drops what it carried and keeps the rest',
      () async {
    final mirrored = <String>[];
    final report = _report(mirrored: mirrored);
    await _record(report, 'welcome');
    final sent = await report.pending();
    // Mounted after the request was built; it rides the next one.
    await _record(report, 'later');
    await report.acknowledge(sent);
    expect([for (final e in await report.pending()) e.slug], ['later']);
    expect([for (final e in await _report().pending()) e.slug], ['later']);
    await report.acknowledge(await report.pending());
    expect(await report.pending(), isEmpty);
    // The platform's copy follows: a fragment while something is pending,
    // nothing once it is acknowledged.
    expect(mirrored.first, startsWith(',"mountedSince":['));
    expect(mirrored.last, '');
  });

  test('a report is sent only under the key that delivered it', () async {
    final mirrored = <(String, String)>[];
    MountedSurfaceReport under(String key) => MountedSurfaceReport(
          now: () => DateTime.utc(2026, 11, 2, 12),
          mirror: (scope, fragment) async => mirrored.add((scope, fragment)),
          apiKey: key,
        );
    // A mount under key A.
    await _record(under('rs_pk_a'), 'welcome');
    // The install relaunches under key B: nothing of A's is reported.
    expect(await under('rs_pk_b').pending(), isEmpty);
    // B's own mounts are kept apart from A's.
    await _record(under('rs_pk_b'), 'other');
    expect(
        [for (final e in await under('rs_pk_b').pending()) e.slug], ['other']);
    // Back under key A, its report is sent, and B's acknowledgement leaves it.
    await under('rs_pk_b').acknowledge(await under('rs_pk_b').pending());
    expect([for (final e in await under('rs_pk_a').pending()) e.slug],
        ['welcome']);
    // The platform's copy follows the key it is told: A's scope with a
    // fragment, B's after its entry was acknowledged with none.
    expect(
        mirrored.where((m) => m.$1 == MountedSurfaceReport.scopeOf('rs_pk_a')),
        isNotEmpty);
    expect(
        mirrored
            .lastWhere((m) => m.$1 == MountedSurfaceReport.scopeOf('rs_pk_b'))
            .$2,
        '');
  });

  test('a key bound while a mount is written does not receive it', () async {
    final report = _report(apiKey: 'rs_pk_a');
    final write = _record(report, 'welcome');
    report.bindKey('rs_pk_b');
    await write;
    final prefs = await SharedPreferences.getInstance();
    final a =
        'restage.mounted_since.${MountedSurfaceReport.scopeOf('rs_pk_a')}';
    final b =
        'restage.mounted_since.${MountedSurfaceReport.scopeOf('rs_pk_b')}';
    expect(prefs.getString(a), contains('welcome'));
    expect(prefs.getString(b), isNull);
    expect(await report.pending(), isEmpty);
  });

  test('a key bound while a mount is read does not throw', () async {
    final report = _report(apiKey: 'rs_pk_a');
    final writes = [
      _record(report, 'welcome'),
      _record(report, 'other'),
    ];
    report.bindKey('rs_pk_b');
    await Future.wait(writes);
    await report.acknowledge(await report.pending());
    expect(await report.pending(), isEmpty);
  });

  test('a read that never lands does not block the next call', () async {
    var reads = 0;
    final report = MountedSurfaceReport(
      preferences: () {
        reads++;
        return reads == 1
            ? Completer<SharedPreferences>().future
            : SharedPreferences.getInstance();
      },
      mirror: (scope, fragment) async {},
    );
    unawaited(report.pending());
    expect(await report.pending(), isEmpty);
    expect(reads, 2);
  });

  test('a client binds the report to its key', () async {
    final report = _report();
    MountedSurfaceReport.instance = report;
    addTearDown(() => MountedSurfaceReport.instance = MountedSurfaceReport());
    RestageRpcClient(baseUrl: 'https://example.com', apiKey: 'rs_pk_a').close();
    await _record(report, 'welcome');
    expect(await report.pending(), hasLength(1));
    // A client for another key reports none of it.
    RestageRpcClient(baseUrl: 'https://example.com', apiKey: 'rs_pk_b').close();
    expect(await report.pending(), isEmpty);
    RestageRpcClient(baseUrl: 'https://example.com', apiKey: 'rs_pk_a').close();
    expect(await report.pending(), hasLength(1));
  });

  test('an entry equals a copy of it, and a copy acknowledges it', () async {
    final report = _report();
    await _record(report, 'welcome');
    final held = (await report.pending()).single;
    final copy = PlacementMountedSurfaceV1.fromJson(held.toJson());
    expect(copy, held);
    expect(copy.hashCode, held.hashCode);
    expect(
      copy,
      isNot(PlacementMountedSurfaceV1(
          placement: held.placement,
          surfaceType: held.surfaceType,
          slug: held.slug,
          month: '2026-12')),
    );
    await report.acknowledge([copy]);
    expect(await report.pending(), isEmpty);
  });

  group('the request client', () {
    Future<
        ({
          MountedSurfaceReport report,
          PlacementBatchRequestV1 request,
          PlacementBatchResponseV1 response
        })> setup() async {
      final fixture = readPlacementDeliveryFixture(
        fileName: 'retained_flow_dependencies_v1.json',
      );
      final report = _report(apiKey: 'rs_pk_test');
      await _record(report, 'welcome');
      MountedSurfaceReport.instance = report;
      addTearDown(() => MountedSurfaceReport.instance = MountedSurfaceReport());
      final request = fixture.request.withMountedSince(await report.pending());
      return (report: report, request: request, response: fixture.response);
    }

    test('a failed request keeps the report', () async {
      final s = await setup();
      for (final status in [500, 429, 401]) {
        final client = RestageRpcClient(
          baseUrl: 'https://example.com',
          apiKey: 'rs_pk_test',
          httpClient: MockClient((_) async => http.Response('', status)),
        );
        addTearDown(client.close);
        await client.fetchPlacements(
          s.request,
          publicationGuard: () => true,
        );
        expect(await s.report.pending(), hasLength(1), reason: '$status');
      }
    });

    test('an answered request clears what it reported', () async {
      final s = await setup();
      sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
      addTearDown(() => sharedSurfaceArtifactStore = null);
      final bodies = <List<int>>[];
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          bodies.add(request.bodyBytes);
          return placementFixtureArtifact(request) ??
              http.Response.bytes(s.response.canonicalBytes, 200);
        }),
      );
      addTearDown(client.close);
      await client.fetchPlacements(
        s.request,
        publicationGuard: () => true,
      );
      expect(bodies.first,
          s.request.withBuildContract(carried: true).canonicalBytes);
      expect(await s.report.pending(), isEmpty);
    });
  });

  test('the shared prefs key holds only entries that decode', () async {
    SharedPreferences.setMockInitialValues({
      'restage.mounted_since': '[{"month":"nope"},'
          '${_encoded(_placement)}]',
    });
    final pending = await _report().pending();
    expect([for (final e in pending) e.slug], ['welcome']);
  });
}

String _encoded(PlacementKeyV1 placement) =>
    '{"month":"2026-11","placement":${String.fromCharCodes(placement.canonicalBytes)},'
    '"surface":{"slug":"welcome","surfaceType":"screen"}}';
