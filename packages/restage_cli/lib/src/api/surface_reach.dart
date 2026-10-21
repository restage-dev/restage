import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_cli/src/output/held_count.dart';

/// The largest reach response the CLI reads.
const int surfaceReachMaximumBytes = 256 * 1024;

/// Why some devices are not on a surface's live version.
enum SurfaceReachReason {
  /// Their build cannot render the version they hold.
  cantRender,

  /// A delivery rule sends them another version.
  routed,

  /// They have not fetched the surface since the live version went live.
  notOpened,
}

/// Devices not on the live version for one reason.
class SurfaceReachStraggler {
  /// Construct a straggler row.
  const SurfaceReachStraggler({
    required this.reason,
    required this.version,
    required this.devices,
    this.platform,
    this.appBuild,
    this.routeId,
    this.fallback,
  });

  /// Decode one wire object.
  factory SurfaceReachStraggler.fromJson(Map<String, dynamic> json) =>
      SurfaceReachStraggler(
        reason: SurfaceReachReason.values.byName(json['reason']! as String),
        version: json['version']! as int,
        devices: json['devices']! as int,
        platform: json['platform'] as String?,
        appBuild: json['appBuild'] as int?,
        routeId: json['routeId'] as String?,
        fallback: json['fallback'] as String?,
      );

  /// Why these devices are not on the live version.
  final SurfaceReachReason reason;

  /// The version they hold.
  final int version;

  /// How many devices.
  final int devices;

  /// The build's platform, for a build that cannot render.
  final String? platform;

  /// The build's ordinal, or -1 when it reported none.
  final int? appBuild;

  /// The rule sending them [version].
  final String? routeId;

  /// What they show instead: `bundled` or `holdLastGood`.
  final String? fallback;

  /// The wire form.
  Map<String, Object?> toJson() => {
    'reason': reason.name,
    'version': version,
    'devices': devices,
    if (platform != null) 'platform': platform,
    if (appBuild != null) 'appBuild': appBuild,
    if (routeId != null) 'routeId': routeId,
    if (fallback != null) 'fallback': fallback,
  };
}

/// How far a surface's live version reached devices.
///
/// [devices] counts installs that fetched the surface in the last 30 days;
/// [reached], those holding the live version. A count from one to four is
/// null and reads "<5".
class SurfaceReach {
  /// Construct a reach.
  const SurfaceReach({
    required this.asOf,
    this.liveVersion,
    this.liveSince,
    this.devices,
    this.reached,
    this.stragglers = const [],
    this.hiddenStragglerRows = 0,
    this.viewsSinceLive,
    this.liveViewsSinceLive,
    this.liveViewShareSinceLive,
  });

  /// Decode one wire object.
  factory SurfaceReach.fromJson(Map<String, dynamic> json) {
    DateTime? at(Object? micros) => micros == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(micros as int, isUtc: true);
    return SurfaceReach(
      asOf: at(json['asOfMicros'])!,
      liveVersion: json['liveVersion'] as int?,
      liveSince: at(json['liveSinceMicros']),
      devices: json['devices'] as int?,
      reached: json['reached'] as int?,
      stragglers: [
        for (final row in (json['stragglers'] as List<dynamic>?) ?? const [])
          SurfaceReachStraggler.fromJson(row as Map<String, dynamic>),
      ],
      hiddenStragglerRows: json['hiddenStragglerRows'] as int? ?? 0,
      viewsSinceLive: json['viewsSinceLive'] as int?,
      liveViewsSinceLive: json['liveViewsSinceLive'] as int?,
      liveViewShareSinceLive: json['liveViewShareSinceLive'] as int?,
    );
  }

  /// Decode the canonical bytes the reach read answers.
  factory SurfaceReach.fromBytes(Uint8List bytes) => SurfaceReach.fromJson(
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
  );

  /// When the read was taken.
  final DateTime asOf;

  /// The live version, or null when nothing is live.
  final int? liveVersion;

  /// When the live version went live.
  final DateTime? liveSince;

