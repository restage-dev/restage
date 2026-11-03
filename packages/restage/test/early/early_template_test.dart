import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show DeliverySurfaceTypeId;
import 'package:restage_shared/restage_shared.dart';

import '../support/placement_delivery_fixture.dart';

String _expand(String text, Map<String, Object?> template, int offset,
    {String mountedSince = ''}) {
  String carrier(Object? tree) =>
      base64Url.encode(utf8.encode(_canonical(tree))).replaceAll('=', '');
  return text
      .replaceAll('@@mountedSince@@', mountedSince)
      .replaceAll('@@utcOffsetMinutes@@', '$offset')
      .replaceAll('@@sdkBuiltIns@@', carrier(template['builtIns']))
      .replaceAll(
          '@@sdkInstalledLibraries@@', carrier(template['installedLibraries']));
}

String _canonical(Object? value) => switch (value) {
      Map() => '{${([
          for (final k in value.keys) k as String
        ]..sort()).map((k) => '${jsonEncode(k)}:${_canonical(value[k])}').join(',')}}',
      List() => '[${value.map(_canonical).join(',')}]',
      _ => jsonEncode(value),
    };

void main() {
  test('the template expands back to the exact bytes Dart would send', () {
    final request = readPlacementDeliveryFixture(
      fileName: 'retained_flow_dependencies_v1.json',
    ).request;
    final json = jsonDecode(
      startupTemplateJson(
          Uri.parse('https://example.com/p'), 'rs_pk_test', request)!,
    ) as Map<String, Object?>;
    final offset = request.localClock?.utcOffsetMinutes ?? 0;
    expect(json['url'], 'https://example.com/p');
    expect(json['authorization'], 'Bearer rs_pk_test');
    expect(
      _expand(json['body']! as String, json, offset),
      utf8.decode(request.withBuildContract(carried: false).canonicalBytes),
    );
    expect(
      _expand(json['fullBody']! as String, json, offset),
      utf8.decode(request.withBuildContract(carried: true).canonicalBytes),
    );
  });

  test('a template leaves the mounted-surface report for the platform to fill',
      () {
    final fixture = readPlacementDeliveryFixture(
      fileName: 'retained_flow_dependencies_v1.json',
    ).request;
    final surface = fixture.mounts.first.key;
    final report = [
      PlacementMountedSurfaceV1(
        placement: surface,
        surfaceType: DeliverySurfaceTypeId('screen'),
        slug: 'welcome',
        month: '2026-11',
      ),
    ];
    final reported = fixture.withMountedSince(report);
    final json = jsonDecode(
      startupTemplateJson(
          Uri.parse('https://example.com/p'), 'rs_pk_test', reported)!,
    ) as Map<String, Object?>;
    final offset = reported.localClock?.utcOffsetMinutes ?? 0;
    // The template never holds a report; the platform splices its own in.
    expect(
        json['body'], contains('"mode":"prefetch"@@mountedSince@@,"mounts"'));
    expect(json['body'], isNot(contains('"mountedSince"')));
    expect(
      _expand(json['body']! as String, json, offset),
      utf8.decode(
        fixture.withBuildContract(carried: false).canonicalBytes,
      ),
    );
    // Spliced with the fragment for the report, it is the exact request bytes.
    expect(
      _expand(json['fullBody']! as String, json, offset,
          mountedSince: mountedSinceTemplateFragment(report)),
      utf8.decode(reported.withBuildContract(carried: true).canonicalBytes),
    );
    expect(mountedSinceTemplateFragment(const []), '');
  });

  test('only facts the platform reads are left for it to fill', () {
    final request = readPlacementDeliveryFixture(
      fileName: 'retained_flow_dependencies_v1.json',
    ).request;
    final json = jsonDecode(
      startupTemplateJson(
          Uri.parse('https://example.com/p'), 'rs_pk_test', request)!,
    ) as Map<String, Object?>;
    final fills = (json['fills']! as List).cast<String>();
    expect(fills, isNot(contains('sdkApiLevel')));
    expect(fills, isNot(contains('channel')));
  });

  test('the platform recomputes the contract hash for its own build number',
      () {
    final fixture = readPlacementDeliveryFixture(
      fileName: 'retained_flow_dependencies_v1.json',
    ).request.buildContract;
    PlacementBatchRequestV1 requestWith(int ordinal) => startupRequestFor(
          platform: fixture.platform,
          mounts: fixture.mounts.toList(),
          contractsByHash: fixture.contractsByHash,
          capability: fixture.installedCapability,
          builtIns: {'platform': fixture.platform},
          buildOrdinal: ordinal,
        );
    final json = jsonDecode(
      startupTemplateJson(
        Uri.parse('https://example.com/p'),
        'rs_pk_test',
        requestWith(1),
        identityTokens: true,
      )!,
    ) as Map<String, Object?>;
    expect(json['fills'], contains('buildOrdinal'));
    final contract =
        (json['contract']! as String).replaceAll('@@buildOrdinal@@', '41');
    final digest = sha256.convert(
      utf8.encode('restage.placement-build-contract.v1\u0000$contract'),
    );
    expect('sha256:$digest', requestWith(41).appBuildContractHash);
  });
}
