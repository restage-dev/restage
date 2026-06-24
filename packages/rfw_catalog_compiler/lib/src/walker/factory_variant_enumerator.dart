import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/ir/factory_variant_ir.dart';
import 'package:rfw_catalog_compiler/src/ir/policy_decision.dart';
import 'package:rfw_catalog_compiler/src/ir/structured_ir.dart';
import 'package:rfw_catalog_compiler/src/policy/denylist_filter.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';
import 'package:rfw_catalog_compiler/src/walker/dart_ui_doc_fallbacks.dart';
import 'package:rfw_catalog_compiler/src/walker/dartdoc.dart';
import 'package:rfw_catalog_compiler/src/walker/element_fqn.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Factory variant candidates discovered from a structured type.
@immutable
final class FactoryVariantEnumerationResult {
  /// Creates an enumeration result.
  const FactoryVariantEnumerationResult({
    required this.variants,
    required this.policyTrace,
  });

  /// Included variants in deterministic source-kind order.
  final List<FactoryVariantIR> variants;

  /// Policy decisions made while enumerating variants.
  final List<PolicyDecisionIR> policyTrace;
}

/// Enumerates the public ways to author instances of [element].
FactoryVariantEnumerationResult enumerateFactoryVariants({
  required ClassElement element,
  required List<StructuredFieldIR> fields,
  required PolicyLedger policy,
}) {
  final policyTrace = <PolicyDecisionIR>[];
  final ownerSourceType = elementFqn(element);

  final constructorVariants = <FactoryVariantIR>[];
  for (final constructor in element.constructors) {
    if (!_isEligibleConstructor(constructor)) continue;

    final target = _variantTarget(
      element,
      _constructorTargetName(constructor),
    );
    final decision = _denylistedParameterDecision(
      parameters: constructor.formalParameters,
      policy: policy,
      target: target,
    );
    if (decision != null) {
      policyTrace.add(decision);
      continue;
    }

    final argMappingResult = _argMappings(
      constructor.formalParameters,
      fields,
    );
    constructorVariants.add(
      FactoryVariantIR(
        wireId: WireId.unallocatedVariant,
        sourceKind: VariantSourceKind.constructor,
        source: constructor,
        namedConstructor: _namedConstructor(constructor),
        argMappings: argMappingResult.mappings,
        argTargetFieldNames: argMappingResult.targetFieldNames,
        description: stripDartdocSlashes(constructor.documentationComment) ??
            dartUiVariantDescription(
              ownerSourceType: ownerSourceType,
              sourceKind: VariantSourceKind.constructor,
              namedConstructor: _namedConstructor(constructor),
            ),
      ),
    );
  }
  constructorVariants.sort(_compareConstructorVariants);

  final staticMethodVariants = <FactoryVariantIR>[];
  for (final method in element.methods) {
    final name = method.name;
    if (name == null ||
        name.isEmpty ||
        !method.isStatic ||
        !method.isPublic ||
        !_returnsSelf(method.returnType, element)) {
      continue;
    }

    final decision = _denylistedParameterDecision(
      parameters: method.formalParameters,
      policy: policy,
      target: _variantTarget(element, name),
    );
    if (decision != null) {
      policyTrace.add(decision);
      continue;
    }

    final argMappingResult = _argMappings(method.formalParameters, fields);
    staticMethodVariants.add(
      FactoryVariantIR(
        wireId: WireId.unallocatedVariant,
        sourceKind: VariantSourceKind.staticMethod,
        source: method,
        staticAccessor: name,
        argMappings: argMappingResult.mappings,
        argTargetFieldNames: argMappingResult.targetFieldNames,
        description: stripDartdocSlashes(method.documentationComment) ??
            dartUiVariantDescription(
              ownerSourceType: ownerSourceType,
              sourceKind: VariantSourceKind.staticMethod,
              staticAccessor: name,
            ),
      ),
    );
  }
  staticMethodVariants.sort(_compareStaticAccessorVariants);

  final staticGetterVariants = <FactoryVariantIR>[];
  for (final getter in element.getters) {
    final name = getter.name;
    if (name == null ||
        name.isEmpty ||
        !getter.isStatic ||
        !getter.isPublic ||
        !_returnsSelf(getter.returnType, element)) {
      continue;
    }

    staticGetterVariants.add(
      FactoryVariantIR(
        wireId: WireId.unallocatedVariant,
        sourceKind: VariantSourceKind.staticGetter,
        source: getter,
        staticAccessor: name,
        description: stripDartdocSlashes(getter.documentationComment),
      ),
    );
  }
  staticGetterVariants.sort(_compareStaticAccessorVariants);

  final constValueVariants = <FactoryVariantIR>[];
  for (final field in element.fields) {
    final name = field.name;
    if (name == null ||
        name.isEmpty ||
        !field.isStatic ||
        !field.isConst ||
        !field.isPublic ||
        !_returnsSelf(field.type, element)) {
      continue;
    }

    constValueVariants.add(
      FactoryVariantIR(
        wireId: WireId.unallocatedVariant,
        sourceKind: VariantSourceKind.constValue,
        source: field,
        staticAccessor: name,
        description: stripDartdocSlashes(field.documentationComment) ??
            dartUiVariantDescription(
              ownerSourceType: ownerSourceType,
              sourceKind: VariantSourceKind.constValue,
              staticAccessor: name,
            ),
      ),
    );
  }
  constValueVariants.sort(_compareStaticAccessorVariants);

  // A static const field is surfaced by the analyzer as both a const-value
  // field and an implicit synthetic getter, so the same accessor name can
  // appear in both `element.fields` and `element.getters`. The const value is
  // the canonical accessor; drop the redundant static-getter variant of the
  // same name so the type does not carry a duplicate variant (e.g. a single
  // `zero` rather than both a staticGetter and a constValue `zero`).
  final constValueAccessorNames = {
    for (final variant in constValueVariants) variant.staticAccessor,
  };
  staticGetterVariants.removeWhere(
    (variant) => constValueAccessorNames.contains(variant.staticAccessor),
  );

  return FactoryVariantEnumerationResult(
    variants: [
      ...constructorVariants,
      ...staticMethodVariants,
      ...staticGetterVariants,
      ...constValueVariants,
    ],
    policyTrace: policyTrace,
  );
}

