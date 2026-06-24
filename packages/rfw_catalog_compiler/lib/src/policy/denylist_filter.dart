import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_compiler/src/policy/denylist_policy.dart';
import 'package:rfw_catalog_compiler/src/policy/policy_ledger.dart';

/// Pure type predicate. Stateless and depth-agnostic so it can walk
/// analyzer type structures without depending on the rest of the compiler.
final class DenylistFilter {
  const DenylistFilter._();

  /// Returns a [DenylistMatch] when [type] is denylisted by the
  /// supplied [ledger]; null otherwise.
  static DenylistMatch? match(DartType type, PolicyLedger ledger) {
    return _matchType(type, ledger, <DartType>{});
  }

  static DenylistMatch? _matchType(
    DartType type,
    PolicyLedger ledger,
    Set<DartType> seen,
  ) {
    if (!seen.add(type)) return null;

    final alias = type.alias;
    if (alias != null) {
      final aliasedType = alias.element.instantiate(
        typeArguments: alias.typeArguments,
        nullabilitySuffix: NullabilitySuffix.none,
      );
      final match = _matchType(aliasedType, ledger, seen);
      if (match != null) {
        return _within(
          match,
          'type alias ${_displayName(type)}',
        );
      }
    }

    if (type is InterfaceType) {
      final directMatch = _matchInterfaceType(type, ledger);
      if (directMatch != null) return directMatch;

      final typeName = _interfaceTypeName(type);
      for (var i = 0; i < type.typeArguments.length; i += 1) {
        final match = _matchType(type.typeArguments[i], ledger, seen);
        if (match != null) {
          return _within(match, 'type argument ${i + 1} of $typeName');
        }
      }
      return null;
    }

    if (type is FunctionType) {
      final returnMatch = _matchType(type.returnType, ledger, seen);
      if (returnMatch != null) {
        return _within(returnMatch, 'function return type');
      }

      for (final param in type.formalParameters) {
        final match = _matchType(param.type, ledger, seen);
        if (match != null) {
          final name = param.name;
          return _within(
            match,
            name == null || name.isEmpty
                ? 'function parameter'
                : 'function parameter $name',
          );
        }
      }
      return null;
    }

    if (type is RecordType) {
      for (var i = 0; i < type.positionalFields.length; i += 1) {
        final match = _matchType(type.positionalFields[i].type, ledger, seen);
        if (match != null) {
          return _within(match, 'record positional field ${i + 1}');
        }
      }
      for (final field in type.namedFields) {
        final match = _matchType(field.type, ledger, seen);
        if (match != null) {
          return _within(match, 'record field ${field.name}');
        }
      }
      return null;
    }

    if (type is TypeParameterType) {
      final bound = type.bound;
      if (bound is DynamicType) return null;
      final match = _matchType(bound, ledger, seen);
      if (match != null) {
        return _within(match, 'type parameter ${type.element.name} bound');
      }
      return null;
    }

    if (type is DynamicType ||
        type is InvalidType ||
        type is NeverType ||
        type is VoidType) {
      return null;
    }

    return null;
  }

  static DenylistMatch? _matchInterfaceType(
    InterfaceType type,
    PolicyLedger ledger,
  ) {
    final policy = ledger.denylist;
    final typeName = _interfaceTypeName(type);
    final typeFqn = _elementFqn(type.element);

    final exactTarget = policy.types.contains(typeName)
        ? typeName
        : policy.types.contains(typeFqn)
            ? typeFqn
            : null;
    if (exactTarget != null) {
      return DenylistMatch(
        policy: 'denylist.types',
        reason: 'type denylisted: $exactTarget',
        target: exactTarget,
      );
    }

    for (final suffix in policy.typeSuffixes) {
      if (typeName.endsWith(suffix) && typeName != suffix) {
        return DenylistMatch(
          policy: 'denylist.typeSuffixes',
          reason: 'type name matches denylisted suffix: '
              "'$suffix' on $typeName",
          target: typeName,
        );
      }
    }
    return null;
  }

  static DenylistMatch _within(DenylistMatch match, String context) {
    return DenylistMatch(
      policy: match.policy,
      reason: '$context contains ${match.reason}',
      target: match.target,
    );
  }

  static String _displayName(DartType type) {
    final displayName = type.getDisplayString();
    return displayName.endsWith('?') || displayName.endsWith('*')
        ? displayName.substring(0, displayName.length - 1)
        : displayName;
  }

  static String _interfaceTypeName(InterfaceType type) =>
      type.element.name ?? _displayName(type);

  static String _elementFqn(Element element) {
    final library = element.library?.identifier;
    final name = element.name;
    if (library == null || name == null) return name ?? _displayNameFallback;
    return '$library#$name';
  }

  static const String _displayNameFallback = '<unnamed>';

  /// Returns a [DenylistMatch] when [flutterTypeFqn] is denylisted as
  /// a widget; null otherwise.
  static DenylistMatch? matchWidget(
    String flutterTypeFqn,
    PolicyLedger ledger,
  ) {
    if (ledger.denylist.widgets.contains(flutterTypeFqn)) {
      return DenylistMatch(
        policy: 'denylist.widgets',
        reason: 'widget denylisted: $flutterTypeFqn',
        target: flutterTypeFqn,
      );
    }
    return null;
  }

  /// Returns a [DenylistMatch] when [propertyName] on the supplied
  /// widget flutter type is denylisted; null otherwise.
  static DenylistMatch? matchProperty(
    String flutterTypeFqn,
    String propertyName,
    PolicyLedger ledger,
  ) {
    final perWidget = ledger.denylist.properties[flutterTypeFqn];
    if (perWidget != null && perWidget.contains(propertyName)) {
      return DenylistMatch(
        policy: 'denylist.properties',
        reason: 'property denylisted: $flutterTypeFqn.$propertyName',
        target: propertyName,
      );
    }
    return null;
  }
}