  /// Installs that fetched the surface in the last 30 days.
  final int? devices;

  /// Of them, those holding the live version.
  final int? reached;

  /// Devices not on the live version, by reason.
  final List<SurfaceReachStraggler> stragglers;

  /// Straggler rows under the privacy floor, left out.
  final int hiddenStragglerRows;

  /// Painted views since the live version went live, over at most 14 days.
  final int? viewsSinceLive;

  /// Of them, views of the live version.
  final int? liveViewsSinceLive;

  /// The live version's share of those views, in basis points.
  final int? liveViewShareSinceLive;

  /// The wire form.
  Map<String, Object?> toJson() => {
    'asOfMicros': asOf.microsecondsSinceEpoch,
    if (liveVersion != null) 'liveVersion': liveVersion,
    if (liveSince != null) 'liveSinceMicros': liveSince!.microsecondsSinceEpoch,
    if (devices != null) 'devices': devices,
    if (reached != null) 'reached': reached,
    if (stragglers.isNotEmpty)
      'stragglers': [for (final s in stragglers) s.toJson()],
    if (hiddenStragglerRows > 0) 'hiddenStragglerRows': hiddenStragglerRows,
    if (viewsSinceLive != null) 'viewsSinceLive': viewsSinceLive,
    if (liveViewsSinceLive != null) 'liveViewsSinceLive': liveViewsSinceLive,
    if (liveViewShareSinceLive != null)
      'liveViewShareSinceLive': liveViewShareSinceLive,
  };
}

/// The headline: `v5 reached 1,240 of 1,610 devices (77%) · 2 h after
/// publish`.
String surfaceReachHeadline(SurfaceReach reach) {
  final live = reach.liveVersion;
  if (live == null) return 'No version is live.';
  final reached = reach.reached;
  final devices = reach.devices;
  final share = reached != null && devices != null && devices > 0
      ? ' (${(reached * 100 / devices).round()}%)'
      : '';
  final elapsed = reach.liveSince == null
      ? null
      : reach.asOf.difference(reach.liveSince!);
  final since = elapsed == null
      ? ''
      : elapsed.inMinutes < 1
      ? ' · just published'
      : ' · ${_elapsed(elapsed)} after publish';
  return 'v$live reached ${countText(reached)} of ${countText(devices)} '
      'devices$share$since';
}

/// The headline, the live version's share of views, then one line per
/// straggler row and the hidden rows.
List<String> renderSurfaceReach(SurfaceReach reach) => [
  surfaceReachHeadline(reach),
  if (reach.liveViewShareSinceLive case final share?)
    '  Views since publish: ${(share / 100).round()}% v${reach.liveVersion}',
  for (final s in reach.stragglers) '  ${_straggler(reach, s)}',
  if (reach.hiddenStragglerRows > 0)
    '  ${reach.hiddenStragglerRows} smaller '
        '${reach.hiddenStragglerRows == 1 ? 'group' : 'groups'} hidden for '
        'privacy',
];

String _straggler(SurfaceReach reach, SurfaceReachStraggler s) {
  final devices = '${countText(s.devices)} devices';
  return switch (s.reason) {
    SurfaceReachReason.cantRender =>
      "Can't render v${s.version} · ${s.platform} build "
          '${s.appBuild == null || s.appBuild! < 0 ? 'unknown' : s.appBuild} · '
          '$devices · ${_fallback(s.fallback)}',
    SurfaceReachReason.routed =>
      'Sent v${s.version} by rule ${s.routeId} · $devices',
    SurfaceReachReason.notOpened =>
      'Not opened since v${reach.liveVersion} went live · on v${s.version} · '
          '$devices',
  };
}

String _fallback(String? source) => switch (source) {
  'bundled' => 'shows the bundled screen',
  'holdLastGood' => 'shows the last version it rendered',
  _ => 'shows nothing',
};

String _elapsed(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 48) return '${d.inHours} h';
  return '${d.inDays} d';
}
