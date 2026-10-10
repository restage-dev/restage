import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/restage_api.dart';

/// Why a published version is live.
@experimental
enum LiveVersionKind {
  /// It is what a surface serves by default.
  serving,

  /// A delivery rule routes to it.
  deliveryRule,

  /// A running experiment arm serves it.
  experimentArm;

  static LiveVersionKind _fromWire(Object? raw) => values.firstWhere(
    (value) => value.name == raw,
    orElse: () => throw FormatException('Unknown live version kind: $raw'),
  );
}

/// One live published version and the custom libraries it needs.
@experimental
@immutable
final class LiveVersionRequirements {
  /// Construct one live version.
  const LiveVersionRequirements({
    required this.environment,
    required this.kind,
    required this.surfaceType,
    required this.surfaceSlug,
    required this.publishedRevision,
    required this.requiredLibraries,
    this.versionLabel,
    this.routeId,
    this.experimentId,
    this.experimentLabel,
    this.armId,
    this.armLabel,
  });

  /// Decode one wire item.
  factory LiveVersionRequirements.fromJson(Map<String, dynamic> json) {
    final libraries = json['requiredLibraries'] as List<dynamic>?;
    return LiveVersionRequirements(
      environment: json['environmentSlug'] as String,
      kind: LiveVersionKind._fromWire(json['kind']),
      surfaceType: json['surfaceType'] as String,
      surfaceSlug: json['surfaceSlug'] as String,
      publishedRevision: json['publishedRevision'] as int,
      versionLabel: json['versionLabel'] as String?,
      routeId: json['routeId'] as String?,
      experimentId: json['experimentId'] as String?,
      experimentLabel: json['experimentLabel'] as String?,
      armId: json['armId'] as String?,
      armLabel: json['armLabel'] as String?,
      requiredLibraries: libraries == null
          ? null
          : {
              for (final entry in libraries.cast<Map<String, dynamic>>())
                entry['namespace'] as String: entry['minVersion'] as int,
            },
    );
  }

  /// Environment slug.
  final String environment;

  /// Why the version is live.
  final LiveVersionKind kind;

  /// Surface type wire name.
  final String surfaceType;

  /// Surface slug.
  final String surfaceSlug;

  /// Version number.
  final int publishedRevision;

  /// Version name, when it has one.
  final String? versionLabel;

  /// The delivery rule routing to the version.
  final String? routeId;

  /// The experiment serving the version.
  final String? experimentId;

  /// That experiment's name.
  final String? experimentLabel;

  /// The arm serving the version.
  final String? armId;

  /// That arm's name.
  final String? armLabel;

  /// Minimum version per library namespace; null when the payload could not
  /// be read.
  final Map<String, int>? requiredLibraries;
}

/// Reads which libraries an app's live versions need.
@experimental
final class LibraryRequirementsApi {
  /// Wrap [api].
  const LibraryRequirementsApi(this._api);

  final RestageApi _api;

  /// Every live version of the app in every environment.
  Future<List<LiveVersionRequirements>> liveLibraryRequirements({
    required String project,
    required String app,
    int? organizationId,
  }) async {
    final raw = await _api.call(
      'surfaceLibraryRequirements',
      'liveLibraryRequirements',
      <String, dynamic>{
        'projectSlug': project,
        'appSlug': app,
        'organizationId': ?organizationId,
      },
    );
    final items = (raw as Map<String, dynamic>)['items'] as List<dynamic>;
    return [
      for (final item in items.cast<Map<String, dynamic>>())
        LiveVersionRequirements.fromJson(item),
    ];
  }
}
