import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/recipe_dispatcher.dart';
import 'package:restage_shared/restage_shared.dart';

/// The synthetic value sentinel emitted for an asymmetric `BorderRadius`
/// (`.only` / `.vertical` / `.horizontal`). The host property-emit recognises
/// this prefix and splices the `key: value` corner list onto the per-corner
/// catalog slots; the recognition itself stays widget-agnostic. Mirrors the
/// `__rfw_interp(...)` Text-interpolation sentinel precedent.
const String _kBorderRadiusSentinelPrefix = '__rfw_border_radius_corners(';

/// Canonical corner emission order for the per-corner sentinel.
const List<String> _kBorderRadiusCornerOrder = [
  'topLeft',
  'topRight',
  'bottomLeft',
  'bottomRight',
];

/// Emits the RFW DSL fragments for structured Flutter value types — the
/// `EdgeInsets` / `Color` / `Offset` / `Border` / `ShapeBorder` / `Gradient` /
/// `BoxShadow` / `Locale` / `FontFeature` / `FontVariation` / `TextDecoration` /
/// `Alignment` family — that a paywall body references as property values.
///
/// This collaborator owns no walk state. It is a pure function of its argument
/// nodes plus a narrow set of host primitives injected as closures (the
/// back-interface). The host (`ExpressionTranslator`) constructs one of these,
/// passing tear-offs of its own private methods, and routes the matching
/// node-dispatch arms here. Output is byte-identical to the in-host emission it
/// replaces.
///
/// The injected back-interface — the 12 host primitives these emitters call
/// outward — is `translate`, `translateDoubleScalar`, `stripParens`,
/// `stringLiteral`, `frameworkOrUnresolved`, `resolveBoundIdentifier`,
/// `isResolvedNonFrameworkCtor`, `deferFrameworkConstLookalike`,
/// `deferFrameworkCtorLookalike`, `conditionalSwitch`,
/// `validateThemeValueForSlot`, and a `locationOf` provider. The closure fields
/// are named to match the host method names so the moved bodies need no
/// call-site edits.
final class StructuredValueEmitter {
  /// Creates an emitter wired to the host primitives it delegates back to.
  StructuredValueEmitter({
    required String Function(Expression, List<Issue>) translate,
    required String Function(Expression, List<Issue>) translateDoubleScalar,
    required Expression Function(Expression) stripParens,
    required String Function(String) stringLiteral,
    required bool Function(Element?) frameworkOrUnresolved,
    required Expression Function(Expression) resolveBoundIdentifier,
    required bool Function(InstanceCreationExpression)
        isResolvedNonFrameworkCtor,
    required String Function(PrefixedIdentifier, String, String, List<Issue>)
        deferFrameworkConstLookalike,
    required String Function(InstanceCreationExpression, String, List<Issue>)
        deferFrameworkCtorLookalike,
    required String Function(
      ConditionalExpression,
      List<Issue>,
      String Function(Expression),
    ) conditionalSwitch,
    required void Function(Expression, PropertyType, List<Issue>)
        validateThemeValueForSlot,
    required String Function(AstNode) locationOf,
  })  : _translate = translate,
        _translateDoubleScalar = translateDoubleScalar,
        _stripParens = stripParens,
        _stringLiteral = stringLiteral,
        _frameworkOrUnresolved = frameworkOrUnresolved,
        _resolveBoundIdentifier = resolveBoundIdentifier,
        _isResolvedNonFrameworkCtor = isResolvedNonFrameworkCtor,
        _deferFrameworkConstLookalike = deferFrameworkConstLookalike,
        _deferFrameworkCtorLookalike = deferFrameworkCtorLookalike,
        _conditionalSwitch = conditionalSwitch,
        _validateThemeValueForSlot = validateThemeValueForSlot,
        _locationOf = locationOf;

  /// Translates an arbitrary expression to its RFW DSL fragment.
  final String Function(Expression, List<Issue>) _translate;

  /// Translates an expression to an RFW scalar that strict-decodes as a
  /// `double` (an author-written `int` literal is forced to a double literal).
  final String Function(Expression, List<Issue>) _translateDoubleScalar;

  /// Strips redundant parenthesization from an expression.
  final Expression Function(Expression) _stripParens;

  /// Emits a quoted RFW string literal for a Dart string value.
  final String Function(String) _stringLiteral;

  /// Whether an element resolves to the framework (or is unresolved) — the gate
  /// for inlining a framework const/ctor vs. deferring a look-alike.
  final bool Function(Element?) _frameworkOrUnresolved;

  /// Resolves an identifier bound in the active inline scope to its expression.
  final Expression Function(Expression) _resolveBoundIdentifier;

  /// Whether a construction resolves to a non-framework (customer) ctor.
  final bool Function(InstanceCreationExpression) _isResolvedNonFrameworkCtor;

  /// Emits the deferral diagnostic for a non-framework constant look-alike.
  final String Function(PrefixedIdentifier, String, String, List<Issue>)
      _deferFrameworkConstLookalike;

  /// Emits the deferral diagnostic for a non-framework constructor look-alike.
  final String Function(InstanceCreationExpression, String, List<Issue>)
      _deferFrameworkCtorLookalike;

  /// Lowers a conditional to a native RFW `switch`, branching each arm through
  /// the supplied per-branch translator.
  final String Function(
    ConditionalExpression,
    List<Issue>,
    String Function(Expression),
  ) _conditionalSwitch;

  /// Validates a contract theme read supplied as a slot value against the
  /// slot's property type.
  final void Function(Expression, PropertyType, List<Issue>)
      _validateThemeValueForSlot;

  /// Resolves the pre-computed source location string for a node.
  final String Function(AstNode) _locationOf;

