import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart'
    show reconstructionVariant;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/translator_recipe.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Emits the RFW DSL map for a customer STRUCTURED VALUE — a paywall body that
/// AUTHORS a customer data-class value (`Plan(name: 'Pro', price: Price(999))`)
/// as a widget property value, the ENCODE side of this feature.
///
/// The map is derived MECHANICALLY from the type's catalog
/// [StructuredEntry.fields] — one entry per field, keyed by `field.name`. That
/// key is the SAME source the generated decoder reads (`source.v([...name])`),
/// so encode↔decode key symmetry is by construction: there is no second key
/// agreement to maintain. The value for each field is the author's constructor
/// argument, referenced via [ArgRef] derived from the resolved source
/// constructor's parameter kinds (named vs positional). Nested-structured and
/// framework-value fields recurse through [EmitFragmentArg]'s translate
/// callback (the host `_translate`), which re-enters instance-creation
/// translation for the nested value.
///
/// This is NOT the hand-authored framework-value path (`StructuredValueEmitter`
/// — `EdgeInsets`/`Border`/…): a customer plain-data class carries no hidden
/// decoder contract, so the recipe is fully derivable and never hand-written.
///
/// This collaborator owns no walk state. It is a pure function of its argument
/// node plus the catalog index and a narrow set of host primitives injected as
/// closures.
final class CustomerStructuredValueEmitter {
  /// Creates an emitter wired to the host primitives it delegates back to.
  CustomerStructuredValueEmitter({
    required StructuredEntry? Function(InstanceCreationExpression)
        structuredValueFor,
    required String Function(
      EmitFragment fragment,
      List<Expression> args,
      List<Issue> issues,
      String loc,
    ) dispatch,
    required String Function(AstNode) locationOf,
  })  : _structuredValueFor = structuredValueFor,
        _dispatch = dispatch,
        _locationOf = locationOf;

  /// Resolves the construction to the catalog [StructuredEntry] it authors, or
  /// `null` when it is not a discovered customer structured value. A
  /// lightweight source-type lookup (NOT a native-validated index) so it is
  /// safe on any merged catalog the translator may hold.
  final StructuredEntry? Function(InstanceCreationExpression)
      _structuredValueFor;
  final String Function(
    EmitFragment fragment,
    List<Expression> args,
    List<Issue> issues,
    String loc,
  ) _dispatch;
  final String Function(AstNode) _locationOf;

