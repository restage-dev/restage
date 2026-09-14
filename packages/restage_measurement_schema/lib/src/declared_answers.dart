import 'canonical.dart';

/// Declared scalar types accepted from an explicitly instrumented answer.
enum MeasurementAnswerKindV1 { category, integer, scaledDecimal }

/// Bounded, target-neutral source declaration for one authored question.
final class MeasurementDeclaredAnswerV1 extends CanonicalValue {
  MeasurementDeclaredAnswerV1.category({
    required this.questionId,
    required this.outcomeKey,
    required this.propertyName,
    required Map<String, String> categoryLabels,
  })  : kind = MeasurementAnswerKindV1.category,
        categoryLabels = Map.unmodifiable(categoryLabels),
        minimum = null,
        maximum = null,
        scale = null,
        unit = null {
    _validate();
  }

  MeasurementDeclaredAnswerV1.integer({
    required this.questionId,
    required this.outcomeKey,
    required this.propertyName,
    required String this.minimum,
    required String this.maximum,
  })  : kind = MeasurementAnswerKindV1.integer,
        categoryLabels = const {},
        scale = null,
        unit = null {
    _validate();
  }

  MeasurementDeclaredAnswerV1.scaledDecimal({
    required this.questionId,
    required this.outcomeKey,
    required this.propertyName,
    required String this.minimum,
    required String this.maximum,
    required int this.scale,
    required String this.unit,
  })  : kind = MeasurementAnswerKindV1.scaledDecimal,
        categoryLabels = const {} {
    _validate();
  }

  factory MeasurementDeclaredAnswerV1.fromJson(Map<String, Object?> json) {
    final kind = MeasurementAnswerKindV1.values
        .byName(requireCanonicalString(json['kind'], 'declaredAnswer.kind'));
    final keys = <String>{
      'questionId',
      'outcomeKey',
      'propertyName',
      'kind',
      if (kind == MeasurementAnswerKindV1.category)
        'categoryLabels'
      else ...['minimum', 'maximum'],
      if (kind == MeasurementAnswerKindV1.scaledDecimal) ...['scale', 'unit']
    };
    final reader = CanonicalObjectReader(json,
        allowedKeys: keys, requiredKeys: keys, path: 'declaredAnswer');
    final questionId = reader.string('questionId');
    final outcomeKey = reader.string('outcomeKey');
    final propertyName = reader.string('propertyName');
    return switch (kind) {
      MeasurementAnswerKindV1.category => MeasurementDeclaredAnswerV1.category(
          questionId: questionId,
          outcomeKey: outcomeKey,
          propertyName: propertyName,
          categoryLabels: reader.object('categoryLabels').map((key, value) =>
              MapEntry(key, requireCanonicalString(value, 'categoryLabel')))),
      MeasurementAnswerKindV1.integer => MeasurementDeclaredAnswerV1.integer(
          questionId: questionId,
          outcomeKey: outcomeKey,
          propertyName: propertyName,
          minimum: reader.string('minimum'),
          maximum: reader.string('maximum')),
      MeasurementAnswerKindV1.scaledDecimal =>
        MeasurementDeclaredAnswerV1.scaledDecimal(
            questionId: questionId,
            outcomeKey: outcomeKey,
            propertyName: propertyName,
            minimum: reader.string('minimum'),
            maximum: reader.string('maximum'),
            scale: reader.integer('scale'),
            unit: reader.string('unit')),
    };
  }

  final String questionId;
  final String outcomeKey;
  final String propertyName;
  final MeasurementAnswerKindV1 kind;
  final Map<String, String> categoryLabels;

  /// Inclusive canonical coefficient bounds; scaled declarations use [scale].
  final String? minimum;
  final String? maximum;
  final int? scale;
  final String? unit;

