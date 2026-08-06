import 'dart:convert';

/// Frozen provenance for the last published schema-v4 reader that predates
/// typed property constraints.
const publishedPackageVersion = '1.1.0';
const publishedAt = '2026-07-13T01:17:44.597072Z';
const publishedReleaseCommit = '185c4abea6802a9893914881d957c9bc7b734a9a';
const publishedArchiveSha256 =
    'dbfeaf0d900d66620354f0fd5749be2a35e5e0a669556619e52201c7510d78e5';
const publishedCatalogCodecSha256 =
    '08ce94e815b375368dafc53a1c70cb89e60c0e3288c44e8e15c8c7cc961ffd81';
const publishedPropertyEntrySha256 =
    '3794858798b4b6e3f6a1109cc26a1d4b3e28b93c171aeb2a38d424aed124d939';

/// Property fields recognized by the published 1.1.0 encoder, in its exact
/// insertion order (`catalog_codec.dart` at lines 854-889 in the archive).
///
/// The matching reader starts at line 1887. It reads these fields but performs
/// no allowed-key check, which is why a newer `constraints` field is accepted
/// and then erased on re-encode.
const publishedPropertyFieldOrder = <String>[
  'wireId',
  'name',
  'type',
  'description',
  'required',
  'synthetic',
  'positional',
  'enumType',
  'widgetType',
  'callbackSignature',
  'firesAs',
  'defaultSource',
  'mutuallyExclusiveWith',
  'requiresAncestor',
  'category',
  'priority',
  'validationRule',
  'deprecated',
  'structuredRef',
  'valueShape',
];

/// Runs the property portion of a canonical schema-v4 catalog through the
/// frozen published 1.1.0 reader/writer projection.
///
/// This fixture deliberately owns its model and field list. It imports no
/// current production schema types and reads no Pub cache or network data at
/// test time. Its input is constrained to already-canonical 1.1.0 fields, for
/// which the published nested codecs are identity round trips; the only newer
/// property field under characterization is `constraints`.
String publishedV110PropertyRoundTrip(String source) {
  final catalog = jsonDecode(source) as Map<String, dynamic>;
  final widgets = catalog['widgets'] as List;
  for (final widgetValue in widgets) {
    final widget = widgetValue as Map<String, dynamic>;
    final properties = widget['properties'] as List;
    for (var i = 0; i < properties.length; i++) {
      properties[i] = PublishedV110Property.fromJson(
        properties[i] as Map<String, dynamic>,
      ).toJson();
    }
  }
  return const JsonEncoder.withIndent('  ').convert(catalog);
}

/// Independent pre-constraint property model copied from the published 1.1.0
/// field projection.
final class PublishedV110Property {
  PublishedV110Property._({
    required this.wireId,
    required this.name,
    required this.type,
    required this.description,
    required this.required,
    required this.synthetic,
    required this.positional,
    required this.enumType,
    required this.widgetType,
    required this.callbackSignature,
    required this.firesAs,
    required this.defaultSource,
    required this.mutuallyExclusiveWith,
    required this.requiresAncestor,
    required this.category,
    required this.priority,
    required this.validationRule,
    required this.deprecated,
    required this.structuredRef,
    required this.valueShape,
  });

  factory PublishedV110Property.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('published 1.1.0 property requires $key');
      }
      return value;
    }

    T? optional<T>(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! T) {
        throw FormatException(
          'published 1.1.0 property $key expected $T, '
          'got ${value.runtimeType}',
        );
      }
      return value;
    }

    final mutex = optional<List<dynamic>>('mutuallyExclusiveWith');
    return PublishedV110Property._(
      wireId: requiredString('wireId'),
      name: requiredString('name'),
      type: requiredString('type'),
      description: requiredString('description'),
      required: optional<bool>('required') ?? false,
      synthetic: optional<String>('synthetic'),
      positional: optional<bool>('positional') ?? false,
      enumType: optional<String>('enumType'),
      widgetType: optional<String>('widgetType'),
      callbackSignature: optional<String>('callbackSignature'),
      firesAs: optional<String>('firesAs'),
      defaultSource: json['defaultSource'],
      mutuallyExclusiveWith:
          mutex == null ? null : List<Object?>.unmodifiable(mutex),
      requiresAncestor: optional<String>('requiresAncestor'),
      category: optional<String>('category'),
      priority: optional<String>('priority'),
      validationRule: json['validationRule'],
      deprecated: json['deprecated'],
      structuredRef: json['structuredRef'],
      valueShape: json['valueShape'],
    );
  }

  final String wireId;
  final String name;
  final String type;
  final String description;
  final bool required;
  final String? synthetic;
  final bool positional;
  final String? enumType;
  final String? widgetType;
  final String? callbackSignature;
  final String? firesAs;
  final Object? defaultSource;
  final List<Object?>? mutuallyExclusiveWith;
  final String? requiresAncestor;
  final String? category;
  final String? priority;
  final Object? validationRule;
  final Object? deprecated;
  final Object? structuredRef;
  final Object? valueShape;

  Map<String, Object?> toJson() => {
        'wireId': wireId,
        'name': name,
        'type': type,
        'description': description,
        if (required) 'required': true,
        if (synthetic != null) 'synthetic': synthetic,
        if (positional) 'positional': true,
        if (enumType != null) 'enumType': enumType,
        if (widgetType != null) 'widgetType': widgetType,
        if (callbackSignature != null) 'callbackSignature': callbackSignature,
        if (firesAs != null) 'firesAs': firesAs,
        if (defaultSource != null) 'defaultSource': defaultSource,
        if (mutuallyExclusiveWith != null && mutuallyExclusiveWith!.isNotEmpty)
          'mutuallyExclusiveWith': mutuallyExclusiveWith,
        if (requiresAncestor != null) 'requiresAncestor': requiresAncestor,
        if (category != null) 'category': category,
        if (priority != null) 'priority': priority,
        if (validationRule != null) 'validationRule': validationRule,
        if (deprecated != null) 'deprecated': deprecated,
        if (structuredRef != null) 'structuredRef': structuredRef,
        if (valueShape != null) 'valueShape': valueShape,
      };
}