  /// Returns the RFW DSL map for [expr] when it constructs a discovered
  /// customer structured value, or `null` when it is NOT one — the caller then
  /// falls through to widget construction (a customer `@RestageWidget`
  /// construction), never mistaking one for the other.
  String? tryEmit(InstanceCreationExpression expr, List<Issue> issues) {
    final structured = _structuredValueFor(expr);
    if (structured == null) return null;

    final loc = _locationOf(expr);

    // The decoder always rebuilds a value through the SAME constructor the
    // catalog names as its reconstruction variant — never the constructor the
    // author actually invoked. Encoding from a DIFFERENT constructor would key
    // the wire map to fields that ctor materialises, while the decoder reads
    // it back through a ctor that may default an omitted field differently —
    // a silent wrong value, not a partial map an issue would catch. So the
    // invoked constructor must MATCH the reconstruction variant; any other
    // constructor is deferred loud, restoring encode<->decode symmetry by
    // construction rather than trusting it as an assumption.
    final invokedCtorName = expr.constructorName.name?.name;
    final reconCtorName = reconstructionVariant(structured)?.namedConstructor;
    if (invokedCtorName != reconCtorName) {
      final invoked = _qualifiedCtorName(structured, invokedCtorName);
      final canonical = _qualifiedCtorName(structured, reconCtorName);
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: '$invoked cannot be encoded: the delivered value is '
              'reconstructed through $canonical, its canonical constructor. '
              'Author a customer data-class value with its canonical '
              'constructor.',
          location: loc,
        ),
      );
      return '';
    }

    final argRefByField = _argRefByFieldName(expr);

    final entries = <EmitMapEntry>[];
    for (final field in structured.fields) {
      final argRef = argRefByField[field.name];
      if (argRef == null) {
        // The author's constructor has no parameter that materialises this
        // field. A REQUIRED field cannot be faithfully encoded (the wire would
        // omit a value the decoder needs, or a transforming/renamed ctor would
        // mis-source it) — defer the WHOLE value loudly, never a partial map.
        // An OPTIONAL field simply takes its constructor default (the decoder
        // reads the absent key as null/default), so omit the entry.
        //
        // NOTE: `field.required` is never `true` for a production customer
        // structured field (the walker's StructuredFieldIR defaults it to
        // `false` and no customer-structured lowering path stamps it) — this
        // branch is therefore dead in practice. The real fail-closed
        // protection against an unsourceable field is the admission gate
        // (customer_structured_discovery.dart's `_reconstructionObstruction` +
        // customer_structured_admissibility.dart's `_unsourceableParam`),
        // which excludes the WHOLE type before it ever reaches this emitter.
        // Kept as defense-in-depth in case that ever changes.
        if (field.required) {
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message: "${structured.name} field '${field.name}' cannot be "
                  'encoded: this constructor does not supply it by that name. '
                  'A customer data-class value must be authored with a '
                  'constructor whose parameters match its fields.',
              location: loc,
            ),
          );
          return '';
        }
        continue;
      }
      entries.add(
        EmitMapEntry(
          field.name,
          EmitFragmentArg(argRef, asLength: _isDoubleField(field.type)),
          omitWhenArgUnset: !field.required,
        ),
      );
    }

    // A NESTED structured/framework-value field recurses back through the
    // host translator (via EmitFragmentArg's translate callback), which can
    // itself defer loud (e.g. a nested value authored via a non-canonical
    // constructor) — raising an issue and returning ''. Left unchecked, that
    // '' would simply be spliced into THIS map as an empty entry
    // (`price: `), a syntactically broken partial map masquerading as a
    // successful encode. Fail closed recursively: if dispatching raised any
    // issue, the whole value is un-encodable, so defer it as a whole — never
    // a partial map.
    final issuesBefore = issues.length;
    final dispatched = _dispatch(
      EmitFragmentMap(entries),
      expr.argumentList.arguments,
      issues,
      loc,
    );
    return issues.length > issuesBefore ? '' : dispatched;
  }

  /// Maps each source constructor parameter name to the [ArgRef] that reads its
  /// author-supplied value: a named parameter by label, a positional parameter
  /// by its zero-based position among the positionals (declaration order — the
  /// same view the decode-side reconstruction plan uses).
  Map<String, ArgRef> _argRefByFieldName(InstanceCreationExpression expr) {
    final ctor = expr.constructorName.element;
    if (ctor is! ConstructorElement) return const {};
    final byName = <String, ArgRef>{};
    var positionalIndex = 0;
    for (final parameter in ctor.formalParameters) {
      final name = parameter.name;
      if (name == null || name.isEmpty) {
        if (parameter.isPositional) positionalIndex++;
        continue;
      }
      if (parameter.isNamed) {
        byName[name] = ArgRef.named(name);
      } else {
        byName[name] = ArgRef.positional(positionalIndex);
        positionalIndex++;
      }
    }
    return byName;
  }

  /// Whether a field's catalog property type decodes as a `double`
  /// (`source.v<double>`), so its encoded scalar must be coerced to a
  /// double-formatted literal (`24` → `24.0`) or the decoder silently nulls an
  /// author-written int. Mirrors the `asLength` positions the built-in
  /// structured recipes (`Offset → {x, y}`) set.
  bool _isDoubleField(PropertyType type) =>
      type == PropertyType.length || type == PropertyType.real;

  /// The author-facing name of a constructor for diagnostics: the bare type
  /// name for the unnamed constructor, or `Type.named` for a named one.
  String _qualifiedCtorName(
    StructuredEntry structured,
    String? namedConstructor,
  ) =>
      namedConstructor == null
          ? structured.name
          : '${structured.name}.$namedConstructor';
}