bool _isEligibleConstructor(ConstructorElement constructor) {
  final name = constructor.name;
  if (name != null && name.startsWith('_')) return false;
  return constructor.redirectedConstructor == null;
}

String? _namedConstructor(ConstructorElement constructor) {
  final name = constructor.name;
  if (name == null || name.isEmpty || name == 'new') return null;
  return name;
}

String _constructorTargetName(ConstructorElement constructor) =>
    _namedConstructor(constructor) ?? 'new';

String _variantTarget(ClassElement element, String memberName) {
  final className = element.name ?? '<unnamed>';
  return '$className.$memberName';
}

PolicyDecisionIR? _denylistedParameterDecision({
  required List<FormalParameterElement> parameters,
  required PolicyLedger policy,
  required String target,
}) {
  for (final parameter in parameters) {
    final match = DenylistFilter.match(parameter.type, policy);
    if (match != null) {
      return PolicyDecisionIR(
        policy: match.policy,
        decision: 'excluded',
        reason: match.reason,
        target: target,
      );
    }
  }
  return null;
}

final class _ArgMappingResult {
  const _ArgMappingResult({
    required this.mappings,
    required this.targetFieldNames,
  });

  final Map<String, ArgMapping> mappings;
  final Map<String, List<String>> targetFieldNames;
}

_ArgMappingResult _argMappings(
  List<FormalParameterElement> parameters,
  List<StructuredFieldIR> fields,
) {
  final fieldsByName = {
    for (final field in fields) field.name: field,
  };
  final mappings = <String, ArgMapping>{};
  final targetFieldNames = <String, List<String>>{};
  for (final parameter in parameters) {
    final name = parameter.name;
    if (name == null || name.isEmpty) continue;

    final matchingField = fieldsByName[name];
    if (matchingField != null) {
      mappings[name] = ArgMapping(targetFields: [matchingField.wireId]);
      targetFieldNames[name] = [matchingField.name];
      continue;
    }

    final splatTargets = _splatTargets(parameter, parameters, fields);
    if (splatTargets.isNotEmpty) {
      mappings[name] = ArgMapping(
        targetFields: [
          for (final target in splatTargets) target.wireId,
        ],
      );
      targetFieldNames[name] = [
        for (final target in splatTargets) target.name,
      ];
    }
  }
  return _ArgMappingResult(
    mappings: Map.unmodifiable(mappings),
    targetFieldNames: Map.unmodifiable(targetFieldNames),
  );
}

List<StructuredFieldIR> _splatTargets(
  FormalParameterElement parameter,
  List<FormalParameterElement> parameters,
  List<StructuredFieldIR> fields,
) {
  if (parameters.length != 1) return const [];
  final parameterType = _displayName(parameter.type);
  final targets = <StructuredFieldIR>[];
  for (final field in fields) {
    final fieldType = field.type.dartType;
    if (fieldType != null && _displayName(fieldType) == parameterType) {
      targets.add(field);
    }
  }
  return targets.length > 1 ? targets : const [];
}

bool _returnsSelf(DartType type, ClassElement element) {
  if (type is! InterfaceType) return false;
  return identical(type.element, element);
}

int _compareConstructorVariants(
  FactoryVariantIR a,
  FactoryVariantIR b,
) {
  final aName = a.namedConstructor;
  final bName = b.namedConstructor;
  if (aName == null && bName != null) return -1;
  if (aName != null && bName == null) return 1;
  return (aName ?? '').compareTo(bName ?? '');
}

int _compareStaticAccessorVariants(
  FactoryVariantIR a,
  FactoryVariantIR b,
) =>
    (a.staticAccessor ?? '').compareTo(b.staticAccessor ?? '');

String _displayName(DartType type) {
  final displayName = type.getDisplayString();
  if (displayName.endsWith('?') || displayName.endsWith('*')) {
    return displayName.substring(0, displayName.length - 1);
  }
  return displayName;
}
