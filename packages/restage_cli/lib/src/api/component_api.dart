import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_shared/restage_shared.dart'
    show BlobSurfacePayload, SurfaceEditorState, SurfacePayload;
import 'package:restage_shared/rfw_formats.dart'
    show ConstructorCall, decodeLibraryBlob;

/// One shared component and its newest version.
@experimental
@immutable
class ComponentSummary {
  /// Construct a summary.
  const ComponentSummary({
    required this.id,
    required this.name,
    required this.scope,
    required this.latestVersion,
    required this.updatedAt,
    required this.usedBy,
    required this.onOlderVersion,
    required this.inAppBuild,
  });

  /// Decode one backend row.
  factory ComponentSummary.fromJson(Map<String, dynamic> json) =>
      ComponentSummary(
        id: json['id'] as int,
        name: json['name'] as String,
        scope: json['scope'] as String,
        latestVersion: json['latestVersion'] as int,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        usedBy: json['usedBy'] as int,
        onOlderVersion: json['onOlderVersion'] as int,
        inAppBuild: json['inAppBuild'] as bool?,
      );

  /// Component id.
  final int id;

  /// Component name.
  final String name;

  /// `project` or `organization`.
  final String scope;

  /// Newest version number.
  final int latestVersion;

  /// When the component last changed.
  final DateTime updatedAt;

  /// Surfaces whose saved draft pins any version.
  final int usedBy;

  /// Of [usedBy], surfaces pinned below [latestVersion].
  final int onOlderVersion;

  /// False when no app build registers what the newest version needs; null
  /// when the server did not say.
  final bool? inAppBuild;

  /// The JSON form.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'scope': scope,
    'latestVersion': latestVersion,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'usedBy': usedBy,
    'onOlderVersion': onOlderVersion,
    'inAppBuild': inAppBuild,
  };
}

/// One immutable component version.
@experimental
@immutable
class ComponentVersionRow {
  /// Construct a version row.
  const ComponentVersionRow({
    required this.version,
    required this.createdAt,
    required this.payload,
  });

  /// Decode one backend row.
  factory ComponentVersionRow.fromJson(Map<String, dynamic> json) =>
      ComponentVersionRow(
        version: json['version'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        payload: decodeByteDataWire(
          json['payload'],
          malformed: (detail) =>
              FormatException('The component payload $detail.'),
        ),
      );

  /// Version number.
  final int version;

  /// When the version was created.
  final DateTime createdAt;

  /// The encoded surface payload.
  final Uint8List payload;
}

/// Typed wrapper over the backend's `component` RPC endpoint.
@experimental
class ComponentApi {
  /// Build a client backed by [_api].
  ComponentApi(this._api);

  final RestageApi _api;

  /// The components of [project] plus its organization's.
  Future<List<ComponentSummary>> list({
    required int organizationId,
    required String project,
  }) async {
    final raw = await _api.call('component', 'list', {
      'organizationId': organizationId,
      'projectSlug': project,
    });
    return [
      for (final row in raw as List<dynamic>)
        ComponentSummary.fromJson(row as Map<String, dynamic>),
    ];
  }

  /// One version of component [componentId].
  Future<ComponentVersionRow> loadVersion({
    required int organizationId,
    required int componentId,
    required int version,
  }) async => ComponentVersionRow.fromJson(
    await _api.call('component', 'loadVersion', {
          'organizationId': organizationId,
          'componentId': componentId,
          'version': version,
        })
        as Map<String, dynamic>,
  );
}

/// What a component version declares: its declarations, the libraries it
/// imports, its entry widget and its slot defaults.
///
/// Throws [FormatException] when [payload] is not a component version.
@experimental
Map<String, Object?> describeComponentPayload(Uint8List payload) {
  final decoded = SurfacePayload.decode(payload);
  if (decoded is! BlobSurfacePayload) {
    throw const FormatException('A component is a single screen.');
  }
  final library = decodeLibraryBlob(decoded.blob);
  final entry = library.widgets.firstWhere(
    (widget) => widget.name == 'main',
    orElse: () => throw const FormatException('The component has no entry.'),
  );
  final state = decoded.editorState;
  final meta = state == null
      ? const <String, Object?>{}
      : SurfaceEditorState.decode(state).meta;
  final slots = meta['slots'];
  return {
    'entry': entry.root is ConstructorCall
        ? (entry.root as ConstructorCall).name
        : null,
    'declarations': [for (final widget in library.widgets) widget.name],
    'imports': [
      for (final import in library.imports) import.name.parts.join('.'),
    ],
    'slots': slots is Map<String, Object?> ? slots : <String, Object?>{},
  };
}