  /// Emits the four-element `[left, top, right, bottom]` RFW list for an
  /// `EdgeInsets.<method>(...)` factory. `loc` is the pre-computed source
  /// location for diagnostics.
  String edgeInsets(
    String method,
    List<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    // Translates a named arg by name; returns '0.0' if absent.
    //
    // rfw's `ArgumentDecoders.edgeInsets` reads each list slot with
    // `source.v<double>(...)`, which strict-casts the value — an int
    // literal returns null, and `Padding.padding` (which is required)
    // throws on a null decoded value. So every emitted edge value is
    // forced to a double literal regardless of whether the author wrote
    // `24` or `24.0` in source.
    String namedOrZero(String name) {
      for (final a in args) {
        if (a is NamedExpression && a.name.label.name == name) {
          return _translateDoubleScalar(a.expression, issues);
        }
      }
      return '0.0';
    }

    // Collects positional (non-named) args.
    List<Expression> positional() =>
        args.where((a) => a is! NamedExpression).toList();

    switch (method) {
      case 'all':
        final pos = positional();
        if (pos.isEmpty) {
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message: 'EdgeInsets.all() requires one positional argument.',
              location: loc,
            ),
          );
          return '[0.0, 0.0, 0.0, 0.0]';
        }
        final v = _translateDoubleScalar(pos.first, issues);
        return '[$v, $v, $v, $v]';
      case 'symmetric':
        final h = namedOrZero('horizontal');
        final v = namedOrZero('vertical');
        return '[$h, $v, $h, $v]';
      case 'fromLTRB':
        final pos = positional();
        if (pos.length != 4) {
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message:
                  'EdgeInsets.fromLTRB() requires four positional arguments.',
              location: loc,
            ),
          );
          return '[0.0, 0.0, 0.0, 0.0]';
        }
        final l = _translateDoubleScalar(pos[0], issues);
        final t = _translateDoubleScalar(pos[1], issues);
        final r = _translateDoubleScalar(pos[2], issues);
        final b = _translateDoubleScalar(pos[3], issues);
        return '[$l, $t, $r, $b]';
      case 'only':
        final l = namedOrZero('left');
        final t = namedOrZero('top');
        final r = namedOrZero('right');
        final b = namedOrZero('bottom');
        return '[$l, $t, $r, $b]';
      default:
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'Unsupported EdgeInsets factory: EdgeInsets.$method. '
                'Supported: all, symmetric, fromLTRB, only.',
            location: loc,
          ),
        );
        return '[0.0, 0.0, 0.0, 0.0]';
    }
  }

  /// `BorderRadius.circular(<radius>)` / `.all(Radius.circular(<radius>))`
  /// flatten to the inner radius expression (the uniform `borderRadius`
  /// slot). The asymmetric `.only` / `.vertical` / `.horizontal` factories
  /// lower to the per-corner sentinel [_kBorderRadiusSentinelPrefix] — a
  /// `key: value` list of only the corners the author set, each value a
  /// double literal — which the host property-emit splices onto the
  /// per-corner catalog slots (`borderRadiusTopLeft` …
  /// `borderRadiusBottomRight`, omitted corners defaulting to `Radius.zero` at
  /// reconstruction). Each
  /// corner must be a framework `Radius.circular(N)` with a statically
  /// extractable, finite radius; ANY elliptical / non-static / non-circular
  /// corner defers the WHOLE value loudly (carry-all-or-defer) — never a
  /// partial or wrong emit.
  String borderRadius(
    String method,
    List<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    switch (method) {
      case 'circular':
        return _borderRadiusCircular(args, issues, loc);
      case 'all':
        return _borderRadiusAll(args, issues, loc);
      case 'only':
      case 'vertical':
      case 'horizontal':
        return _borderRadiusPerCorner(method, args, issues, loc);
      default:
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'Unsupported BorderRadius factory: BorderRadius.$method. '
                'Supported: circular, all, only, vertical, horizontal.',
            location: loc,
          ),
        );
        return '0';
    }
  }

  /// `BorderRadius.circular(<radius>)` → the bare inner radius (the uniform
  /// `borderRadius` slot's own `_coerceForPropertyType(real, …)` doubles a
  /// constant). A conditional radius must coerce PER BRANCH here — the
  /// string-level coercion cannot reach inside a `switch`'s arms (a bare-int
  /// branch would otherwise be silently nulled by `v<double>`).
  String _borderRadiusCircular(
    List<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    final positional = args.where((a) => a is! NamedExpression).toList();
    if (positional.length != 1) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'BorderRadius.circular() requires one positional argument.',
          location: loc,
        ),
      );
      return '0';
    }
    return _radiusScalarDsl(positional.first, issues);
  }

  /// The radius scalar DSL of a positional radius argument: a conditional
  /// coerces PER BRANCH (the slot's string-level `_coerceForPropertyType`
  /// cannot reach inside a `switch`'s arms — a bare-int branch would be
  /// silently nulled by `v<double>`), a bare radius lowers directly. Shared by
  /// the uniform `.circular` arm and the per-corner `Radius.circular`
  /// extraction so the per-branch coercion subtlety lives in one place.
  String _radiusScalarDsl(Expression radius, List<Issue> sink) {
    final stripped = _stripParens(radius);
    if (stripped is ConditionalExpression) {
      return _conditionalSwitch(
        stripped,
        sink,
        (branch) => _translateDoubleScalar(branch, sink),
      );
    }
    return _translate(radius, sink);
  }

  /// `BorderRadius.all(Radius.circular(<radius>))` is semantically the uniform
  /// `.circular` form, so it returns the bare inner radius onto the uniform
  /// `borderRadius` slot. A non-circular (`Radius.elliptical`, `Radius.zero`,
  /// non-static) radius is not representable as a uniform scalar → loud defer.
  String _borderRadiusAll(
    List<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    final positional = args.where((a) => a is! NamedExpression).toList();
    final scalar =
        positional.length == 1 ? _radiusCircularScalar(positional.first) : null;
    if (scalar == null) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'BorderRadius.all(...) supports a single '
              'Radius.circular(...) radius only; an elliptical, non-static, '
              'or otherwise unsupported radius is not representable.',
          location: loc,
        ),
      );
      return '0';
    }
    return scalar;
  }

  /// Lowers `BorderRadius.only/.vertical/.horizontal` to the per-corner
  /// sentinel: only the corners the author set, in canonical
  /// topLeft/topRight/bottomLeft/bottomRight order, each value coerced to a
  /// double literal. Carry-all-or-defer: any corner that is not a framework
  /// `Radius.circular(<finite, extractable>)` defers the whole value loudly.
  String _borderRadiusPerCorner(
    String method,
    List<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    Expression? named(String name) {
      for (final a in args) {
        if (a is NamedExpression && a.name.label.name == name) {
          return a.expression;
        }
      }
      return null;
    }

    final corners = <String, Expression>{};
    void set(String corner, Expression? e) {
      if (e != null) corners[corner] = e;
    }

    switch (method) {
      case 'only':
        set('topLeft', named('topLeft'));
        set('topRight', named('topRight'));
        set('bottomLeft', named('bottomLeft'));
        set('bottomRight', named('bottomRight'));
      case 'vertical':
        final top = named('top');
        final bottom = named('bottom');
        set('topLeft', top);
        set('topRight', top);
        set('bottomLeft', bottom);
        set('bottomRight', bottom);
      case 'horizontal':
        final left = named('left');
        final right = named('right');
        set('topLeft', left);
        set('bottomLeft', left);
        set('topRight', right);
        set('bottomRight', right);
    }

    final parts = <String>[];
    for (final corner in _kBorderRadiusCornerOrder) {
      final radius = corners[corner];
      if (radius == null) continue;
      final scalar = _radiusCircularScalar(radius);
      if (scalar == null) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'BorderRadius.$method(...) supports statically '
                'extractable Radius.circular(...) corners only; an elliptical, '
                'non-static, or otherwise unsupported corner radius defers the '
                'whole value.',
            location: loc,
          ),
        );
        return '0';
      }
      parts.add('$corner: ${asDoubleLiteral(scalar)}');
    }
    return '$_kBorderRadiusSentinelPrefix${parts.join(', ')})';
  }

  /// The bare radius DSL of a framework `Radius.circular(<radius>)` corner, or
  /// `null` for any non-circular / non-static / customer-look-alike / value-
  /// error corner (the caller then defers the whole borderRadius loudly). A
  /// conditional radius coerces per branch, mirroring [_borderRadiusCircular].
  /// Returned bare (non-conditional) or per-branch-doubled (conditional) — the
  /// caller applies [asDoubleLiteral] for the per-corner sentinel.
  ///
  /// Handles both AST shapes a `Radius.circular(...)` corner presents: a
  /// resolved `InstanceCreationExpression` (production) and an unresolved
  /// `MethodInvocation` (a synthetic-test input parses the static call before
  /// the analyzer resolves it to a constructor). A resolved CUSTOMER `Radius`
  /// look-alike defers either way (a value-substitution the floor can't catch).
  String? _radiusCircularScalar(Expression radiusExpr) {
    final stripped = _stripParens(radiusExpr);
    final String className;
    final String? ctorName;
    final List<Expression> arguments;
    if (stripped is InstanceCreationExpression) {
      if (_isResolvedNonFrameworkCtor(stripped)) return null;
      final identity = _ctorIdentity(stripped);
      className = identity.$1;
      ctorName = identity.$2;
      arguments = stripped.argumentList.arguments;
    } else if (stripped is MethodInvocation) {
      final target = stripped.target;
      if (target is! SimpleIdentifier) return null;
      if (!_frameworkOrUnresolved(target.element)) return null;
      className = target.name;
      ctorName = stripped.methodName.name;
      arguments = stripped.argumentList.arguments;
    } else {
      return null;
    }
    if (className != 'Radius' || ctorName != 'circular') return null;
    final positional = arguments.where((a) => a is! NamedExpression).toList();
    if (positional.length != 1) return null;
    // Extract against a scratch sink: a non-finite / unresolvable radius adds a
    // non-informational issue here, which the caller turns into a single
    // carry-all-or-defer diagnostic rather than a partial emit.
    final scratch = <Issue>[];
    final dsl = _radiusScalarDsl(positional.first, scratch);
    if (dsl.isEmpty || scratch.any((i) => !i.code.isInformational)) return null;
    return dsl;
  }

  /// The `(className, constructorName)` of an instance creation, resolving the
  /// analyzer's const-named-factory shift (where the class name lands on the
  /// import-prefix slot and the factory name on the type-name slot).
  (String, String?) _ctorIdentity(InstanceCreationExpression expr) {
    final typeName = expr.constructorName.type.name.lexeme;
    final named = expr.constructorName.name?.name;
    final prefix = expr.constructorName.type.importPrefix?.name.lexeme;
    if (named == null && prefix != null) {
      return (prefix, typeName);
    }
    return (typeName, named);
  }

  /// Structured-type translators (LinearGradient, Border, BoxShadow, …)
  /// emit only the keys the author set. Decoders on the rfw side
  /// reapply Flutter's own defaults for omitted keys, so the wire
  /// format stays compact and the catalog stays single-source-of-truth.
  String linearGradient(
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    final parts = <String>['type: "linear"'];
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      switch (name) {
        case 'begin':
        case 'end':
          parts.add('$name: ${alignmentGeometry(a.expression, issues, loc)}');
        case 'colors':
          parts.add('$name: ${_translate(a.expression, issues)}');
        case 'stops':
          // `stops` decodes as `list<double>`, so coerce int elements to
          // double literals (the scalar slots already coerce via
          // `asDoubleLiteral`); `colors` are int ARGB values and stay as-is.
          final stopsDsl = emitDoubleList(
            a.expression,
            _translate,
            _translateDoubleScalar,
            issues,
          );
          parts.add('$name: $stopsDsl');
        case 'tileMode':
        case 'transform':
        case 'colorMode':
          _deferredArg('LinearGradient', name, issues, loc);
        default:
          _unknownNamedArg(
            'LinearGradient',
            name,
            'begin, end, colors, stops',
            issues,
            loc,
          );
      }
    }
    return '{${parts.join(', ')}}';
  }

  /// `Border.all(color:, width:)` collapses to a single-side list
  /// `[<sideMap>]`; rfw's `border` decoder fills the remaining three
  /// sides identically from the first entry.
  String borderAll(
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    String? colorDsl;
    String? widthDsl;
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      switch (name) {
        case 'color':
          // Validate before translating so a coalesced `??` fallback in this
          // hand-authored structured field is kind-checked and recorded as
          // validated (see [_translateCoalesce]).
          _validateThemeValueForSlot(a.expression, PropertyType.color, issues);
          colorDsl = _translate(a.expression, issues);
        case 'width':
          _validateThemeValueForSlot(a.expression, PropertyType.length, issues);
          widthDsl = _translateDoubleScalar(a.expression, issues);
        case 'style':
        case 'strokeAlign':
          _deferredArg('Border.all', name, issues, loc);
        default:
          _unknownNamedArg('Border.all', name, 'color, width', issues, loc);
      }
    }
    return '[${_borderSideMap(colorDsl, widthDsl)}]';
  }

  /// `Border(top:, right:, bottom:, left:)` emits a 4-element list in
  /// rfw's start/top/end/bottom order. Unset sides serialise as a
  /// `BorderSide.none` map so rfw's border decoder doesn't fall back
  /// to the start-side value for omitted positions. `left` maps to
  /// `start` and `right` to `end` (LTR-correct; the host's
  /// `TextDirection` swaps them at render time).
  String borderDefault(
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    String? top;
    String? right;
    String? bottom;
    String? left;
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      // Route each side through `_borderSideExpression` (not the generic
      // `_translate`): it special-cases `BorderSide.none` to the framework
      // none-map and resolves a bound `final` local through to it, look-alike
      // -gated. Without it a recognised `BorderSide.none` would emit the bare
      // member name `"none"`, which rfw's borderSide decoder ignores (it is not
      // a map) — silently inheriting the start side, a value-wrong shape the
      // catalog floor cannot catch. A `BorderSide(...)` construction still
      // lowers via the helper's `_translate` fall-through. Mirrors the
      // `RoundedRectangleBorder(side:)` arms.
      final value = _borderSideExpression(a.expression, issues);
      switch (name) {
        case 'top':
          top = value;
        case 'right':
          right = value;
        case 'bottom':
          bottom = value;
        case 'left':
          left = value;
        default:
          _unknownNamedArg(
            'Border',
            name,
            'top, right, bottom, left',
            issues,
            loc,
          );
      }
    }
    const none = '{width: 0.0, style: "none"}';
    return '[${left ?? none}, ${top ?? none}, '
        '${right ?? none}, ${bottom ?? none}]';
  }

  /// `BorderSide(color:, width:, style:)` emits the rfw map shape.
  String borderSide(
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    String? colorDsl;
    String? widthDsl;
    String? styleDsl;
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      switch (name) {
        case 'color':
          // Validate before translating so a coalesced `??` fallback in this
          // hand-authored structured field is kind-checked and recorded as
          // validated (see [_translateCoalesce]).
          _validateThemeValueForSlot(a.expression, PropertyType.color, issues);
          colorDsl = _translate(a.expression, issues);
        case 'width':
          _validateThemeValueForSlot(a.expression, PropertyType.length, issues);
          widthDsl = _translateDoubleScalar(a.expression, issues);
        case 'style':
          // `BorderStyle.solid` / `BorderStyle.none` — emit the bare
          // member name as a DSL string so rfw's enumValue decoder
          // picks it up. Any other expression is an authoring error
          // worth surfacing rather than threading through `_translate`,
          // which would produce a DSL fragment the decoder rejects.
          final e = a.expression;
          if (e is PrefixedIdentifier && e.prefix.name == 'BorderStyle') {
            // Nested name-only gate: a resolved customer class named
            // `BorderStyle` must not emit a framework enum-string inside the
            // hand-authored BorderSide map. Defer the whole BorderSide helper
            // rather than leaving a nested bare string behind.
            if (!_frameworkOrUnresolved(e.prefix.element)) {
              return _deferFrameworkConstLookalike(
                e,
                'BorderStyle',
                e.identifier.name,
                issues,
              );
            }
            styleDsl = '"${e.identifier.name}"';
          } else {
            issues.add(
              Issue(
                code: IssueCode.unrecognizedMethodCall,
                message: 'BorderSide.style must be a BorderStyle member '
                    '(solid or none). Got: ${e.toSource()}.',
                location: loc,
              ),
            );
          }
        case 'strokeAlign':
          _deferredArg('BorderSide', name, issues, loc);
        default:
          _unknownNamedArg(
            'BorderSide',
            name,
            'color, width, style',
            issues,
            loc,
          );
      }
    }
    return _borderSideMap(colorDsl, widthDsl, styleDsl: styleDsl);
  }

  /// Assembles a BorderSide map fragment with the given parts. Each
  /// argument is null-coalesced via the rfw decoder's own defaults at
  /// runtime, so omit unset fields rather than emitting placeholders.
  String _borderSideMap(
    String? colorDsl,
    String? widthDsl, {
    String? styleDsl,
  }) {
    final parts = <String>[];
    if (colorDsl != null) parts.add('color: $colorDsl');
    if (widthDsl != null) parts.add('width: $widthDsl');
    if (styleDsl != null) parts.add('style: $styleDsl');
    return '{${parts.join(', ')}}';
  }

  /// Emits the RFW DSL map for a `ShapeBorder` construction (rounded/stadium/
  /// circle/beveled/continuous rectangle, `OutlinedBorder`, `LinearBorder`,
  /// `StarBorder`), or `null` when the construction is not a recognized shape.
  String? shapeBorder({
    required String? prefix,
    required String typeName,
    required String? constructorName,
    required NodeList<Expression> args,
    required List<Issue> issues,
    required String loc,
  }) {
    final shapeType =
        prefix != null && constructorName == null ? prefix : typeName;
    final variant =
        prefix != null && constructorName == null ? typeName : constructorName;
    final before = issues.length;

    String done(String value) => issues.length == before ? value : '';

    switch (shapeType) {
      case 'RoundedRectangleBorder':
        if (variant != null) return null;
        return done(
          _outlinedShape(
            wireType: 'rounded',
            args: args,
            issues: issues,
            loc: loc,
            supportsBorderRadius: true,
            supported: 'side, borderRadius',
          ),
        );
      case 'RoundedSuperellipseBorder':
        if (variant != null) return null;
        return done(
          _outlinedShape(
            wireType: 'roundedSuperellipse',
            args: args,
            issues: issues,
            loc: loc,
            supportsBorderRadius: true,
            supported: 'side, borderRadius',
          ),
        );
      case 'CircleBorder':
        if (variant != null) return null;
        return done(
          _outlinedShape(
            wireType: 'circle',
            args: args,
            issues: issues,
            loc: loc,
            numericFields: const {'eccentricity'},
            supported: 'side, eccentricity',
          ),
        );
      case 'StadiumBorder':
        if (variant != null) return null;
        return done(
          _outlinedShape(
            wireType: 'stadium',
            args: args,
            issues: issues,
            loc: loc,
            supported: 'side',
          ),
        );
      case 'ContinuousRectangleBorder':
        if (variant != null) return null;
        return done(
          _outlinedShape(
            wireType: 'continuous',
            args: args,
            issues: issues,
            loc: loc,
            supportsBorderRadius: true,
            supported: 'side, borderRadius',
          ),
        );
      case 'BeveledRectangleBorder':
        if (variant != null) return null;
        return done(
          _outlinedShape(
            wireType: 'beveled',
            args: args,
            issues: issues,
            loc: loc,
            supportsBorderRadius: true,
            supported: 'side, borderRadius',
          ),
        );
      case 'LinearBorder':
        return done(
          _linearBorder(variant, args, issues, loc),
        );
      case 'StarBorder':
        return done(
          _starBorder(variant, args, issues, loc),
        );
    }
    return null;
  }

  String _outlinedShape({
    required String wireType,
    required NodeList<Expression> args,
    required List<Issue> issues,
    required String loc,
    required String supported,
    bool supportsBorderRadius = false,
    Set<String> numericFields = const {},
  }) {
    final parts = <String>['type: "$wireType"'];
    for (final a in args) {
      if (a is! NamedExpression) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'ShapeBorder constructors only support named arguments.',
            location: loc,
          ),
        );
        continue;
      }
      final name = a.name.label.name;
      switch (name) {
        case 'side':
          parts.add('side: ${_borderSideExpression(a.expression, issues)}');
        case 'borderRadius':
          if (supportsBorderRadius) {
            parts.add(
              'borderRadius: '
              '${_translateDoubleScalar(a.expression, issues)}',
            );
          } else {
            _unknownNamedArg(wireType, name, supported, issues, loc);
          }
        default:
          if (numericFields.contains(name)) {
            parts.add(_doubleShapePart(name, a.expression, issues));
          } else {
            _unknownNamedArg(wireType, name, supported, issues, loc);
          }
      }
    }
    return _shapeMap(parts);
  }

  String _linearBorder(
    String? variant,
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    const edgeNames = {'start', 'end', 'top', 'bottom'};
    if (edgeNames.contains(variant)) {
      final parts = <String>['type: "linear"'];
      String? side;
      String? size;
      String? alignment;
      for (final a in args.whereType<NamedExpression>()) {
        final name = a.name.label.name;
        switch (name) {
          case 'side':
            side = _borderSideExpression(a.expression, issues);
          case 'size':
            size = _translateDoubleScalar(a.expression, issues);
          case 'alignment':
            alignment = _translateDoubleScalar(a.expression, issues);
          default:
            _unknownNamedArg(
              'LinearBorder.$variant',
              name,
              'side, size, alignment',
              issues,
              loc,
            );
        }
      }
      if (side != null) parts.add('side: $side');
      parts.add(
        '$variant: ${_linearBorderEdgeMap(size: size, alignment: alignment)}',
      );
      return _shapeMap(parts);
    }
    if (variant != null) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Unsupported LinearBorder factory: LinearBorder.$variant. '
              'Supported: default, start, end, top, bottom.',
          location: loc,
        ),
      );
      return '';
    }

    final parts = <String>['type: "linear"'];
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      switch (name) {
        case 'side':
          parts.add('side: ${_borderSideExpression(a.expression, issues)}');
        case 'start':
        case 'end':
        case 'top':
        case 'bottom':
          parts.add('$name: ${_linearBorderEdge(a.expression, issues, loc)}');
        default:
          _unknownNamedArg(
            'LinearBorder',
            name,
            'side, start, end, top, bottom',
            issues,
            loc,
          );
      }
    }
    return _shapeMap(parts);
  }

  String _linearBorderEdge(
    Expression rawExpr,
    List<Issue> issues,
    String loc,
  ) {
    // Gate at the mechanism: this helper dispatches on the raw expr's SHAPE
    // (the `LinearBorderEdge(...)` ctor) and diagnoses directly (no
    // `_translate` fallback), so a named-intermediate binding (a helper param /
    // `final` local) bound to a `LinearBorderEdge` must be resolved-through
    // here or it over-claims (classifier inlinable, translator an
    // `unrecognizedMethodCall`). Inert outside an inline. Mirrors
    // `alignmentGeometry`.
    final expr = _resolveBoundIdentifier(rawExpr);
    NodeList<Expression>? args;
    if (expr is InstanceCreationExpression) {
      final typeName = expr.constructorName.type.name.lexeme;
      if (typeName == 'LinearBorderEdge' && expr.constructorName.name == null) {
        if (_isResolvedNonFrameworkCtor(expr)) {
          return _deferFrameworkCtorLookalike(
            expr,
            'LinearBorderEdge',
            issues,
          );
        }
        args = expr.argumentList.arguments;
      }
    } else if (expr is MethodInvocation &&
        expr.target == null &&
        expr.methodName.name == 'LinearBorderEdge') {
      args = expr.argumentList.arguments;
    }
    if (args == null) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'LinearBorder edge values must be LinearBorderEdge(...).',
          location: loc,
        ),
      );
      return '{}';
    }
    String? size;
    String? alignment;
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      switch (name) {
        case 'size':
          size = _translateDoubleScalar(a.expression, issues);
        case 'alignment':
          alignment = _translateDoubleScalar(a.expression, issues);
        default:
          _unknownNamedArg(
            'LinearBorderEdge',
            name,
            'size, alignment',
            issues,
            loc,
          );
      }
    }
    return _linearBorderEdgeMap(size: size, alignment: alignment);
  }

  String _linearBorderEdgeMap({String? size, String? alignment}) {
    final parts = <String>[];
    if (size != null) parts.add('size: $size');
    if (alignment != null) parts.add('alignment: $alignment');
    return '{${parts.join(', ')}}';
  }

  String _starBorder(
    String? variant,
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    final polygon = variant == 'polygon';
    if (variant != null && !polygon) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Unsupported StarBorder factory: StarBorder.$variant. '
              'Supported: default and polygon.',
          location: loc,
        ),
      );
      return '';
    }
    final parts = <String>['type: "${polygon ? 'polygon' : 'star'}"'];
    final supported = polygon
        ? 'side, sides, pointRounding, rotation, squash'
        : 'side, points, innerRadiusRatio, pointRounding, valleyRounding, '
            'rotation, squash';
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      switch (name) {
        case 'side':
          parts.add('side: ${_borderSideExpression(a.expression, issues)}');
        case 'sides':
          if (polygon) {
            parts.add(_doubleShapePart('sides', a.expression, issues));
          } else {
            _unknownNamedArg('StarBorder', name, supported, issues, loc);
          }
        case 'points':
        case 'innerRadiusRatio':
        case 'valleyRounding':
          if (!polygon) {
            parts.add(_doubleShapePart(name, a.expression, issues));
          } else {
            _unknownNamedArg(
              'StarBorder.polygon',
              name,
              supported,
              issues,
              loc,
            );
          }
        case 'pointRounding':
        case 'rotation':
        case 'squash':
          parts.add(_doubleShapePart(name, a.expression, issues));
        default:
          _unknownNamedArg(
            polygon ? 'StarBorder.polygon' : 'StarBorder',
            name,
            supported,
            issues,
            loc,
          );
      }
    }
    return _shapeMap(parts);
  }

  String _borderSideExpression(Expression rawExpr, List<Issue> issues) {
    // Gate at the mechanism: this helper dispatches on the raw expr's SHAPE
    // (the `BorderSide.none` special-case), so a named-intermediate binding (a
    // helper param / `final` local) bound to `BorderSide.none` must be
    // resolved-through here — otherwise it falls to `_translate`, which emits
    // the bare member-name `"none"` the shape decoder cannot read. Inert
    // outside an inline (empty maps). Mirrors `alignmentGeometry`.
    final expr = _resolveBoundIdentifier(rawExpr);
    if (expr is PrefixedIdentifier &&
        expr.prefix.name == 'BorderSide' &&
        expr.identifier.name == 'none') {
      // Nested name-only gate: `BorderSide.none` inside a real shape border is
      // lowered to the framework none-map by NAME. A resolved customer class
      // named `BorderSide` must NOT name-match — defer with a diagnostic rather
      // than emit the framework map (a value-substitution silent-wrong); an
      // unresolved prefix keeps the name path (the synthetic-test affordance).
      if (!_frameworkOrUnresolved(expr.prefix.element)) {
        return _deferFrameworkConstLookalike(
          expr,
          'BorderSide',
          expr.identifier.name,
          issues,
        );
      }
      return '{width: 0.0, style: "none"}';
    }
    return _translate(expr, issues);
  }

  String _doubleShapePart(
    String name,
    Expression expr,
    List<Issue> issues,
  ) =>
      '$name: ${_translateDoubleScalar(expr, issues)}';

  String _shapeMap(List<String> parts) => '{${parts.join(', ')}}';

  /// `BoxShadow(color:, offset:, blurRadius:, spreadRadius:)` emits
  /// the rfw map shape consumed by `ArgumentDecoders.boxShadow`.
  String boxShadow(
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    final parts = <String>[];
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      switch (name) {
        case 'color':
        case 'offset':
          parts.add('$name: ${_translate(a.expression, issues)}');
        case 'blurRadius':
        case 'spreadRadius':
          parts.add(
            '$name: ${_translateDoubleScalar(a.expression, issues)}',
          );
        case 'blurStyle':
          _deferredArg('BoxShadow', name, issues, loc);
        default:
          _unknownNamedArg(
            'BoxShadow',
            name,
            'color, offset, blurRadius, spreadRadius',
            issues,
            loc,
          );
      }
    }
    return '{${parts.join(', ')}}';
  }

  /// Emits the RFW DSL for a cascade expression — the supported case is a
  /// `Paint()..color = ...` cascade, lowered to a `Paint` value map.
  String cascadeExpression(CascadeExpression expr, List<Issue> issues) {
    if (_isPaintCreation(expr.target)) {
      return _paintCascade(expr, issues, _locationOf(expr)) ?? '';
    }
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: 'Unsupported cascade expression: ${expr.toSource()}.',
        location: _locationOf(expr),
      ),
    );
    return '';
  }

  bool _isPaintCreation(Expression expr) {
    if (expr is InstanceCreationExpression) {
      return expr.constructorName.type.name.lexeme == 'Paint' &&
          expr.constructorName.name == null;
    }
    if (expr is MethodInvocation) {
      return expr.target == null && expr.methodName.name == 'Paint';
    }
    return false;
  }

  String? _paintCascade(
    CascadeExpression expr,
    List<Issue> issues,
    String loc,
  ) {
    final parts = <String>[];
    var unsupported = false;
    for (final section in expr.cascadeSections) {
      if (section is! AssignmentExpression || section.operator.lexeme != '=') {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'Unsupported Paint cascade section: '
                '${section.toSource()}.',
            location: loc,
          ),
        );
        unsupported = true;
        continue;
      }
      final name = _assignmentPropertyName(section.leftHandSide);
      if (name == null) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'Unsupported Paint cascade target: '
                '${section.leftHandSide.toSource()}.',
            location: loc,
          ),
        );
        unsupported = true;
        continue;
      }
      switch (name) {
        case 'color':
        case 'blendMode':
        case 'filterQuality':
        case 'isAntiAlias':
          final before = issues.length;
          final value = _translate(section.rightHandSide, issues);
          if (issues.length == before) parts.add('$name: $value');
        default:
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message: 'Paint.$name is not supported.',
              location: loc,
            ),
          );
          unsupported = true;
      }
    }
    if (unsupported) return null;
    return '{${parts.join(', ')}}';
  }

  String? _assignmentPropertyName(Expression expr) {
    if (expr is SimpleIdentifier) return expr.name;
    if (expr is PrefixedIdentifier) return expr.identifier.name;
    if (expr is PropertyAccess) return expr.propertyName.name;
    return null;
  }

  /// Emits the RFW DSL map for a `Locale(...)` / `Locale.fromSubtags(...)`
  /// construction.
  String locale(
    String? constructorName,
    List<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    String? languageCode;
    String? scriptCode;
    String? countryCode;
    if (constructorName == null) {
      final positional = _positionalArgs(args);
      if (positional.length != 1 && positional.length != 2) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'Locale() requires languageCode and optional countryCode.',
            location: loc,
          ),
        );
        return '""';
      }
      languageCode = _stringValue(positional[0]);
      if (positional.length == 2) countryCode = _stringValue(positional[1]);
    } else if (constructorName == 'fromSubtags') {
      final named = _namedArgs(args);
      languageCode = _stringValue(named['languageCode']);
      scriptCode = _stringValue(named['scriptCode']);
      countryCode = _stringValue(named['countryCode']);
    } else {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Unsupported Locale constructor: Locale.$constructorName.',
          location: loc,
        ),
      );
      return '""';
    }

    if (languageCode == null || languageCode.isEmpty) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Locale requires a string languageCode.',
          location: loc,
        ),
      );
      return '""';
    }
    final subtags = [
      languageCode,
      if (scriptCode != null && scriptCode.isNotEmpty) scriptCode,
      if (countryCode != null && countryCode.isNotEmpty) countryCode,
    ];
    return _stringLiteral(subtags.join('-'));
  }

  /// Emits the RFW DSL map for a `Shadow(...)` construction.
  String shadow(NodeList<Expression> args, List<Issue> issues, String loc) {
    final parts = <String>[];
    for (final a in args.whereType<NamedExpression>()) {
      final name = a.name.label.name;
      switch (name) {
        case 'color':
        case 'offset':
          parts.add('$name: ${_translate(a.expression, issues)}');
        case 'blurRadius':
          parts.add(
            '$name: ${_translateDoubleScalar(a.expression, issues)}',
          );
        default:
          _unknownNamedArg(
            'Shadow',
            name,
            'color, offset, blurRadius',
            issues,
            loc,
          );
      }
    }
    return '{${parts.join(', ')}}';
  }

  /// Emits the RFW DSL map for a `FontFeature(...)` construction.
  String fontFeature(
    String? constructorName,
    List<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    final positional = _positionalArgs(args);
    if (constructorName == 'enable' || constructorName == 'disable') {
      if (positional.length != 1) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: 'FontFeature.$constructorName() requires one string '
                'feature argument.',
            location: loc,
          ),
        );
        return '{}';
      }
      final feature = _stringValue(positional.first);
      if (feature == null) {
        _stringArgIssue('FontFeature.$constructorName', issues, loc);
        return '{}';
      }
      final value = constructorName == 'enable' ? '1' : '0';
      return '{feature: ${_stringLiteral(feature)}, value: $value}';
    }
    if (constructorName != null) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'Unsupported FontFeature constructor: '
              'FontFeature.$constructorName.',
          location: loc,
        ),
      );
      return '{}';
    }
    if (positional.length != 1 && positional.length != 2) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'FontFeature() requires feature and optional value.',
          location: loc,
        ),
      );
      return '{}';
    }
    final feature = _stringValue(positional.first);
    if (feature == null) {
      _stringArgIssue('FontFeature', issues, loc);
      return '{}';
    }
    final value =
        positional.length == 2 ? _translate(positional[1], issues) : '1';
    return '{feature: ${_stringLiteral(feature)}, value: $value}';
  }

  /// Emits the RFW DSL map for a `FontVariation(...)` construction.
  String fontVariation(
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    final positional = _positionalArgs(args);
    if (positional.length != 2) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'FontVariation() requires axis and value arguments.',
          location: loc,
        ),
      );
      return '{}';
    }
    final axis = _stringValue(positional.first);
    if (axis == null) {
      _stringArgIssue('FontVariation', issues, loc);
      return '{}';
    }
    final value = _translateDoubleScalar(positional[1], issues);
    return '{axis: ${_stringLiteral(axis)}, value: $value}';
  }

  /// Emits the RFW DSL for a `TextDecoration.combine([...])` call — the
  /// merged-decoration value.
  String textDecorationCombine(
    NodeList<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    final positional = _positionalArgs(args);
    if (positional.length != 1) {
      issues.add(
        Issue(
          code: IssueCode.unrecognizedMethodCall,
          message: 'TextDecoration.combine() requires one list argument.',
          location: loc,
        ),
      );
      return '[]';
    }
    return _translate(positional.first, issues);
  }

  List<Expression> _positionalArgs(Iterable<Expression> args) =>
      args.where((a) => a is! NamedExpression).toList();

  Map<String, Expression> _namedArgs(Iterable<Expression> args) => {
        for (final a in args.whereType<NamedExpression>())
          a.name.label.name: a.expression,
      };

  String? _stringValue(Expression? expr) {
    if (expr == null) return null;
    if (expr is SimpleStringLiteral) return expr.value;
    final folded = tryFoldConstant(expr);
    return folded is String ? folded : null;
  }

  void _stringArgIssue(String host, List<Issue> issues, String loc) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: '$host requires a string literal argument.',
        location: loc,
      ),
    );
  }

  /// Translates an `Alignment.<member>` reference or `Alignment(x, y)`
  /// ctor to the DSL map `{x: <double>, y: <double>}` that rfw's
  /// alignment decoder consumes.
  ///
  /// `Alignment(x, y)` surfaces as `InstanceCreationExpression` when
  /// the analyzer resolves the class and as a bare `MethodInvocation`
  /// when it can't — both shapes route through the same arg-list
  /// path.
  String alignmentGeometry(
    Expression rawExpr,
    List<Issue> issues,
    String loc,
  ) {
    // Gate at the mechanism: this helper dispatches on the raw expression's
    // SHAPE and diagnoses (no `_translate` fallback), so a named-intermediate
    // binding (a helper param / `final` local) used as an alignment argument —
    // e.g. a gradient `begin:`/`end:`, which reaches here OUTSIDE
    // `_translateSlotValue` — must be resolved-through here or it would
    // over-claim (classifier inlinable, translator a confusing diagnostic).
    // Inert outside an inline (both binding maps empty).
    final expr = _resolveBoundIdentifier(rawExpr);
    if (expr is PrefixedIdentifier && expr.prefix.name == 'Alignment') {
      // Nested name-only gate: an `Alignment.<member>` argument inside a real
      // framework gradient is lowered against a hard-coded coordinate table by
      // member NAME. A resolved customer class named `Alignment` must NOT
      // name-match — it would emit framework `{x, y}` coordinates for the
      // author's own type, a value-substitution silent-wrong the type-aware
      // floor cannot catch (any `{x, y}` is valid). Defer with a diagnostic;
      // an unresolved prefix keeps the name-based path (synthetic-test
      // affordance), consistent with the outermost value-substitution gate.
      if (!_frameworkOrUnresolved(expr.prefix.element)) {
        return _deferFrameworkConstLookalike(
          expr,
          'Alignment',
          expr.identifier.name,
          issues,
        );
      }
      return _alignmentMember(expr.identifier.name, issues, loc);
    }
    NodeList<Expression>? ctorArgs;
    if (expr is InstanceCreationExpression &&
        expr.constructorName.type.name.lexeme == 'Alignment' &&
        expr.constructorName.name == null) {
      if (_isResolvedNonFrameworkCtor(expr)) {
        return _deferFrameworkCtorLookalike(expr, 'Alignment', issues);
      }
      ctorArgs = expr.argumentList.arguments;
    } else if (expr is MethodInvocation &&
        expr.target == null &&
        expr.methodName.name == 'Alignment') {
      ctorArgs = expr.argumentList.arguments;
    }
    if (ctorArgs != null) {
      final xy = _xyMap(ctorArgs, issues, loc, diagnoseHost: null);
      if (xy != null) return xy;
    }
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: 'Unsupported alignment expression: ${expr.toSource()}. '
            'Use an Alignment.<name> member or Alignment(x, y).',
        location: loc,
      ),
    );
    return '{x: 0.0, y: 0.0}';
  }

  String _alignmentMember(String member, List<Issue> issues, String loc) {
    final xy = _kAlignmentMembers[member];
    if (xy != null) return '{x: ${xy.$1}, y: ${xy.$2}}';
    issues.add(
      Issue(
        code: IssueCode.unresolvedIdentifier,
        message: "Unsupported Alignment member 'Alignment.$member'. "
            'Supported: ${_kAlignmentMembers.keys.join(", ")}.',
        location: loc,
      ),
    );
    return '{x: 0.0, y: 0.0}';
  }

  /// Returns the `{x, y}` DSL fragment for an `(x, y)` positional-double
  /// arg list, or `null` when the arg shape doesn't match. When
  /// [diagnoseHost] is non-null an `Issue` is surfaced on shape
  /// mismatch (the helper-with-diagnostic variant); when null the
  /// caller handles the mismatch (the optional-translation variant).
  String? _xyMap(
    NodeList<Expression> args,
    List<Issue> issues,
    String loc, {
    required String? diagnoseHost,
  }) {
    final positional = args.where((a) => a is! NamedExpression).toList();
    if (positional.length != 2) {
      if (diagnoseHost != null) {
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: '$diagnoseHost requires two positional arguments (x, y).',
            location: loc,
          ),
        );
      }
      return null;
    }
    final x = _translateDoubleScalar(positional[0], issues);
    final y = _translateDoubleScalar(positional[1], issues);
    return '{x: $x, y: $y}';
  }

  /// Surfaces a uniform diagnostic for an unrecognised named argument
  /// to a structured-type translator (`LinearGradient`, `Border`, …).
  void _unknownNamedArg(
    String host,
    String argName,
    String supported,
    List<Issue> issues,
    String loc,
  ) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: 'Unknown $host argument: $argName. Supported: $supported.',
        location: loc,
      ),
    );
  }

  /// Surfaces a uniform diagnostic for a recognised but not-yet-supported
  /// named argument (e.g. `LinearGradient.tileMode`).
  void _deferredArg(
    String host,
    String argName,
    List<Issue> issues,
    String loc,
  ) {
    issues.add(
      Issue(
        code: IssueCode.unrecognizedMethodCall,
        message: '$host.$argName is not yet supported.',
        location: loc,
      ),
    );
  }
}

/// `Alignment.<member>` references resolved at codegen time. Used by
/// the linear-gradient translator for `begin:` / `end:` since rfw's
/// alignment decoder expects an `{x, y}` map. Mirrors Flutter's
/// `Alignment` static members.
const Map<String, (double, double)> _kAlignmentMembers = {
  'topLeft': (-1.0, -1.0),
  'topCenter': (0.0, -1.0),
  'topRight': (1.0, -1.0),
  'centerLeft': (-1.0, 0.0),
  'center': (0.0, 0.0),
  'centerRight': (1.0, 0.0),
  'bottomLeft': (-1.0, 1.0),
  'bottomCenter': (0.0, 1.0),
  'bottomRight': (1.0, 1.0),
};
