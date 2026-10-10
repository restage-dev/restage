import 'package:restage_shared/src/surface_contract/surface_screen_host_data_schema.dart';

/// Builds readable sample host data for every input [schema] declares.
///
/// Strings read as their input name in sentence case (`streakDays` becomes
/// "Streak days"), numbers are small, lists hold two items, and nullable
/// inputs get their non-null sample.
Map<String, Object?> sampleHostContext(SurfaceScreenHostDataSchema schema) =>
    <String, Object?>{
      for (final entry in schema.inputs.entries)
        entry.key: _sample(entry.value, entry.key),
    };

Object? _sample(SurfaceScreenHostDataShape shape, String name) =>
    switch (shape) {
      SurfaceScreenHostDataScalarShapeV1(:final kind) => switch (kind) {
          SurfaceScreenHostDataScalarKind.boolean => true,
          SurfaceScreenHostDataScalarKind.integer => 3,
          SurfaceScreenHostDataScalarKind.doubleValue => 1.5,
          SurfaceScreenHostDataScalarKind.number => 3,
          SurfaceScreenHostDataScalarKind.string ||
          SurfaceScreenHostDataScalarKind.jsonValue =>
            _sentenceCase(name),
        },
      SurfaceScreenHostDataNullableShapeV1(:final value) =>
        _sample(value, name),
      SurfaceScreenHostDataListShapeV1(:final items) => <Object?>[
          _sample(items, name),
          _sample(items, name),
        ],
      SurfaceScreenHostDataMapShapeV1(:final values) => <String, Object?>{
          name: _sample(values, name),
        },
      SurfaceScreenHostDataObjectShapeV1(:final fields) => <String, Object?>{
          for (final entry in fields.entries)
            entry.key: _sample(entry.value, entry.key),
        },
    };

String _sentenceCase(String name) {
  final words = name
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(RegExp(r'[_\-\s]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word.toLowerCase())
      .toList();
  if (words.isEmpty) return name;
  final text = words.join(' ');
  return text[0].toUpperCase() + text.substring(1);
}