  void _validate() {
    for (final identifier in [questionId, outcomeKey, propertyName]) {
      if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(identifier)) {
        throw ArgumentError('Answer identifiers must be bounded stable names');
      }
    }
    if (kind == MeasurementAnswerKindV1.category) {
      if (categoryLabels.isEmpty ||
          categoryLabels.length > 64 ||
          categoryLabels.entries.any((entry) =>
              entry.key.isEmpty ||
              entry.key.length > 128 ||
              entry.value.isEmpty ||
              entry.value.length > 256)) {
        throw ArgumentError('Answer categories and labels must be bounded');
      }
    } else {
      final low = _integer(minimum!);
      final high = _integer(maximum!);
      if (low > high ||
          (kind == MeasurementAnswerKindV1.scaledDecimal &&
              (scale! < 0 ||
                  scale! > 18 ||
                  unit!.isEmpty ||
                  unit!.length > 128))) {
        throw ArgumentError('Answer numeric domain is invalid');
      }
    }
  }

  /// Selects only values representable exactly within the declared domain.
  MeasurementAnswerValueV1? capture(Object? raw) {
    if (raw == null) return null;
    if (kind == MeasurementAnswerKindV1.category) {
      return raw is String && categoryLabels.containsKey(raw)
          ? MeasurementCategoryAnswerV1(raw)
          : null;
    }
    try {
      final String coefficient;
      if (kind == MeasurementAnswerKindV1.integer) {
        if (raw is! int && raw is! String) return null;
        coefficient = raw.toString();
      } else {
        if (raw is! num && raw is! String) return null;
        final text = raw.toString();
        final match = RegExp(r'^(-?)([0-9]+)(?:\.([0-9]+))?$').firstMatch(text);
        if (match == null) return null;
        final fraction = match.group(3) ?? '';
        if (fraction.length > scale!) return null;
        coefficient = BigInt.parse(
                '${match.group(1)}${match.group(2)}${fraction.padRight(scale!, '0')}')
            .toString();
      }
      final value = _integer(coefficient);
      if (value < _integer(minimum!) || value > _integer(maximum!)) return null;
      return kind == MeasurementAnswerKindV1.integer
          ? MeasurementIntegerAnswerV1(coefficient)
          : MeasurementScaledAnswerV1(coefficient: coefficient, scale: scale!);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Checks a received canonical value against this exact source declaration.
  bool admits(MeasurementAnswerValueV1 value) {
    if (value.kind != kind) return false;
    if (value is MeasurementCategoryAnswerV1)
      return categoryLabels.containsKey(value.value);
    final coefficient = switch (value) {
      MeasurementIntegerAnswerV1(:final value) => value,
      MeasurementScaledAnswerV1(:final coefficient) => coefficient,
      _ => throw StateError('Unreachable answer kind'),
    };
    if (value is MeasurementScaledAnswerV1 && value.scale != scale)
      return false;
    return _integer(coefficient) >= _integer(minimum!) &&
        _integer(coefficient) <= _integer(maximum!);
  }

  @override
  Map<String, Object?> toJson() => {
        'questionId': questionId,
        'outcomeKey': outcomeKey,
        'propertyName': propertyName,
        'kind': kind.name,
        if (kind == MeasurementAnswerKindV1.category)
          'categoryLabels': categoryLabels
        else ...{'minimum': minimum, 'maximum': maximum},
        if (kind == MeasurementAnswerKindV1.scaledDecimal) ...{
          'scale': scale,
          'unit': unit
        }
      };
}

/// Closed canonical answer payload, with no arbitrary application property map.
sealed class MeasurementAnswerValueV1 extends CanonicalValue {
  const MeasurementAnswerValueV1();
  MeasurementAnswerKindV1 get kind;
  Object get outcomeValue;
  factory MeasurementAnswerValueV1.fromJson(Map<String, Object?> json) {
    final kind = MeasurementAnswerKindV1.values
        .byName(requireCanonicalString(json['kind'], 'answerValue.kind'));
    final keys = kind == MeasurementAnswerKindV1.scaledDecimal
        ? const {'kind', 'coefficient', 'scale'}
        : const {'kind', 'value'};
    final reader = CanonicalObjectReader(json,
        allowedKeys: keys, requiredKeys: keys, path: 'answerValue');
    return switch (kind) {
      MeasurementAnswerKindV1.category =>
        MeasurementCategoryAnswerV1(reader.string('value')),
      MeasurementAnswerKindV1.integer =>
        MeasurementIntegerAnswerV1(reader.string('value')),
      MeasurementAnswerKindV1.scaledDecimal => MeasurementScaledAnswerV1(
          coefficient: reader.string('coefficient'),
          scale: reader.integer('scale')),
    };
  }
}

final class MeasurementCategoryAnswerV1 extends MeasurementAnswerValueV1 {
  MeasurementCategoryAnswerV1(this.value) {
    if (value.isEmpty || value.length > 128)
      throw ArgumentError('Category answer is not bounded');
  }
  final String value;
  @override
  MeasurementAnswerKindV1 get kind => MeasurementAnswerKindV1.category;
  @override
  Object get outcomeValue => value;
  @override
  Map<String, Object?> toJson() => {'kind': kind.name, 'value': value};
}

final class MeasurementIntegerAnswerV1 extends MeasurementAnswerValueV1 {
  MeasurementIntegerAnswerV1(this.value) {
    _integer(value);
  }
  final String value;
  @override
  MeasurementAnswerKindV1 get kind => MeasurementAnswerKindV1.integer;
  @override
  Object get outcomeValue => value;
  @override
  Map<String, Object?> toJson() => {'kind': kind.name, 'value': value};
}

final class MeasurementScaledAnswerV1 extends MeasurementAnswerValueV1 {
  MeasurementScaledAnswerV1({required this.coefficient, required this.scale}) {
    _integer(coefficient);
    if (scale < 0 || scale > 18)
      throw ArgumentError('Answer scale is not bounded');
  }
  final String coefficient;
  final int scale;
  @override
  MeasurementAnswerKindV1 get kind => MeasurementAnswerKindV1.scaledDecimal;
  @override
  Object get outcomeValue => {'coefficient': coefficient, 'scale': scale};
  @override
  Map<String, Object?> toJson() =>
      {'kind': kind.name, 'coefficient': coefficient, 'scale': scale};
}

BigInt _integer(String value) {
  if (value.length > 128 || !RegExp(r'^(0|-?[1-9][0-9]*)$').hasMatch(value)) {
    throw ArgumentError(
        'Answer coefficient must be a bounded canonical integer');
  }
  return BigInt.parse(value);
}
