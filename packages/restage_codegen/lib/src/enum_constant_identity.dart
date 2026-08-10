import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

/// Canonical analyzer identity of one resolved enum constant, including its
/// exact declaration position.
typedef AnalyzerEnumConstantIdentity = ({
  String definingLibrary,
  String enumName,
  String member,
  int ordinal,
});

/// One enum constant canonicalized against an expected resolved enum type.
final class AnalyzerEnumConstant {
  /// Creates a canonical enum constant fact.
  const AnalyzerEnumConstant({
    required this.value,
    required this.element,
    required this.identity,
  });

  /// The direct enum-member value, even when the input was a const alias.
  final DartObject value;

  /// The exact enum-member element.
  final FieldElement element;

  /// Defining library, enum declaration, member, and declaration ordinal.
  final AnalyzerEnumConstantIdentity identity;
}

/// Resolves [value] to one constant of [expected] by analyzer const equality.
///
/// This deliberately does not inspect source spelling, display strings, or
/// coincidental member names. A value from another enum cannot match.
AnalyzerEnumConstant? canonicalAnalyzerEnumConstant(
  DartObject value,
  EnumElement expected,
) {
  final definingLibrary = expected.library.identifier;
  final enumName = expected.name;
  if (definingLibrary.isEmpty || enumName == null || enumName.isEmpty) {
    return null;
  }
  for (final (ordinal, candidate) in expected.constants.indexed) {
    final member = candidate.name;
    final candidateValue = candidate.computeConstantValue();
    if (member == null || member.isEmpty || candidateValue == null) continue;
    if (candidateValue != value) continue;
    return AnalyzerEnumConstant(
      value: candidateValue,
      element: candidate,
      identity: (
        definingLibrary: definingLibrary,
        enumName: enumName,
        member: member,
        ordinal: ordinal,
      ),
    );
  }
  return null;
}
