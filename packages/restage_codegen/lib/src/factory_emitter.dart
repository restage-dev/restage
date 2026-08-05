import 'package:collection/collection.dart';
import 'package:restage_codegen/src/customer_map_plan.dart';
import 'package:restage_codegen/src/customer_record_plan.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart'
    show
        isCustomerMapFieldSlot,
        isCustomerMapPropertySlot,
        isCustomerMapShape,
        isCustomerRecordFieldSlot,
        isCustomerRecordPropertySlot,
        isCustomerRecordShape,
        isCustomerStructuredListShape,
        isCustomerStructuredPropertySlot,
        structuredSlotKey;
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
import 'package:restage_codegen/src/factory_variant_fields.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_codegen/src/synthetic_property.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Returns the Dart source for one top-level `LocalWidgetBuilder` closure
/// that constructs [entry]'s underlying Flutter widget from a flat
/// `DataSource`, or `null` if [entry] cannot be mechanically emitted
/// against the current generator surface.
///
/// Eligibility:
///
///   * Every scalar property type may appear
///     (`color`/`length`/`edgeInsets`/`alignment`/`fontWeight`/
///     `duration`/`curve`/`boolean`/`integer`/`real`/`string`).
///   * `ChildrenSlot.single` is allowed when the entry has a property
///     named `'child'` of type `widget` — that property emits as
///     `child: source.child(...)` (required) or
///     `child: source.optionalChild(...)` (optional). Other widget-typed
///     properties (e.g. `body`, `appBar`, `home`) are rejected; their
///     Flutter constructor parameters often have non-`Widget` types
///     (`PreferredSizeWidget?`, etc.) that would mismatch the helpers'
///     return type and break the consuming package's build.
///   * `ChildrenSlot.list` is allowed when the entry has a property
///     named `'children'` of type `widgetList` — that property emits as
///     `children: source.childList(...)`.
///   * Void-callback event properties (`onPressed`, `onTap`, `onLongPress`,
///     `onDoubleTap`, `onEnd`, `onSheetDismissed`) emit as
///     `<name>: source.voidHandler(...)`. The set of event property names
///     must exactly match the entry's `fires` list. Other event names (e.g.
///     `'onChanged'`) declare the typed callback shape via
///     `PropertyEntry.callbackSignature` (e.g. `'ValueChanged<bool>'`) and
///     emit through
///     `source.handler<T>(path, (trigger) => (T value) => trigger({...}))`.
///   * `synthetic: 'gateOnPressed'` on a boolean property gates the
///     entry's `onPressed` event handler instead of being passed as
///     a constructor argument: the generator emits a pre-amble
///     decode of the bool, then wraps the `onPressed` slot as
///     `onPressed: <bool> ? null : source.voidHandler(...)`. Requires
///     the entry to declare an `onPressed` event property.
///
/// Eligible additions:
///
///   * `decomposes` recipes emit as `<slot>: <Call>(<inner>: <decode>, ...)`
///     where `<slot>` is the named ctor arg the structured type slots
///     into (`ButtonStyle` / `TextStyle` → `style`, `BoxDecoration`
///     → `decoration`). The native recipe's receiver-aware construction
///     metadata determines whether `<Call>` is a constructor or static factory.
///     Properties consumed by a recipe are excluded from the direct named-args
///     list.
///   * `synthetic: 'iconData'` on an integer property wraps the
///     codepoint as `IconData(value, fontFamily: 'MaterialIcons')`
///     and emits positionally — must be paired with `positional: true`
///     so the wrapped value slots into Flutter's positional `icon`
///     arg.
///   * `synthetic: 'borderRadiusCircular'` on a real property wraps
///     the decoded scalar as `BorderRadius.circular(<value>)` so the
///     same flat slot drives both direct ctor args
///     (`ClipRRect.borderRadius`) and recipe-hoisted inner args
///     (`BoxDecoration.borderRadius`). When the property is optional
///     and has no literal default, the emission coalesces the
///     nullable decode to `0.0` so missing slots collapse to
///     `BorderRadius.zero`.
///   * `positional: true` properties emit as positional ctor args
///     ahead of the named ones, in catalog declaration order. Used
///     for Flutter widgets whose first ctor arg is positional
///     (`Image.network(String src, ...)`, `Icon(IconData icon, ...)`,
///     `Text(String data, ...)`).
///   * `PropertyType.enumValue` properties carrying `enumType` emit
///     as `ArgumentDecoders.enumValue<T>(T.values, source, path)`.
///     A literal `defaultValue` string (e.g. `'start'`) renders as
///     `T.<value>` for the `??` fallback so the emitted code
///     satisfies non-nullable Flutter ctor parameters. The named
///     enum type must be reachable from the per-library Flutter
///     import the emitter adds.
///   * Non-canonical `PropertyType.widget` properties (additional
///     `Widget?` slots beyond the single canonical `'child'` slot —
///     e.g. AppBar.title, Scaffold.body, IconButton.icon) emit as
///     `<name>: source.optionalChild(...)` (or `source.child(...)`
///     when `required`). When the property carries `widgetType`,
///     the codegen appends a downcast (`as <widgetType>` /
///     `as <widgetType>?`) so the value type-checks against a
///     narrower Flutter ctor parameter (e.g. Scaffold.appBar's
///     `PreferredSizeWidget?`).
///
/// Excluded today: non-canonical widgetList properties (additional
/// `List<Widget>` slots beyond the canonical `'children'` slot). Lands
/// in subsequent generator work.
String? emitFactoryFunction(
  WidgetEntry entry, {
  NativeCatalogIndex? nativeIndex,
  CustomerReconstruction? customer,
  Map<String, String> aliases = const {},
}) {
  if (!_isMechanicallyEmittable(
    entry,
    nativeIndex: nativeIndex,
    customer: customer,
  )) {
    return null;
  }

  // The import-alias map is threaded in explicitly so it is available even
  // when there is no structured-type reconstruction context (`customer` is
  // null but the caller still emits aliased imports). Fall back to the
  // customer record's aliases for callers that only pass `customer`.
  final customerAliases = aliases.isNotEmpty
      ? aliases
      : (customer?.aliases ?? const <String, String>{});
  final functionName = functionNameFor(entry);
  final ctor = _ctorExpressionFor(entry, aliases: customerAliases);
  final canonicalChild = _canonicalChildPropertyOf(entry);
  final gatingProp = _gatingPropertyOf(entry);

  // Properties consumed by a decomposition recipe are emitted as
  // inner args of the structured-type call; they don't also appear
  // as direct named ctor args.
  final consumedByRecipes = _consumedPropertyNames(
    entry,
    nativeIndex: nativeIndex,
  );

  // Emit order: positional args first (in catalog order), then
  // structured-type recipes, then named scalars + events, then the
  // canonical child slot last (sort_child_properties_last lint).
  final argLines = <String>[];

  for (final p in entry.properties) {
    if (!p.positional || consumedByRecipes.contains(p.name)) continue;
    final customerValue =
        _customerMapOrRecordPropValue(p, entry, customer, nativeIndex);
    if (customerValue != null) {
      argLines.add('    $customerValue,');
      continue;
    }
    // A POSITIONAL customer structured prop routes through the reconstructor
    // (emitted positionally, no name prefix) — the positional analog of the
    // named structured prop below. Without this it would fall into the old
    // structured decoder and throw "no registered decoder" (a build crash).
    final customerSourceType = _customerPropSourceType(p, entry, customer);
    if (customerSourceType != null) {
      final value = _customerStructuredPropValue(
        customerSourceType,
        p,
        entry,
        customer!,
        nativeIndex,
      );
      argLines.add('    $value,');
      continue;
    }
    final positional = _positionalEmit(
      p,
      entry.name,
      index: nativeIndex,
      aliases: customerAliases,
    );
    argLines.add('    $positional,');
  }

  if (entry.decomposes.isNotEmpty) {
    final index = nativeIndex;
    if (index == null) return null;
    for (final recipe in entry.decomposes) {
      final recipeArg = _nativeRecipeEmit(recipe, entry, index);
      argLines.add('    $recipeArg,');
    }
  }

  // `imageFilterBlur` synthetic: pair `blurSigmaX` + `blurSigmaY`
  // scalars into an `ImageFilter.blur(sigmaX:, sigmaY:)` value and
  // emit as the widget's `filter:` named arg. The two scalars don't
  // surface as direct ctor args — they're consumed here. Eligibility
  // (paired existence) is gated upstream in `_isMechanicallyEmittable`.
  // The sigma decode threads through `_decodeExpression` so a required
  // curation routes through the throw-on-missing
  // path automatically; the present catalog leaves both optional and
  // Flutter's "no blur" default (sigma = 0.0) is provided here.
  final xProp = entry.properties.firstWhereOrNull(
    (p) => p.synthetic == _imageFilterBlurSynthetic && p.name == 'blurSigmaX',
  );
  if (xProp != null) {
    final yProp = entry.properties.firstWhere(
      (p) => p.synthetic == _imageFilterBlurSynthetic && p.name == 'blurSigmaY',
    );
    final xExpr = _decodeExpression(xProp, entry.name, index: nativeIndex);
    final yExpr = _decodeExpression(yProp, entry.name, index: nativeIndex);
    final xArg = xProp.required ? xExpr : '($xExpr ?? 0.0)';
    final yArg = yProp.required ? yExpr : '($yExpr ?? 0.0)';
    argLines.add(
      '    filter: ImageFilter.blur(sigmaX: $xArg, sigmaY: $yArg),',
    );
  }

  for (final p in entry.properties) {
    if (p.positional) continue;
    if (p.synthetic == _borderRadiusCircularSynthetic) {
      // Direct-property borderRadius wrap (e.g. `ClipRRect.borderRadius`,
      // whose Flutter slot is non-nullable). Recipe-hoisted flats with the
      // same synthetic emit through `_recipeEmit` with `nullable: true`
      // and are filtered above via `consumedByRecipes`.
      if (consumedByRecipes.contains(p.name)) continue;
      final uniform = _wrappedValueFor(
        p,
        entry.name,
        nullable: false,
        index: nativeIndex,
      );
      // When the entry declares the four corner siblings, the uniform
      // expression becomes the fall-through arm of the per-corner
      // conditional; otherwise it emits unchanged (byte-identical).
      final value =
          _borderRadiusEmitWithCorners(uniform, entry, index: nativeIndex);
      argLines.add('    ${p.name}: $value,');
      continue;
    }
    if (p.synthetic != null) continue; // consumed elsewhere
    if (identical(p, canonicalChild)) continue;
    if (consumedByRecipes.contains(p.name)) continue;

    if (gatingProp != null &&
        p.type == PropertyType.event &&
        p.name == 'onPressed') {
      // Gate the onPressed handler with the bool synthetic. Setting
      // `onPressed: null` is Flutter's convention for the disabled
      // state across button widgets.
      final decoded =
          _decoderCallFor(p, "<Object>['${p.name}']", index: nativeIndex);
      argLines.add(
        '    ${p.name}: ${gatingProp.name} ? null : $decoded,',
      );
      continue;
    }
    final customerValue =
        _customerMapOrRecordPropValue(p, entry, customer, nativeIndex);
    if (customerValue != null) {
      argLines.add('    ${p.name}: $customerValue,');
      continue;
    }
    final customerSourceType = _customerPropSourceType(p, entry, customer);
    if (customerSourceType != null) {
      // A customer structured slot renders through the inline reconstructor,
      // reading its fields from the wire map at this property's path (a NAMED
      // arg — the positional analog is routed the same way in the positional
      // loop above).
      final value = _customerStructuredPropValue(
        customerSourceType,
        p,
        entry,
        customer!,
        nativeIndex,
      );
      argLines.add('    ${p.name}: $value,');
      continue;
    }
    final decoded = _decodeExpression(
      p,
      entry.name,
      index: nativeIndex,
      aliases: customerAliases,
    );
    argLines.add('    ${p.name}: $decoded,');
  }

  if (canonicalChild != null) {
    final decoded = _decodeExpression(
      canonicalChild,
      entry.name,
      index: nativeIndex,
      aliases: customerAliases,
    );
    argLines.add('    ${canonicalChild.name}: $decoded,');
  }

  final preamble = gatingProp == null
      ? ''
      : '  final ${gatingProp.name} = '
          "source.v<bool>(<Object>['${gatingProp.name}']) ?? false;\n\n";

  return '''
Widget $functionName(BuildContext context, DataSource source) {
$preamble  return $ctor(
${argLines.join('\n')}
  );
}
''';
}

/// Emits the positional value for [prop] without a `name:` prefix.
/// `iconData` synthetic wraps the int codepoint into an `IconData`
/// constant; everything else falls through to the same scalar
/// decoder used for named args.
///
/// For `required: true` codepoints, the inner expression mirrors
/// [_decodeExpression]'s throw-on-missing contract so a malformed blob
/// fails loudly rather than rendering a zero-codepoint icon the user
/// can't tell is broken. Non-required codepoints retain the `?? 0`
/// fallback (zero is a valid `IconData` argument and the surrounding
/// Icon paints a Material default at that codepoint).
String _positionalEmit(
  PropertyEntry prop,
  String widgetName, {
  NativeCatalogIndex? index,
  Map<String, String> aliases = const {},
}) {
  if (prop.synthetic == _iconDataSynthetic) {
    final read = "source.v<int>(<Object>['${prop.name}'])";
    final fallback = prop.required
        ? "(throw ArgumentError('$widgetName.${prop.name} is required.'))"
        : '0';
    return "IconData($read ?? $fallback, fontFamily: 'MaterialIcons')";
  }
  return _decodeExpression(prop, widgetName, index: index, aliases: aliases);
}

String _nativeRecipeEmit(
  DecompositionRecipe recipe,
  WidgetEntry entry,
  NativeCatalogIndex index,
) {
  final targetArg = recipe.targetArg;
  final construction = recipe.construction;
  if (targetArg == null || construction == null) {
    throw StateError(
      "Native decomposition recipe on '${entry.name}' is missing "
      'targetArg or construction.',
    );
  }
  final structured = index.structuredByRef(recipe.structuredRef);
  if (structured == null) {
    throw StateError(
      "Native decomposition recipe on '${entry.name}' references "
      'unknown structured entry ${recipe.structuredRef}.',
    );
  }
  final variant = _requiredVariant(index, construction.variantRef);
  // A structured type that layout validates only under an assert gets its
  // reassembled value repaired before it can reach a render object.
  final repair = _kStructuredRepairs[structured.sourceType];
  final expression = _nativeFactoryInvocationExpression(
    invocation: construction,
    variant: variant,
    owningWidget: entry,
    resultStructured: structured,
    index: index,
    argumentForParameter: (parameter) => _outerArgumentForParameter(
      parameter: parameter,
      variant: variant,
      recipe: recipe,
      entry: entry,
      index: index,
      // A field feeding a repaired reassembly reads its number tolerantly. The
      // strict `source.v<double>` cannot tell an `int` on the wire from an
      // absent slot, so a whole number written as `200` would take the field's
      // default instead of its value — and the repair cannot undo that: by the
      // time it sees the assembled value, the number is already gone. Read it
      // where it is still there.
      tolerantNumbers: repair != null,
    ),
  );
  return repair == null
      ? '$targetArg: $expression'
      : '$targetArg: $repair($expression)';
}

String _nativeFactoryInvocationExpression({
  required FactoryInvocation invocation,
  required FactoryVariant variant,
  required WidgetEntry owningWidget,
  required StructuredEntry resultStructured,
  required NativeCatalogIndex index,
  required String? Function(FactoryParameter parameter) argumentForParameter,
}) {
  final receiverType = index.receiverDartType(
    invocation.receiver,
    owningWidget: owningWidget,
    resultStructured: resultStructured,
  );
  final receiver = receiverType.symbolName;

  // The accessor kinds carry a non-null accessor name by construction, so the
  // "no member name" guards the old flat switch needed are gone; only an
  // unnamed constructor legitimately has no member (it calls the receiver).
  switch (variant) {
    case ConstructorVariant(:final namedConstructor, :final parameters):
      final member = invocation.memberName ?? namedConstructor;
      final callable = member == null ? receiver : '$receiver.$member';
      return '$callable'
          '(${_nativeArgumentList(parameters, argumentForParameter)})';
    case StaticMethodVariant(:final staticAccessor, :final parameters):
      final member = invocation.memberName ?? staticAccessor;
      return '$receiver.$member('
          '${_nativeArgumentList(parameters, argumentForParameter)})';
    case StaticGetterVariant(:final staticAccessor) ||
          ConstValueVariant(:final staticAccessor):
      final member = invocation.memberName ?? staticAccessor;
      return '$receiver.$member';
  }
}

String _nativeArgumentList(
  List<FactoryParameter> parameters,
  String? Function(FactoryParameter parameter) argumentForParameter,
) {
  final args = <String>[];
  for (final parameter in _orderedParameters(parameters)) {
    final expression = argumentForParameter(parameter);
    if (expression == null) continue;
    switch (parameter.kind) {
      case FactoryParameterKind.named:
        args.add('${parameter.name}: $expression');
      case FactoryParameterKind.positional:
        args.add(expression);
    }
  }
  return args.join(', ');
}

List<FactoryParameter> _orderedParameters(List<FactoryParameter> parameters) {
  final positional = parameters
      .where((p) => p.kind == FactoryParameterKind.positional)
      .toList()
    ..sort((a, b) => a.position!.compareTo(b.position!));
  final named = parameters
      .where((p) => p.kind == FactoryParameterKind.named)
      .toList(growable: false);
  return [...positional, ...named];
}

String? _outerArgumentForParameter({
  required FactoryParameter parameter,
  required FactoryVariant variant,
  required DecompositionRecipe recipe,
  required WidgetEntry entry,
  required NativeCatalogIndex index,
  bool tolerantNumbers = false,
}) {
  final parameterMapping = recipe.parameterMappings.firstWhereOrNull(
    (mapping) => mapping.parameterRef == parameter.wireId,
  );
  if (parameterMapping != null) {
    return _mappedOuterArgument(
      propertyRef: parameterMapping.propertyRef,
      transform: parameterMapping.transform,
      entry: entry,
      index: index,
      parameter: parameter,
      tolerantNumbers: tolerantNumbers,
    );
  }

  final fieldIds = _targetFieldsForParameter(variant, parameter);
  if (fieldIds.isEmpty) return _missingArgumentExpression(parameter);
  if (fieldIds.length != 1) {
    throw StateError(
      'Native factory parameter ${parameter.wireId} maps to multiple fields; '
      'multi-field forward construction is not supported by this emitter.',
    );
  }

  final fieldMapping = recipe.fieldMappings.firstWhereOrNull(
    (mapping) => mapping.fieldRef == fieldIds.single,
  );
  if (fieldMapping == null) return _missingArgumentExpression(parameter);
  return _mappedOuterArgument(
    propertyRef: fieldMapping.propertyRef,
    transform: fieldMapping.transform,
    entry: entry,
    index: index,
    parameter: parameter,
    tolerantNumbers: tolerantNumbers,
  );
}

String _mappedOuterArgument({
  required WireId propertyRef,
  required DecompositionValueTransform transform,
  required WidgetEntry entry,
  required NativeCatalogIndex index,
  required FactoryParameter parameter,
  bool tolerantNumbers = false,
}) {
  final property = _propertyByWireId(entry, propertyRef);
  if (property == null) {
    throw StateError(
      "Native decomposition recipe on '${entry.name}' references unknown "
      'property $propertyRef.',
    );
  }
  var expression = _transformExpression(
    transform,
    property: property,
    entry: entry,
    index: index,
    parameter: parameter,
    tolerantNumbers: tolerantNumbers,
  );
  // Recipe-hoisted borderRadius (e.g. `BoxDecoration.borderRadius` on
  // Container / AnimatedContainer): when the owning entry declares the four
  // corner siblings, wrap the uniform `BorderRadius.circular(...)` recipe
  // expression in the per-corner `BorderRadius.only(...)` conditional —
  // the same never-both reconstruction the direct ClipRRect path emits.
  // The corner reals are NOT recipe field-mappings (which would hit the
  // multi-field forward-construction throw); they're standalone synthetics
  // read here.
  if (property.synthetic == _borderRadiusCircularSynthetic) {
    expression = _borderRadiusEmitWithCorners(expression, entry, index: index);
  }
  return _applyParameterDefaultFallback(
    expression,
    parameter,
    property: property,
    transform: transform,
  );
}

List<WireId> _targetFieldsForParameter(
  FactoryVariant variant,
  FactoryParameter parameter,
) {
  final fields = factoryVariantCallableFields(variant);
  final name = parameter.name;
  if (name != null) {
    return fields.argMappings[name]?.targetFields ?? const [];
  }
  if (fields.parameters.length == 1 && fields.argMappings.length == 1) {
    return fields.argMappings.values.single.targetFields;
  }
  return const [];
}

String? _missingArgumentExpression(FactoryParameter parameter) {
  switch (parameter.defaultPolicy) {
    case FactoryParameterDefaultPolicy.omitWhenNull:
    case FactoryParameterDefaultPolicy.useFlutterDefault:
      return null;
    case FactoryParameterDefaultPolicy.emitNull:
      return 'null';
    case FactoryParameterDefaultPolicy.requiredValue:
      throw StateError(
        'Native factory parameter ${parameter.wireId} is required but no '
        'field mapping supplied a value.',
      );
  }
}

String _applyParameterDefaultFallback(
  String expression,
  FactoryParameter parameter, {
  required PropertyEntry property,
  required DecompositionValueTransform transform,
}) {
  if (parameter.nullable || parameter.defaultValue == null) return expression;
  // For an identity transform the decoded property expression already carries
  // the property's own default fallback. When that property default is a
  // non-null-guaranteeing constant (any source other than a theme binding,
  // whose resolved value is nullable at render time), appending the parameter
  // default here is dead code — `value ?? const ?? const`. Skip it so the
  // emitted argument is a single `value ?? const`. Theme-binding property
  // defaults resolve to a nullable value, so the parameter default stays a
  // reachable fallback and is kept.
  if (transform is IdentityTransform &&
      property.defaultSource is! ThemeBindingDefault &&
      _defaultExpressionFor(property) != null) {
    return expression;
  }
  return '$expression ?? ${_parameterDefaultExpression(parameter)}';
}

String _parameterDefaultExpression(FactoryParameter parameter) {
  final defaultValue = parameter.defaultValue;
  if (defaultValue == null) {
    throw StateError(
      'Native factory parameter ${parameter.wireId} has no default value.',
    );
  }
  switch (defaultValue) {
    case LiteralParameterDefault(:final value):
      if (value is bool || value is int || value is double) return '$value';
      if (value is String) {
        final valueShape = parameter.valueShape;
        final enumRef = valueShape is EnumShape ? valueShape.enumRef : null;
        if (valueShape.propertyType == PropertyType.enumValue &&
            enumRef != null) {
          return '${enumRef.symbolName}.$value';
        }
        return _dartStringLiteral(value);
      }
      throw StateError(
        'Unsupported literal default for native factory parameter '
        '${parameter.wireId}: $value',
      );
    case StaticMemberParameterDefault(:final staticType, :final memberName):
      if (memberName.isEmpty) {
        throw StateError(
          'Malformed static default for native factory parameter '
          '${parameter.wireId}.',
        );
      }
      return '${staticType.symbolName}.$memberName';
  }
}

String _transformExpression(
  DecompositionValueTransform transform, {
  required PropertyEntry property,
  required WidgetEntry entry,
  required NativeCatalogIndex index,
  required FactoryParameter parameter,
  bool tolerantNumbers = false,
}) {
  switch (transform) {
    case IdentityTransform():
      return _nativeDecodedArgument(
        property,
        entry: entry,
        parameter: parameter,
        index: index,
        tolerantNumbers: tolerantNumbers,
      );
    case ConstructVariantTransform():
      return _constructVariantTransformExpression(
        transform,
        property: property,
        entry: entry,
        index: index,
      );
    case ProjectListTransform():
      if (_isSupportedNativeProjectList(transform, property)) {
        return _nativeDecodedArgument(
          property,
          entry: entry,
          parameter: parameter,
          index: index,
          tolerantNumbers: tolerantNumbers,
        );
      }
      throw StateError(
        'Native projectList transform for ${entry.name}.${property.name} is '
        'not supported by factory emission.',
      );
    case CoerceScalarTransform():
      throw StateError(
        'Native transform coerceScalar is not supported by '
        'factory emission yet.',
      );
  }
}

String _nativeDecodedArgument(
  PropertyEntry property, {
  required WidgetEntry entry,
  required FactoryParameter parameter,
  required NativeCatalogIndex index,
  bool tolerantNumbers = false,
}) {
  return _coerceNativeArgumentForParameter(
    _wrappedValueFor(
      property,
      entry.name,
      nullable: parameter.nullable,
      index: index,
      tolerantNumbers: tolerantNumbers,
    ),
    parameter: parameter,
    index: index,
  );
}

String _coerceNativeArgumentForParameter(
  String expression, {
  required FactoryParameter parameter,
  required NativeCatalogIndex index,
}) {
  final targetType = _shapeBorderTargetType(parameter.valueShape, index);
  if (targetType == 'OutlinedBorder') {
    // The cast nullability must follow the target parameter: a non-nullable
    // OutlinedBorder parameter takes a non-nullable cast, otherwise the
    // emitted argument is `OutlinedBorder?` against a non-null parameter.
    final nullability = parameter.nullable ? '?' : '';
    return '($expression as OutlinedBorder$nullability)';
  }
  return expression;
}

String? _shapeBorderTargetType(
  CatalogValueShape shape,
  NativeCatalogIndex index,
) {
  if (shape.propertyType != PropertyType.shapeBorder) return null;
  if (shape is UnionShape) {
    final union = index.unionByRef(shape.unionRef);
    final symbol = _sourceTypeSymbol(union?.sourceType);
    if (symbol == 'OutlinedBorder') return symbol;
  }
  if (shape is ScalarShape) {
    final dartTypeRef = shape.dartTypeRef;
    if (dartTypeRef?.symbolName == 'OutlinedBorder') {
      return dartTypeRef!.symbolName;
    }
  }
  return null;
}

String? _sourceTypeSymbol(String? sourceType) {
  if (sourceType == null) return null;
  final hash = sourceType.indexOf('#');
  if (hash < 0 || hash == sourceType.length - 1) return null;
  return sourceType.substring(hash + 1);
}

String _constructVariantTransformExpression(
  ConstructVariantTransform transform, {
  required PropertyEntry property,
  required WidgetEntry entry,
  required NativeCatalogIndex index,
  Set<String>? sharedNullGuards,
}) {
  final resultStructuredRef = transform.resultStructuredRef;
  final invocation = transform.invocation;
  final resultStructured = index.structuredByRef(resultStructuredRef);
  if (resultStructured == null) {
    throw StateError(
      'constructVariant transform references unknown structured entry '
      '$resultStructuredRef.',
    );
  }
  final variant = _requiredVariant(index, invocation.variantRef);
  final bindings = {
    for (final binding in transform.argumentBindings)
      binding.parameterRef: binding,
  };
  final nullGuards = sharedNullGuards ?? <String>{};
  final expression = _nativeFactoryInvocationExpression(
    invocation: invocation,
    variant: variant,
    owningWidget: entry,
    resultStructured: resultStructured,
    index: index,
    argumentForParameter: (parameter) {
      final binding = bindings[parameter.wireId];
      if (binding == null) return _missingArgumentExpression(parameter);
      return _transformBindingExpression(
        binding,
        property: property,
        entry: entry,
        index: index,
        nullGuards: nullGuards,
      );
    },
  );
  if (sharedNullGuards != null) return expression;
  if (nullGuards.isEmpty) return expression;
  final guard = nullGuards.join(' || ');
  return '$guard ? null : $expression';
}

String _transformBindingExpression(
  TransformArgumentBinding binding, {
  required PropertyEntry property,
  required WidgetEntry entry,
  required NativeCatalogIndex index,
  required Set<String> nullGuards,
}) {
  switch (binding) {
    case PropertyValueArgumentBinding():
      final path = "<Object>['${property.name}']";
      final decoded = _decoderCallFor(property, path, index: index);
      if (binding.nullPolicy == TransformNullPolicy.nullResult ||
          binding.missingPolicy == TransformMissingPolicy.nullResult) {
        nullGuards.add('$decoded == null');
        return '$decoded!';
      }
      if (binding.nullPolicy == TransformNullPolicy.error ||
          binding.missingPolicy == TransformMissingPolicy.error) {
        return '$decoded ?? '
            "(throw ArgumentError('${entry.name}.${property.name} is "
            "required.'))";
      }
      return _decodeExpression(property, entry.name, index: index);
    case LiteralArgumentBinding(:final literal):
      return _literalExpression(literal);
    case NestedTransformArgumentBinding(:final nestedTransform):
      if (nestedTransform is! ConstructVariantTransform) {
        throw StateError(
          'nestedTransform argument binding must be a constructVariant '
          'transform; got ${_transformKindName(nestedTransform)}.',
        );
      }
      return _constructVariantTransformExpression(
        nestedTransform,
        property: property,
        entry: entry,
        index: index,
        sharedNullGuards: nullGuards,
      );
  }
}

String _literalExpression(Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is int || value is double) return '$value';
  if (value is String) return _dartStringLiteral(value);
  throw StateError('Unsupported native transform literal: $value.');
}

FactoryVariant _requiredVariant(NativeCatalogIndex index, WireIdRef ref) {
  final variant = index.variantByRef(ref);
  if (variant == null) {
    throw StateError('Native factory variant $ref was not found.');
  }
  return variant;
}

/// Returns the Dart expression for [prop]'s value at a ctor-arg call
/// site, applying any per-synthetic wrap. Falls through to
/// [_decodeExpression] for properties without an emission-wrap
/// synthetic.
///
/// [nullable] is `true` when the call-site sink accepts `null` (e.g.
/// `BoxDecoration.borderRadius` — `BorderRadiusGeometry?`) and `false`
/// when the sink is non-nullable (e.g. `ClipRRect.borderRadius` —
/// `BorderRadiusGeometry` with a `BorderRadius.zero` default). For
/// `borderRadiusCircular`, the distinction is load-bearing:
/// `BoxDecoration` asserts `shape == BoxShape.circle` implies
/// `borderRadius == null`, so the recipe-inner path must collapse a
/// missing slot to `null`, not to `BorderRadius.zero`. The direct-prop
/// path stays with the zero default since the Flutter ctor parameter
/// can't take `null` there.
String _wrappedValueFor(
  PropertyEntry prop,
  String widgetName, {
  required bool nullable,
  NativeCatalogIndex? index,
  bool tolerantNumbers = false,
}) {
  final decoded = _decodeExpression(
    prop,
    widgetName,
    index: index,
    tolerantNumbers: tolerantNumbers,
  );
  switch (prop.synthetic) {
    case _borderRadiusCircularSynthetic:
      // Required / default-bearing slots resolve to non-null `double`
      // via `_decodeExpression`'s own fallback — wrap directly.
      if (prop.required || prop.defaultValue != null) {
        return 'BorderRadius.circular($decoded)';
      }
      if (nullable) {
        // Two reads of `source.v<double>(...)` — cheap (map lookup) and
        // keeps the emission a single expression for the recipe-inner
        // arg position.
        return '$decoded == null ? null : BorderRadius.circular($decoded!)';
      }
      return 'BorderRadius.circular($decoded ?? 0.0)';
    default:
      return decoded;
  }
}

/// The four corner reals declared on [entry] via the
/// [_borderRadiusCornerSynthetic] strategy, keyed by the corner name. An
/// entry either declares none of them (uniform-only) or — by curation
/// convention — all four; the helper returns whatever subset is present.
/// A partial subset is rejected loudly at emission (see
/// [_borderRadiusEmitWithCorners]) rather than silently defaulting the
/// missing corner(s) to `Radius.zero`.
Map<String, PropertyEntry> _borderRadiusCornersOf(WidgetEntry entry) {
  final corners = <String, PropertyEntry>{};
  for (final corner in _kBorderRadiusCorners) {
    final prop = entry.properties.firstWhereOrNull(
      (p) =>
          p.synthetic == _borderRadiusCornerSynthetic &&
          p.name == corner.property,
    );
    if (prop != null) corners[corner.corner] = prop;
  }
  return corners;
}

/// Wraps [uniformExpression] (the existing `BorderRadius.circular(...)` /
/// nullable-collapse output for the uniform `borderRadius` slot) in the
/// per-corner conditional when [entry] declares the corner siblings.
///
/// With no corner siblings the uniform expression is returned verbatim —
/// the emission is byte-identical to the pre-per-corner output. With
/// corners present, the emission is a single ternary:
///
/// ```text
/// (<topLeft> ?? <topRight> ?? <bottomLeft> ?? <bottomRight>) != null
///   ? BorderRadius.only(
///       topLeft: Radius.circular(<topLeft> ?? 0.0), ...)
///   : <uniformExpression>
/// ```
///
/// so ANY corner present on the wire selects `BorderRadius.only(...)`
/// (each omitted corner coalescing to `0.0` ≡ `Radius.zero`) and an
/// all-corners-absent wire falls through to the uniform path — never both.
String _borderRadiusEmitWithCorners(
  String uniformExpression,
  WidgetEntry entry, {
  NativeCatalogIndex? index,
}) {
  final corners = _borderRadiusCornersOf(entry);
  if (corners.isEmpty) return uniformExpression;
  // Enforce the all-four-or-none curation convention: a partial corner set
  // (e.g. a 3-corner curation slip) would silently default the missing
  // corner to `Radius.zero` instead of failing loud, because every
  // `BorderRadius.only` named arg is optional. Refuse to emit so the slip
  // surfaces at build time rather than as a silent wrong-render.
  if (corners.length != _kBorderRadiusCorners.length) {
    throw StateError(
      "Catalog entry '${entry.name}' declares ${corners.length} of "
      '${_kBorderRadiusCorners.length} borderRadius corner synthetics. The '
      'per-corner reconstruction requires all four (topLeft / topRight / '
      'bottomLeft / bottomRight) or none — a partial set would silently '
      'default the missing corner(s) to Radius.zero. Refusing to emit.',
    );
  }

  String read(PropertyEntry prop) =>
      "source.v<double>(<Object>['${prop.name}'])";

  final presence = corners.values.map(read).join(' ?? ');
  final onlyArgs = <String>[];
  for (final corner in _kBorderRadiusCorners) {
    final prop = corners[corner.corner];
    if (prop == null) continue;
    onlyArgs.add(
      '${corner.corner}: Radius.circular(${read(prop)} ?? 0.0)',
    );
  }
  final only = 'BorderRadius.only(${onlyArgs.join(', ')})';
  // Parenthesize the uniform fall-through arm: the recipe-hoisted uniform
  // expression is itself a `cond ? null : circular(...)` ternary, and an
  // unparenthesized nested ternary in the `else` position binds ambiguously.
  return '($presence) != null ? $only : ($uniformExpression)';
}

/// Strategy identifier for `PropertyEntry.synthetic`: wrap the
/// integer codepoint as `IconData(value, fontFamily: 'MaterialIcons')`.
const String _iconDataSynthetic = 'iconData';

/// Structured types whose validity Flutter enforces with a debug-only assert
/// **from the render object rather than the constructor** — so a value
/// assembled from a corrupt wire is only discovered inside `performLayout`,
/// where a throw leaves a silently broken frame instead of a contained error.
/// Route their reassembly through a repair that hands layout a legal value.
///
/// Keyed by the structured entry's `sourceType`, so the mapping survives a
/// catalog rename.
const Map<String, String> _kStructuredRepairs = {
  'package:flutter/src/rendering/box.dart#BoxConstraints':
      'RestageDecoders.safeConstraints',
};

/// Strategy identifier for `PropertyEntry.synthetic`: gate the entry's
/// `onPressed` handler with the property's bool value.
const String _gateOnPressedSynthetic = 'gateOnPressed';

/// Strategy identifier for `PropertyEntry.synthetic`: combine paired
/// `blurSigmaX` / `blurSigmaY` scalar properties into an
/// `ImageFilter.blur(sigmaX:, sigmaY:)` value and route it to the
/// widget's `filter:` named arg. Used by `BackdropFilter`.
const String _imageFilterBlurSynthetic = 'imageFilterBlur';

/// Strategy identifier for `PropertyEntry.synthetic`: wrap the
/// property's decoded `double` value as `BorderRadius.circular(<value>)`
/// at emission time. Used for catalog slots that surface a
/// uniform-corner radius as a single real but whose Flutter ctor
/// expects a `BorderRadiusGeometry` (e.g. `ClipRRect.borderRadius`,
/// `BoxDecoration.borderRadius`).
///
/// When the owning entry ALSO declares the four
/// [_borderRadiusCornerSynthetic] sibling reals, the emission becomes a
/// per-corner conditional: any corner present on the wire selects
/// `BorderRadius.only(...)` (each omitted corner defaulting to
/// `Radius.zero`), otherwise the uniform `BorderRadius.circular(...)`
/// path emits unchanged — never both. With no corner siblings the
/// uniform emission is byte-identical to the pre-per-corner output.
const String _borderRadiusCircularSynthetic = 'borderRadiusCircular';

/// Strategy identifier for `PropertyEntry.synthetic`: a single corner's
/// radius scalar (`borderRadiusTopLeft` / `borderRadiusTopRight` /
/// `borderRadiusBottomLeft` / `borderRadiusBottomRight`). The four corner
/// reals are NEVER emitted as independent ctor args — they're read
/// together by the sibling [_borderRadiusCircularSynthetic] property's
/// emission, which reconstructs `BorderRadius.only(...)`. A corner
/// synthetic with no uniform `borderRadiusCircular` sibling has no
/// reconstruction owner and the entry is rejected by the eligibility gate.
const String _borderRadiusCornerSynthetic = 'borderRadiusCorner';

/// The four corner property names, in Flutter `BorderRadius.only` ctor
/// order, paired with the `Radius` ctor parameter each one feeds.
const List<({String property, String corner})> _kBorderRadiusCorners = [
  (property: 'borderRadiusTopLeft', corner: 'topLeft'),
  (property: 'borderRadiusTopRight', corner: 'topRight'),
  (property: 'borderRadiusBottomLeft', corner: 'bottomLeft'),
  (property: 'borderRadiusBottomRight', corner: 'bottomRight'),
];

/// The synthetic emit strategies the factory emitter knows how to lower.
///
/// A `PropertyEntry.synthetic` value outside this set has no emit path, so the
/// whole widget is dropped from mechanical emission. Curation validation checks
/// a synthetic's strategy against this set so a typo'd strategy is surfaced at
/// curation time instead of silently dropping the widget. (A `null` synthetic
/// is a non-strategy recipe-flat property and is not validated against this
/// set.)
const Set<String> kSupportedSyntheticStrategies = {
  _iconDataSynthetic,
  _gateOnPressedSynthetic,
  _imageFilterBlurSynthetic,
  _borderRadiusCircularSynthetic,
  _borderRadiusCornerSynthetic,
};

/// Returns the private function identifier for [entry]'s factory closure.
///
/// Built from the catalog `name` field (`'Center'` → `_buildCenter`,
/// `'CardFilled'` → `_buildCardFilled`). The catalog already
/// disambiguates named-constructor entries by giving them distinct
/// names (`'Card.filled'` becomes `'CardFilled'` in the registry), so
/// the dot-strip is defense-in-depth for any entry that slips
/// a dot through.
String functionNameFor(WidgetEntry entry) =>
    '_build${entry.name.replaceAll('.', '')}';

/// Whether the factory can mechanically emit EVERY aspect of [entry] (all
/// properties, slots, events, synthetics, decompositions) against the current
/// generator surface — the same whole-widget check `emitFactoryFunction` gates
/// on before producing a body. The walker uses it to close the admit-then-skip
/// gap: a widget this feature admits for a structured prop but whose OTHER
/// props are not all emittable (e.g. a direct enum prop with no metadata) is
/// excluded-loud at the ONE admission point rather than admitted-into-the-
/// catalog then skipped-by-the-factory. [customer] provides the inline
/// reconstruction context so a customer structured prop counts as emittable.
bool isFactoryEmittable(
  WidgetEntry entry, {
  NativeCatalogIndex? nativeIndex,
  CustomerReconstruction? customer,
}) =>
    _isMechanicallyEmittable(
      entry,
      nativeIndex: nativeIndex,
      customer: customer,
    );

/// True when every aspect of [entry] can be emitted by the current
/// generator surface. See [emitFactoryFunction] for the per-category
/// eligibility rules.
bool _isMechanicallyEmittable(
  WidgetEntry entry, {
  required NativeCatalogIndex? nativeIndex,
  CustomerReconstruction? customer,
}) {
  // single/list slots must point at a canonically-named widget /
  // widgetList property. Anything else (e.g. Scaffold's body+appBar,
  // CupertinoPageScaffold's navigationBar) hits a Flutter
  // constructor-parameter type the source.child helpers can't satisfy
  // — it lands in the bespoke-handling surface.
  final canonicalChild = _canonicalChildPropertyOf(entry);
  if (entry.childrenSlot != ChildrenSlot.none && canonicalChild == null) {
    return false;
  }

  // Each decomposition recipe must target a known structured type
  // and reference flat properties that actually exist on the entry.
  // Unknown structured types (or factory conventions) belong to the
  // bespoke surface. Two recipes referencing the same flat property
  // would render its value twice (once per structured target) — a
  // malformed-catalog signal; reject loudly.
  final consumedFlatNames = <String>{};
  if (entry.decomposes.isNotEmpty) {
    final index = nativeIndex;
    if (index == null) return false;
    for (final recipe in entry.decomposes) {
      if (!_isNativeRecipeEmittable(recipe, entry, index)) return false;
      for (final mapping in recipe.fieldMappings) {
        final property = _propertyByWireId(entry, mapping.propertyRef);
        if (property == null) return false;
        if (!consumedFlatNames.add(property.name)) return false;
      }
      for (final mapping in recipe.parameterMappings) {
        final property = _propertyByWireId(entry, mapping.propertyRef);
        if (property == null) return false;
        if (!consumedFlatNames.add(property.name)) return false;
      }
    }
  }

  // Event properties and `fires` must form an exact bijection — every
  // declared fire has a matching event property and vice versa, with
  // no duplicates on either side. Mismatches indicate a
  // bespoke-surface entry the mechanical emitter can't safely handle.
  //
  // The bijection key on the property side is `firesAs ?? name`. This
  // separates the catalog's event taxonomy from the underlying Flutter
  // ctor parameter name — e.g. `CupertinoDatePicker.onDateTimeChanged`
  // (the Flutter ctor name, used as the property name) declares
  // `firesAs: 'onChanged'` to satisfy a `WidgetEventName.onChanged`
  // fire. Property names that aren't renamed via `firesAs` continue
  // to match against their `name` directly.
  final eventProps = entry.properties
      .where((p) => p.type == PropertyType.event)
      .toList(growable: false);
  final eventNames = eventProps.map((p) => p.firesAs ?? p.name).toSet();
  final fireNames = entry.fires.map((f) => f.name).toSet();
  if (eventNames.length != eventProps.length ||
      fireNames.length != entry.fires.length ||
      eventNames.length != fireNames.length ||
      !eventNames.containsAll(fireNames)) {
    return false;
  }
  // Non-void event fires (e.g. `onChanged`) require the matching event
  // property to declare a `callbackSignature` so the emitter knows
  // which typed handler to thread through `source.handler<T>(...)`.
  // Void-callback event names skip this check since `voidHandler` is
  // the implicit signature.
  for (final fire in entry.fires) {
    if (_voidEvents.contains(fire)) continue;
    final prop =
        eventProps.firstWhereOrNull((p) => (p.firesAs ?? p.name) == fire.name);
    if (prop == null || prop.callbackSignature == null) return false;
    if (!_isSupportedCallbackSignature(prop.callbackSignature!)) return false;
  }

  // At-most-one synthetic of any given strategy per entry. Multiple
  // `gateOnPressed` synthetics would silently agree on which property
  // is the gate (whichever `_gatingPropertyOf` finds first); rejecting
  // here keeps eligibility and emit in lockstep.
  if (entry.properties
          .where((p) => p.synthetic == _gateOnPressedSynthetic)
          .length >
      1) {
    return false;
  }

  for (final prop in entry.properties) {
    // `identical` (not `==`) is intentional here and at the
    // equivalent skip in `emitFactoryFunction`. Both sites walk
    // `entry.properties` directly, and `_canonicalChildPropertyOf`
    // returns an element from that same list by reference; the
    // identity check matches the slot property without mistakenly
    // skipping a duplicate-by-value entry elsewhere in the list.
    if (identical(prop, canonicalChild)) continue;

    if (prop.synthetic != null) {
      if (!_isSupportedSynthetic(prop, entry)) return false;
      continue; // valid synthetic; not emitted as a ctor arg.
    }

    if (prop.type == PropertyType.event) continue; // validated above.

    // A `structured` widget property is an authored structured value slot —
    // it is INTENDED to emit through a registered runtime decoder. ANY
    // structured property that can't reach that decoder must fail the build
    // loudly here rather than letting the eligibility gate silently drop the
    // whole widget (the silent-exclusion class). Two distinct breaches:
    //   1. No resolvable structuredRef at all (neither a top-level
    //      `structuredRef` nor a `StructuredShape` valueShape ref) — a
    //      malformed structured slot. Throw before it falls through to the
    //      not-emittable path and gets silently excluded.
    //   2. A resolvable ref whose structured type has no registered decoder
    //      — the registered-table gap. Throw the same way.
    if (_customerReconstructableMapOrRecordProp(prop, entry, customer)) {
      continue;
    }
    if (_customerReconstructableProp(prop, entry, customer)) continue;

    if (prop.type == PropertyType.structured) {
      // A CUSTOMER structured slot has no registered runtime decoder (the table
      // is built-in only); it renders through the inline reconstructor instead.
      // The admission predicate already guaranteed the whole closure is
      // renderable + has a reconstruction plan, so an admitted customer slot is
      // emittable here. (No 'admitted-but-skip' path: an admitted slot the
      // reconstructor can't handle is a predicate gap, excluded upstream.)
      if (_structuredRefOf(prop) == null) {
        throw StateError(
          "Catalog entry '${entry.name}' property '${prop.name}' is a "
          'PropertyType.structured widget property with no structuredRef; a '
          'structured slot must carry a structuredRef resolving to a '
          'registered decoder. Refusing to silently drop the widget.',
        );
      }
      if (_structuredRefDecoderFor(prop, nativeIndex) == null) {
        throw StateError(
          "Catalog entry '${entry.name}' property '${prop.name}' is a "
          'structured value slot whose structuredRef resolves to a structured '
          'type with no registered decoder. A registered structured value '
          'needs an entry in the structured-ref decoder table (plus a matching '
          'runtime decoder and translator recipe). Refusing to silently drop '
          'the widget.',
        );
      }
    }
    if (!_isEmittableProperty(prop, nativeIndex)) {
      return false;
    }
  }
  return true;
}

bool _isNativeRecipeEmittable(
  DecompositionRecipe recipe,
  WidgetEntry entry,
  NativeCatalogIndex index,
) {
  if (recipe.targetArg == null || recipe.construction == null) return false;
  final structured = index.structuredByRef(recipe.structuredRef);
  if (structured == null) return false;
  final construction = recipe.construction!;
  final variant = index.variantByRef(construction.variantRef);
  if (variant == null) return false;
  final owner = index.variantOwner(construction.variantRef);
  if (owner?.wireId != structured.wireId ||
      owner?.library != structured.library) {
    return false;
  }
  final variantFields = factoryVariantCallableFields(variant);
  final variantFieldRefs = <WireId>{
    for (final argMapping in variantFields.argMappings.values)
      ...argMapping.targetFields,
  };
  final parameterFieldRefs = <WireId>{
    for (final parameter in variantFields.parameters)
      ..._targetFieldsForParameter(variant, parameter),
  };
  final parameterIds = {
    for (final parameter in variantFields.parameters) parameter.wireId,
  };
  for (final mapping in recipe.fieldMappings) {
    if (index.structuredField(recipe.structuredRef, mapping.fieldRef) == null) {
      return false;
    }
    if (!variantFieldRefs.contains(mapping.fieldRef)) {
      throw StateError(
        'Native decomposition recipe for ${entry.name} maps field '
        '${mapping.fieldRef.value}, but selected variant '
        '${variant.wireId.value} has no argMapping for that field.',
      );
    }
    if (!parameterFieldRefs.contains(mapping.fieldRef)) {
      throw StateError(
        'Native decomposition recipe for ${entry.name} maps field '
        '${mapping.fieldRef.value}, and selected variant '
        '${variant.wireId.value} has an argMapping for that field, but no '
        'factory parameter emits it.',
      );
    }
    final property = _propertyByWireId(entry, mapping.propertyRef);
    if (property == null) return false;
    if (!_isSupportedNativeTransform(
      mapping.transform,
      property: property,
      index: index,
    )) {
      throw StateError(
        'Native ${_transformKindName(mapping.transform)} transform for '
        '${entry.name}.${property.name} is not supported by factory emission.',
      );
    }
  }
  for (final mapping in recipe.parameterMappings) {
    if (!parameterIds.contains(mapping.parameterRef)) {
      throw StateError(
        'Native decomposition recipe for ${entry.name} maps parameter '
        '${mapping.parameterRef.value}, but selected variant '
        '${variant.wireId.value} has no such factory parameter.',
      );
    }
    final property = _propertyByWireId(entry, mapping.propertyRef);
    if (property == null) return false;
    if (!_isSupportedNativeTransform(
      mapping.transform,
      property: property,
      index: index,
    )) {
      throw StateError(
        'Native ${_transformKindName(mapping.transform)} transform for '
        '${entry.name}.${property.name} is not supported by factory emission.',
      );
    }
  }
  return true;
}

/// Display name for a transform, matching the prior `kind.name` text used in
/// diagnostics.
String _transformKindName(DecompositionValueTransform transform) {
  return switch (transform) {
    IdentityTransform() => 'identity',
    ConstructVariantTransform() => 'constructVariant',
    ProjectListTransform() => 'projectList',
    CoerceScalarTransform() => 'coerceScalar',
  };
}

bool _isSupportedNativeTransform(
  DecompositionValueTransform transform, {
  required PropertyEntry property,
  required NativeCatalogIndex index,
}) {
  switch (transform) {
    case IdentityTransform():
      return true;
    case ConstructVariantTransform(
        :final resultStructuredRef,
        :final invocation,
        :final argumentBindings,
      ):
      if (index.structuredByRef(resultStructuredRef) == null) return false;
      if (index.variantByRef(invocation.variantRef) == null) return false;
      for (final binding in argumentBindings) {
        if (binding is NestedTransformArgumentBinding) {
          if (!_isSupportedNativeTransform(
            binding.nestedTransform,
            property: property,
            index: index,
          )) {
            return false;
          }
        }
        if (binding.nullPolicy == TransformNullPolicy.omitArgument ||
            binding.missingPolicy == TransformMissingPolicy.omitArgument ||
            binding.missingPolicy == TransformMissingPolicy.useDefault) {
          return false;
        }
      }
      return true;
    case ProjectListTransform():
      return _isSupportedNativeProjectList(transform, property);
    case CoerceScalarTransform():
      return false;
  }
}

bool _isSupportedNativeProjectList(
  ProjectListTransform transform,
  PropertyEntry property,
) {
  final itemTransform = transform.itemTransform;
  final shape = property.valueShape;
  if (itemTransform is! IdentityTransform || shape is! ListShape) {
    return false;
  }
  final itemShape = shape.itemShape;
  if (property.type == PropertyType.boxShadowList) {
    return shape.wireCodec == CatalogWireCodec.rfwBoxShadowList &&
        itemShape is StructuredShape;
  }
  return property.type == PropertyType.stringList ||
      property.type == PropertyType.shadowList ||
      property.type == PropertyType.fontFeatureList ||
      property.type == PropertyType.fontVariationList;
}

/// `WidgetEventName` values whose Flutter constructor parameter is a
/// `VoidCallback?`. The mechanical emitter wires these via
/// `source.voidHandler(...)`. Other event names need a per-property
/// `callbackSignature` and route through the typed-handler emit path.
const Set<WidgetEventName> _voidEvents = {
  WidgetEventName.onPressed,
  WidgetEventName.onTap,
  WidgetEventName.onLongPress,
  WidgetEventName.onDoubleTap,
  WidgetEventName.onEnd,
  WidgetEventName.onSheetDismissed,
};

/// Pattern matching `'ValueChanged<T>'` where `T` is either:
///   * a single identifier optionally followed by `?` (nullable) —
///     `'bool'`, `'bool?'`, `'String'`; or
///   * a `List<E>` of a single identifier (optionally nullable element) —
///     `'List<String>'`, `'List<int?>'`.
/// The captured group is the whole `T` (`'bool'`, `'String'`,
/// `'List<String>'`), which threads directly into both the handler's type
/// argument and the typed closure parameter at the emit site.
///
/// The `List<E>` arm carries a settled-selection event — the whole selection
/// fired as one `List<E>` over the rfw `DynamicList` wire (`DynamicList` is a
/// dynamic-safe wire value, so this needs no new wire shape; the scalar arm is
/// byte-identical). `Set<E>` is deliberately NOT accepted: `Set` is not a
/// dynamic-safe rfw value, so a multi-select widget carries its selection as a
/// `List<E>` and materializes the `Set` inside the compiled widget / the host
/// callback adapter, never on the wire.
final RegExp _kValueChangedSignature =
    RegExp(r'^ValueChanged<(\w+\??|List<\w+\??>)>$');

/// Returns the `T` parameter when [signature] matches the
/// `ValueChanged<T>` shape, or `null` when it doesn't.
String? _valueChangedTypeParam(String signature) =>
    _kValueChangedSignature.firstMatch(signature)?.group(1);

/// True when [signature] names a typed-callback shape the emitter
/// knows how to thread through `source.handler<T>(...)`. Closed
/// today to scalar `ValueChanged<T>` shapes; richer signatures
/// (multi-arg callbacks, `ValueSetter`, etc.) extend this when a
/// catalog entry needs them.
bool _isSupportedCallbackSignature(String signature) =>
    _valueChangedTypeParam(signature) != null;

/// Returns the boolean property carrying the `'gateOnPressed'`
/// synthetic strategy when [entry] declares one and is otherwise
/// eligible to use it. Eligibility: the strategy is `'gateOnPressed'`,
/// the property type is `boolean`, the entry fires `onPressed`, and
/// the entry declares an `onPressed` event property to gate.
PropertyEntry? _gatingPropertyOf(WidgetEntry entry) =>
    entry.properties.firstWhereOrNull(
      (p) => p.synthetic == _gateOnPressedSynthetic,
    );

/// True when [prop]'s `synthetic` strategy is one the mechanical
/// emitter knows how to consume on [entry]. `null`-synthetic properties
/// don't reach this check; the caller filters them.
bool _isSupportedSynthetic(PropertyEntry prop, WidgetEntry entry) {
  switch (prop.synthetic) {
    case _gateOnPressedSynthetic:
      // The synthetic gates the entry's onPressed handler; the entry
      // must declare an onPressed fire AND an onPressed event property
      // for the gate to bind to.
      return prop.type == PropertyType.boolean &&
          entry.fires.contains(WidgetEventName.onPressed) &&
          entry.properties.any(
            (p) => p.type == PropertyType.event && p.name == 'onPressed',
          );
    case _iconDataSynthetic:
      // The synthetic wraps the int codepoint as
      // `IconData(value, fontFamily: 'MaterialIcons')`. The wrapped
      // value slots into Flutter's `Icon(IconData icon, ...)`
      // positional first arg, so the property must also be marked
      // positional in the catalog.
      return prop.type == PropertyType.integer && prop.positional;
    case _imageFilterBlurSynthetic:
      // The synthetic pairs `blurSigmaX` + `blurSigmaY` into an
      // `ImageFilter.blur(...)` value. Per-prop gate: typed `real`
      // with the right name. Pair gate: both partners present and
      // both correctly carry the synthetic + type. One walk via Set
      // membership rather than three.
      if (prop.type != PropertyType.real) return false;
      if (prop.name != 'blurSigmaX' && prop.name != 'blurSigmaY') return false;
      final blurNames = entry.properties
          .where(
            (p) =>
                p.synthetic == _imageFilterBlurSynthetic &&
                p.type == PropertyType.real,
          )
          .map((p) => p.name)
          .toSet();
      return blurNames.containsAll({'blurSigmaX', 'blurSigmaY'});
    case _borderRadiusCircularSynthetic:
      // The synthetic wraps a single real (uniform corner radius) as
      // `BorderRadius.circular(<value>)`. The wrap applies whether the
      // property is a direct ctor arg (e.g. ClipRRect.borderRadius) or a
      // flat hoisted out of a BoxDecoration recipe — both emission paths
      // route through `_wrappedValueFor`. When the entry also declares the
      // four corner siblings, the emission becomes the per-corner
      // conditional (still owned by this property).
      return prop.type == PropertyType.real;
    case _borderRadiusCornerSynthetic:
      // A single corner real consumed by the sibling uniform
      // `borderRadiusCircular` property's per-corner reconstruction. The
      // corner is never emitted on its own, so it must be a real AND the
      // entry must declare the uniform `borderRadiusCircular` owner that
      // reads it — an orphan corner has no reconstruction path.
      if (prop.type != PropertyType.real) return false;
      if (!_kBorderRadiusCorners.any((c) => c.property == prop.name)) {
        return false;
      }
      return entry.properties.any(
        (p) => p.synthetic == _borderRadiusCircularSynthetic,
      );
    default:
      return false;
  }
}

/// Returns the property that fills [entry]'s `ChildrenSlot.single` /
/// `ChildrenSlot.list` slot when one exists, or `null` otherwise.
///
/// The single slot expects a property named `'child'` with
/// `PropertyType.widget`; the list slot expects `'children'` with
/// `PropertyType.widgetList`. Both names match the underlying Flutter
/// constructor parameter names so the emitted code constructs the
/// canonical Flutter widget without a name-remap.
PropertyEntry? _canonicalChildPropertyOf(WidgetEntry entry) {
  switch (entry.childrenSlot) {
    case ChildrenSlot.none:
      return null;
    case ChildrenSlot.single:
      return entry.properties.firstWhereOrNull(
        (p) => p.name == 'child' && p.type == PropertyType.widget,
      );
    case ChildrenSlot.list:
      return entry.properties.firstWhereOrNull(
        (p) => p.name == 'children' && p.type == PropertyType.widgetList,
      );
  }
}

bool _isEmittableProperty(
  PropertyEntry prop,
  NativeCatalogIndex? index,
) {
  switch (prop.type) {
    case PropertyType.boolean:
    case PropertyType.integer:
    case PropertyType.real:
    case PropertyType.length:
    case PropertyType.string:
    case PropertyType.stringList:
    case PropertyType.color:
    case PropertyType.edgeInsets:
    case PropertyType.alignment:
    case PropertyType.alignmentXY:
    case PropertyType.offset:
    case PropertyType.fontWeight:
    case PropertyType.duration:
    case PropertyType.curve:
    case PropertyType.gradient:
    case PropertyType.border:
    case PropertyType.boxShadowList:
    case PropertyType.locale:
    case PropertyType.paint:
    case PropertyType.shadowList:
    case PropertyType.fontFeatureList:
    case PropertyType.fontVariationList:
    case PropertyType.textDecoration:
    case PropertyType.shapeBorder:
    // A recursive span map decoded by the bespoke `RestageDecoders.inlineSpan`
    // — mechanically emittable like the other complex-map slots.
    case PropertyType.inlineSpan:
    // A self-describing image map decoded by the bespoke
    // `RestageDecoders.decorationImage` — mechanically emittable like the
    // other complex-map slots.
    case PropertyType.decorationImage:
    // A list of `{value, label}` option maps decoded by the bespoke
    // `RestageDecoders.selectionOptionList` — mechanically emittable like the
    // other complex-map slots.
    case PropertyType.selectionOptionList:
    // A list of booleans decoded by the bespoke `RestageDecoders.booleanList`
    // — mechanically emittable like the other bespoke-decoder list slots.
    case PropertyType.booleanList:
      return true;
    case PropertyType.enumValue:
      // The decoder calls `ArgumentDecoders.enumValue<T>(T.values, ...)`,
      // which needs the runtime enum type. That type is carried on the
      // canonical value shape, with the property's `enumType` as a
      // fallback.
      return _enumDartTypeName(prop) != null;
    case PropertyType.widget:
      // Non-canonical widget properties — additional `Widget?` (or
      // narrower, via `widgetType`) slots beyond the single canonical
      // `'child'` slot. Examples: AppBar.title, MaterialApp.home,
      // Scaffold.body / appBar, IconButton.icon, ListTile.{leading,
      // title, subtitle, trailing}. Emitted as
      // `<name>: source.optionalChild(...)` (or `source.child(...)`
      // when `required`), with an optional downcast when
      // `widgetType` is set. The canonical child slot is dispatched
      // separately via `_canonicalChildPropertyOf` so it lands last
      // (sort_child_properties_last lint).
      return true;
    case PropertyType.widgetList:
      // No non-canonical widgetList in the curated catalog; the
      // single canonical 'children' slot is dispatched via
      // _canonicalChildPropertyOf. Reject defensively here so an
      // accidental second widgetList property surfaces at codegen.
      return false;
    case PropertyType.event:
    case PropertyType.dataReference:
      return false;
    case PropertyType.structured:
      // A structured value slot is mechanically emittable ONLY when it
      // carries a `structuredRef` resolving to a structured type with a
      // registered runtime decoder (the `_kStructuredRefDecoders` table).
      // No `structuredRef`, or a `structuredRef` whose structured type is
      // unregistered, is NOT emittable — emittability is never flipped on
      // for structured slots in the blanket. (Fail-loud is preserved
      // separately: an authored-but-unregistered structured slot reaches
      // `_decoderCallFor`'s loud throw via the decompose path rather than
      // being silently excluded — see the negative-test coverage.)
      return _structuredRefDecoderFor(prop, index) != null;
    case PropertyType.unknown:
      // Local builds construct PropertyEntry from annotations, never
      // from decoded JSON, so PropertyType.unknown should never reach
      // codegen. Surface loudly if it does.
      throw StateError(
        'PropertyType.unknown is a decoder-side forward-compat '
        'sentinel and must not appear in a locally-built catalog.',
      );
  }
}

/// Returns the constructor expression to invoke for [entry], parsed from
/// `flutterType`. The class portion (after `#`) may contain a
/// `.factoryName` suffix (e.g. `Image.network`); the whole thing is the
/// Dart constructor reference. A CUSTOMER widget whose library is aliased in
/// [aliases] is qualified (`s0.BadgeCard` / `s0.Image.network`) so it resolves
/// through the uniform-prefix import; a built-in widget stays bare.
String _ctorExpressionFor(
  WidgetEntry entry, {
  Map<String, String> aliases = const {},
}) {
  final hashIndex = entry.flutterType.indexOf('#');
  if (hashIndex < 0 || hashIndex == entry.flutterType.length - 1) {
    throw StateError(
      "Catalog entry '${entry.name}' has malformed flutterType "
      "'${entry.flutterType}': expected '<package URI>#<ClassName>' or "
      "'<package URI>#<ClassName>.<factoryName>'.",
    );
  }
  return _qualifyName(
    entry.flutterType.substring(hashIndex + 1),
    entry.flutterType.substring(0, hashIndex),
    aliases,
  );
}

String _decodeExpression(
  PropertyEntry prop,
  String widgetName, {
  NativeCatalogIndex? index,
  Map<String, String> aliases = const {},
  bool tolerantNumbers = false,
}) {
  final path = "<Object>['${prop.name}']";
  final decoded = _decoderCallFor(
    prop,
    path,
    index: index,
    aliases: aliases,
    tolerantNumbers: tolerantNumbers,
  );
  // Literal `defaultValue` takes precedence. Otherwise a `required`
  // scalar without a default emits a throw so a malformed blob fails
  // loudly (the SDK surfaces the throw as `PaywallLoadFailed`) rather
  // than rendering a silently-zeroed widget the user can't tell is
  // broken. The throw fallback only applies to property types whose
  // decoder returns nullable — `widget` / `widgetList` / void-handler
  // `event` paths return non-null Flutter values directly (RFW
  // substitutes an error widget / empty list / void handler when the
  // slot is missing).
  final defaultExpr = _defaultExpressionFor(prop, aliases: aliases);
  if (defaultExpr != null) return '$decoded ?? $defaultExpr';
  if (!prop.required) return decoded;
  // Typed-handler events return `T?` from `source.handler<T>(...)`.
  // When the Flutter ctor param is non-nullable (e.g.
  // `CupertinoDatePicker.onDateTimeChanged`), the catalog can't simply
  // throw on missing — binding an event handler is an authoring choice,
  // not a catalog-correctness concern. Emit a no-op closure
  // fallback so the widget renders even when no handler is bound;
  // the typed handler still threads through when a handler is bound.
  if (prop.type == PropertyType.event && prop.callbackSignature != null) {
    final argType = _valueChangedTypeParam(prop.callbackSignature!)!;
    return '$decoded ?? ($argType _) {}';
  }
  // A registered structured-ref decoder returns a nullable Flutter value
  // (e.g. `Size?`), so a required slot can throw on a missing value just
  // like the other nullable-decoder scalar paths.
  final nullable = _structuredRefDecoderFor(prop, index) != null ||
      _decoderReturnsNullable(prop.type);
  if (!nullable) return decoded;
  return '$decoded ?? '
      "(throw ArgumentError('$widgetName.${prop.name} is required.'))";
}

/// True when [_decoderCallFor]'s emission for [type] returns a nullable
/// value (so a `?? <fallback>` clause is meaningful). Non-nullable
/// decoder paths skip the throw fallback in [_decodeExpression].
///
/// `event` is conservatively non-nullable here because the void-handler
/// path (`source.voidHandler(...)`) returns non-null. The typed-handler
/// path (`source.handler<T>(...)`) does return nullable, but
/// [_decodeExpression] handles that case directly with a typed no-op
/// closure fallback rather than the generic throw.
bool _decoderReturnsNullable(PropertyType type) {
  switch (type) {
    case PropertyType.boolean:
    case PropertyType.integer:
    case PropertyType.real:
    case PropertyType.length:
    case PropertyType.string:
    case PropertyType.stringList:
    case PropertyType.color:
    case PropertyType.edgeInsets:
    case PropertyType.alignment:
    case PropertyType.alignmentXY:
    case PropertyType.offset:
    case PropertyType.fontWeight:
    case PropertyType.duration:
    case PropertyType.curve:
    case PropertyType.enumValue:
    case PropertyType.gradient:
    case PropertyType.border:
    case PropertyType.boxShadowList:
    case PropertyType.locale:
    case PropertyType.paint:
    case PropertyType.shadowList:
    case PropertyType.fontFeatureList:
    case PropertyType.fontVariationList:
    case PropertyType.textDecoration:
    case PropertyType.shapeBorder:
    // `RestageDecoders.inlineSpan(...)` returns a nullable `InlineSpan?`.
    case PropertyType.inlineSpan:
    // `RestageDecoders.decorationImage(...)` returns a nullable
    // `DecorationImage?`.
    case PropertyType.decorationImage:
    // `RestageDecoders.selectionOptionList(...)` returns a nullable
    // `List<RestageSelectionOption>?`.
    case PropertyType.selectionOptionList:
    // `RestageDecoders.booleanList(...)` returns a nullable `List<bool>?`.
    case PropertyType.booleanList:
      return true;
    case PropertyType.widget:
    case PropertyType.widgetList:
    case PropertyType.event:
    case PropertyType.dataReference:
      return false;
    case PropertyType.structured:
      // Structured slots are not emitted through the mechanical
      // scalar decoder path; the translator handles them. Treat as
      // non-nullable defensively — the eligibility gate excludes
      // structured properties before reaching here.
      return false;
    case PropertyType.unknown:
      // Local builds construct PropertyEntry from annotations, never
      // from decoded JSON, so PropertyType.unknown should never reach
      // codegen. Surface loudly if it does.
      throw StateError(
        'PropertyType.unknown is a decoder-side forward-compat '
        'sentinel and must not appear in a locally-built catalog.',
      );
  }
}

Set<String> _consumedPropertyNames(
  WidgetEntry entry, {
  required NativeCatalogIndex? nativeIndex,
}) {
  if (nativeIndex == null) {
    return const <String>{};
  }
  final consumed = <String>{};
  for (final recipe in entry.decomposes) {
    for (final mapping in recipe.fieldMappings) {
      final property = _propertyByWireId(entry, mapping.propertyRef);
      if (property != null) consumed.add(property.name);
    }
    for (final mapping in recipe.parameterMappings) {
      final property = _propertyByWireId(entry, mapping.propertyRef);
      if (property != null) consumed.add(property.name);
    }
  }
  return consumed;
}

PropertyEntry? _propertyByWireId(WidgetEntry entry, WireId wireId) =>
    entry.properties.firstWhereOrNull((property) => property.wireId == wireId);

/// Registered runtime decoders for `structured`-typed value slots, keyed by
/// the structured type's name (as carried on its catalog structured entry).
///
/// A `structured` property points at a structured entry via its
/// `structuredRef`; when that entry's name appears here, the mechanical
/// emitter lowers the slot to `<decoder>(source, <path>)` against the
/// named runtime decoder. The decoder reads the structured value's flat
/// wire map (e.g. `Size` → `{width, height}`) and returns the reconstructed
/// Flutter value (or `null` for the caller's default contract).
///
/// THE extension point: a new registered structured value adds one entry
/// here (and a matching runtime decoder + a matching translator recipe that
/// emits the flat wire map). A `structured` property whose structured type
/// is absent from this map is NOT emittable through this path — see
/// [_structuredRefDecoderFor]; an authored-but-unregistered structured slot
/// reaches [_decoderCallFor]'s loud throw rather than being silently dropped.
const Map<String, String> _kStructuredRefDecoders = {
  'Size': 'RestageDecoders.size',
  'BorderSide': 'RestageDecoders.borderSide',
  'TextStyle': 'RestageDecoders.textStyle',
};

/// Resolves the runtime decoder expression registered for [prop]'s structured
/// reference, or `null` when [prop] is not a structured slot, carries no
/// structured reference, the ref doesn't resolve against [index], or the
/// resolved structured type has no registered decoder.
///
/// The structured reference is read from [PropertyEntry.structuredRef] when
/// present, otherwise from the property's resolved [StructuredShape]
/// `valueShape` (a recipe-materialized flat property carries the ref on its
/// shape, not on the top-level field).
///
/// [index] may be `null` (e.g. a single-library emit without native
/// metadata); a structured ref can't be resolved in that case, so the slot
/// is not emittable through the structured-ref path.
String? _structuredRefDecoderFor(
  PropertyEntry prop,
  NativeCatalogIndex? index,
) {
  if (prop.type != PropertyType.structured) return null;
  final ref = _structuredRefOf(prop);
  if (ref == null || index == null) return null;
  final structured = index.structuredByRef(ref);
  if (structured == null) return null;
  return _kStructuredRefDecoders[structured.name];
}

/// The build-time context for reconstructing customer structured values inline:
/// the discovered structured types + their reconstruction plans, both keyed by
/// `sourceType`, map and record plans keyed by slot, the slot ->
/// target-`sourceType` map (which resolves each nominal structured slot without
/// needing an allocated wire ID), and the import-alias map.
///
/// `aliases` maps each referenced CUSTOMER library URI to its unique
/// uniform-prefix import alias (`s0`, `s1`, ...). Every customer type the
/// reconstruction names — a widget constructor, a nested structured
/// constructor, a referenced enum — is emitted QUALIFIED through its library's
/// alias (`s0.Badge`, `s0.Tone`), so two same-name types from different
/// libraries can never collide by construction (the alias scheme keeps both,
/// both render). Built-in types (`dart:`/`package:flutter/`) are absent from
/// the map and stay bare (they resolve through the `widgets.dart` re-exports).
typedef CustomerReconstruction = ({
  Map<String, StructuredEntry> structuredBySourceType,
  Map<String, ReconstructionPlan> plansBySourceType,
  Map<String, MapPlan> mapPlans,
  Map<String, RecordPlan> recordPlans,
  Map<String, String> slotTargets,
  Set<String> nullableStructuredSlots,
  Map<String, String> aliases,
});

/// Qualifies [bareName] with the import alias for [libraryUri] when that
/// library is an aliased customer library, else returns [bareName] unchanged (a
/// built-in type, or no aliasing context). The alias prefixes the WHOLE
/// reference, so a named constructor (`Foo.bar`) or an enum member access
/// (`Tone.values`) qualifies correctly as `s0.Foo.bar` / `s0.Tone.values`.
String _qualifyName(
  String bareName,
  String? libraryUri,
  Map<String, String> aliases,
) {
  if (libraryUri == null) return bareName;
  final alias = aliases[libraryUri];
  return alias == null ? bareName : '$alias.$bareName';
}

/// The import URI (before the `#`) of a `<library-uri>#<ClassName>` reference.
String _libraryUriOf(String qualifiedRef) =>
    qualifiedRef.substring(0, qualifiedRef.indexOf('#'));

/// The defining library URI of [prop]'s enum type, or `null` when [prop] does
/// not carry an [EnumShape] (its enum type comes from `enumType` metadata with
/// no source library, or it is not an enum at all).
String? _enumLibraryUri(PropertyEntry prop) {
  final shape = prop.valueShape;
  return shape is EnumShape ? shape.enumRef.libraryUri : null;
}

/// Whether [ctx] can reconstruct the structured type [sourceType] inline (it
/// was admitted and has both a lowered entry and a reconstruction plan).
bool _canReconstructCustomer(CustomerReconstruction? ctx, String? sourceType) =>
    ctx != null &&
    sourceType != null &&
    ctx.structuredBySourceType.containsKey(sourceType) &&
    ctx.plansBySourceType.containsKey(sourceType);

/// The Dart class name for a `<library-uri>#<ClassName>` [sourceType].
String _typeNameForSourceType(String sourceType) =>
    sourceType.substring(sourceType.indexOf('#') + 1);

// BEGIN CUSTOMER MAP RECONSTRUCTION
MapPlan? _customerMapPropPlan(
  PropertyEntry prop,
  WidgetEntry entry,
  CustomerReconstruction? customer,
) {
  if (customer == null || !isCustomerMapPropertySlot(prop)) return null;
  return customer.mapPlans[structuredSlotKey(entry.flutterType, prop.name)];
}

MapPlan? _customerMapFieldPlan(
  StructuredField field,
  String ownerSourceType,
  CustomerReconstruction ctx,
) {
  if (!isCustomerMapFieldSlot(field)) return null;
  return ctx.mapPlans[structuredSlotKey(ownerSourceType, field.name)];
}

String _customerMapKeyType(
  MapKeyPlan key,
  CustomerReconstruction ctx,
) {
  final enumRef = key.enumRef;
  if (enumRef == null) return 'String';
  return _qualifyName(enumRef.symbolName, enumRef.libraryUri, ctx.aliases);
}

String _customerMapTerminalType(
  MapPlan plan,
  CustomerReconstruction ctx,
) {
  final sourceType = plan.valueSourceType;
  if (sourceType != null) {
    return _qualifyName(
      _typeNameForSourceType(sourceType),
      _libraryUriOf(sourceType),
      ctx.aliases,
    );
  }
  final valueType = plan.valueShape.propertyType;
  switch (valueType) {
    case PropertyType.boolean:
      return 'bool';
    case PropertyType.integer:
      return 'int';
    case PropertyType.real:
    case PropertyType.length:
      return 'double';
    case PropertyType.string:
      return 'String';
    case PropertyType.enumValue:
      final shape = plan.valueShape;
      if (shape is! EnumShape) {
        throw StateError(
          'A customer map enum value plan has no enum shape.',
        );
      }
      return _qualifyName(
        shape.enumRef.symbolName,
        shape.enumRef.libraryUri,
        ctx.aliases,
      );
    case PropertyType.structured:
      throw StateError(
        'A customer map structured value plan has no reconstruction target.',
      );
    case PropertyType.stringList:
      return 'List<String>';
    case PropertyType.color:
      return 'Color';
    case PropertyType.edgeInsets:
      return 'EdgeInsets';
    case PropertyType.alignment:
      return 'AlignmentGeometry';
    case PropertyType.alignmentXY:
      return 'Alignment';
    case PropertyType.offset:
      return 'Offset';
    case PropertyType.fontWeight:
      return 'FontWeight';
    case PropertyType.duration:
      return 'Duration';
    case PropertyType.curve:
      return 'Curve';
    case PropertyType.gradient:
      return 'Gradient';
    case PropertyType.border:
      return 'BoxBorder';
    case PropertyType.boxShadowList:
      return 'List<BoxShadow>';
    case PropertyType.locale:
      return 'Locale';
    case PropertyType.paint:
      return 'Paint';
    case PropertyType.shadowList:
      return 'List<Shadow>';
    case PropertyType.fontFeatureList:
      return 'List<FontFeature>';
    case PropertyType.fontVariationList:
      return 'List<FontVariation>';
    case PropertyType.textDecoration:
      return 'TextDecoration';
    case PropertyType.shapeBorder:
      return 'ShapeBorder';
    case PropertyType.inlineSpan:
      return 'InlineSpan';
    case PropertyType.decorationImage:
      return 'DecorationImage';
    case PropertyType.selectionOptionList:
      return 'List<RestageSelectionOption>';
    case PropertyType.booleanList:
      return 'List<bool>';
    case PropertyType.widget:
    case PropertyType.widgetList:
    case PropertyType.event:
    case PropertyType.dataReference:
    case PropertyType.unknown:
      throw StateError(
        '$valueType cannot be a customer map value.',
      );
  }
}

String _customerMapTypeAt(
  MapPlan plan,
  int keyDepth,
  CustomerReconstruction ctx,
) {
  final keyType = _customerMapKeyType(plan.keys[keyDepth], ctx);
  final valueType = keyDepth + 1 < plan.keys.length
      ? _customerMapTypeAt(plan, keyDepth + 1, ctx)
      : _customerMapTerminalType(plan, ctx);
  return 'Map<$keyType, $valueType>';
}

String _customerMapTerminalValue(
  MapPlan plan,
  List<Object> path, {
  required String ownerLabel,
  required CustomerReconstruction ctx,
  required NativeCatalogIndex? nativeIndex,
  required int depth,
}) {
  final pathLiteral = _pathLiteral(path);
  final sourceType = plan.valueSourceType;
  if (sourceType != null) {
    if (!_canReconstructCustomer(ctx, sourceType)) {
      throw StateError(
        'Customer map $ownerLabel targets an unreconstructable value type.',
      );
    }
    final reconstruction = _emitCustomerReconstruction(
      sourceType,
      path,
      ctx,
      nativeIndex,
      depth: depth,
    );
    return 'source.isMap($pathLiteral) ? $reconstruction '
        ": (throw ArgumentError('$ownerLabel entry value is required.'))";
  }
  final decoded = _decoderCallFor(
    syntheticProperty('value', plan.valueShape),
    pathLiteral,
    index: nativeIndex,
    aliases: ctx.aliases,
  );
  return '$decoded ?? '
      "(throw ArgumentError('$ownerLabel entry value is required.'))";
}

String _customerMapValue(
  MapPlan plan,
  List<Object> path, {
  required String ownerLabel,
  required String requiredMessage,
  required CustomerReconstruction ctx,
  required NativeCatalogIndex? nativeIndex,
  int keyDepth = 0,
  int depth = 0,
}) {
  if (plan.keys.isEmpty) {
    throw StateError('A customer map reconstruction plan has no key layer.');
  }
  final pathLiteral = _pathLiteral(path);
  // Named from the SHARED loop depth, never from [keyDepth]: a map layer is
  // not the only thing that can enclose this loop (a map inside a list element
  // sits under the list's counter), and every path segment below references
  // the enclosing counters by identifier.
  final indexName = 'i$depth';
  final mapName = 'm$depth';
  final keyName = 'k$depth';
  final lengthName = 'n$depth';
  final entryPath = <Object>[...path, _PathIndex(indexName)];
  final keyPath = <Object>[...entryPath, 'key'];
  final valuePath = <Object>[...entryPath, 'value'];
  final keyPlan = plan.keys[keyDepth];
  final keyType = _customerMapKeyType(keyPlan, ctx);
  final valueType = keyDepth + 1 < plan.keys.length
      ? _customerMapTypeAt(plan, keyDepth + 1, ctx)
      : _customerMapTerminalType(plan, ctx);
  final keyEnumRef = keyPlan.enumRef;
  final String keyRead;
  if (keyEnumRef == null) {
    keyRead = 'source.v<String>(${_pathLiteral(keyPath)}) ?? '
        "(throw ArgumentError('$ownerLabel entry key is required.'))";
  } else {
    final qualified =
        _qualifyName(keyEnumRef.symbolName, keyEnumRef.libraryUri, ctx.aliases);
    // A defaulted field changes one value. Defaulting a key can discard the
    // author's entry and insert a different entry that was never sent.
    keyRead = 'ArgumentDecoders.enumValue<$qualified>('
        '$qualified.values, source, ${_pathLiteral(keyPath)}) ?? '
        "(throw ArgumentError('$ownerLabel entry key is not a known "
        "member.'))";
  }
  final value = keyDepth + 1 < plan.keys.length
      ? _customerMapValue(
          plan,
          valuePath,
          ownerLabel: ownerLabel,
          requiredMessage: "'$ownerLabel entry value is required.'",
          ctx: ctx,
          nativeIndex: nativeIndex,
          keyDepth: keyDepth + 1,
          depth: depth + 1,
        )
      : _customerMapTerminalValue(
          plan,
          valuePath,
          ownerLabel: ownerLabel,
          ctx: ctx,
          nativeIndex: nativeIndex,
          depth: depth + 1,
        );
  // The entry count is read ONCE. Left in the condition it is re-evaluated per
  // entry, and each evaluation allocates a fresh path list plus a key and a
  // hash on the customer's device; a nested map multiplies that per level.
  final map = '() { '
      'final $mapName = <$keyType, $valueType>{}; '
      'final $lengthName = source.length($pathLiteral); '
      'for (var $indexName = 0; '
      '$indexName < $lengthName; $indexName++) { '
      'if (!source.isMap(${_pathLiteral(entryPath)})) { '
      "throw ArgumentError('$ownerLabel entry must be an object.'); } "
      'final $keyName = $keyRead; '
      'if ($mapName.containsKey($keyName)) { '
      "throw ArgumentError('$ownerLabel has a duplicate key.'); } "
      '$mapName[$keyName] = $value; } '
      'return $mapName; }()';
  return 'source.isList($pathLiteral) ? $map '
      ': (throw ArgumentError($requiredMessage))';
}

String? _customerMapPropValue(
  PropertyEntry prop,
  WidgetEntry entry,
  CustomerReconstruction? customer,
  NativeCatalogIndex? nativeIndex,
) {
  final plan = _customerMapPropPlan(prop, entry, customer);
  if (plan == null || customer == null) return null;
  final ownerLabel = '${entry.name}.${prop.name}';
  return _customerMapValue(
    plan,
    <Object>[prop.name],
    ownerLabel: ownerLabel,
    requiredMessage: "'$ownerLabel is required.'",
    ctx: customer,
    nativeIndex: nativeIndex,
  );
}

String? _customerMapFieldValue(
  StructuredField field,
  String ownerSourceType,
  List<Object> path,
  CustomerReconstruction ctx,
  NativeCatalogIndex? nativeIndex, {
  required int depth,
}) {
  final plan = _customerMapFieldPlan(field, ownerSourceType, ctx);
  if (plan == null) return null;
  final owner = _typeNameForSourceType(ownerSourceType);
  final ownerLabel = '$owner.${field.name}';
  return _customerMapValue(
    plan,
    path,
    ownerLabel: ownerLabel,
    requiredMessage: "'$ownerLabel is required.'",
    ctx: ctx,
    nativeIndex: nativeIndex,
    depth: depth,
  );
}

RecordPlan? _customerRecordPropPlan(
  PropertyEntry prop,
  WidgetEntry entry,
  CustomerReconstruction? customer,
) {
  if (customer == null || !isCustomerRecordPropertySlot(prop)) return null;
  return customer.recordPlans[structuredSlotKey(entry.flutterType, prop.name)];
}

/// Whether [prop] on [entry] has the build-time plan required to emit its map
/// OR record reconstruction. Maps are checked first; a slot can only be one of
/// the two, so the first plan found decides.
bool _customerReconstructableMapOrRecordProp(
  PropertyEntry prop,
  WidgetEntry entry,
  CustomerReconstruction? customer,
) =>
    _customerMapPropPlan(prop, entry, customer) != null ||
    _customerRecordPropPlan(prop, entry, customer) != null;

/// Emits a Dart record expression from [plan], reading each label below [path].
///
/// Labels emit in the plan's canonical order for deterministic source
/// generation. Every label is an unconditional hard read, enums included:
/// absence, a wrong wire type, and an enum-membership miss all throw rather
/// than fabricating a value the author did not send.
String _customerRecordValue(
  RecordPlan plan,
  List<Object> path, {
  required String ownerLabel,
  required CustomerReconstruction ctx,
  required NativeCatalogIndex? nativeIndex,
}) {
  final labels = <String>[];
  for (final label in plan.labels) {
    final decoded = _decoderCallFor(
      syntheticProperty(label.name, label.shape),
      _pathLiteral([...path, label.name]),
      index: nativeIndex,
      aliases: ctx.aliases,
    );
    final message = "'$ownerLabel.${label.name} is required.'";
    labels.add('${label.name}: $decoded ?? (throw ArgumentError($message))');
  }
  return '(${labels.join(', ')},)';
}

/// The argument value for a MAP or RECORD widget property, or `null` when [p]
/// is neither. The map path is tried first; the two plan kinds are disjoint, so
/// whichever produces a value decides.
///
/// An admitted record slot is non-nullable and carries no wire default, so its
/// map must be present before the label-keyed value can be reconstructed.
String? _customerMapOrRecordPropValue(
  PropertyEntry p,
  WidgetEntry entry,
  CustomerReconstruction? customer,
  NativeCatalogIndex? nativeIndex,
) {
  final map = _customerMapPropValue(p, entry, customer, nativeIndex);
  if (map != null) return map;
  final plan = _customerRecordPropPlan(p, entry, customer);
  if (plan == null || customer == null) return null;
  final pathLiteral = _pathLiteral(<Object>[p.name]);
  final ownerLabel = '${entry.name}.${p.name}';
  final record = _customerRecordValue(
    plan,
    <Object>[p.name],
    ownerLabel: ownerLabel,
    ctx: customer,
    nativeIndex: nativeIndex,
  );
  return 'source.isMap($pathLiteral) ? $record '
      ": (throw ArgumentError('$ownerLabel is required.'))";
}

/// The decoded value for a MAP or RECORD field nested in a customer data
/// class, or `null` when [field] is neither. The map path is tried first; the
/// two plan kinds are disjoint, so whichever produces a value decides.
String? _customerMapOrRecordFieldValue(
  StructuredField field,
  String ownerSourceType,
  List<Object> path,
  CustomerReconstruction ctx,
  NativeCatalogIndex? nativeIndex, {
  required int depth,
}) {
  final map = _customerMapFieldValue(
    field,
    ownerSourceType,
    path,
    ctx,
    nativeIndex,
    depth: depth,
  );
  if (map != null) return map;
  if (!isCustomerRecordFieldSlot(field)) return null;
  final plan = ctx.recordPlans[structuredSlotKey(ownerSourceType, field.name)];
  if (plan == null) return null;
  final owner = _typeNameForSourceType(ownerSourceType);
  final ownerLabel = '$owner.${field.name}';
  final record = _customerRecordValue(
    plan,
    path,
    ownerLabel: ownerLabel,
    ctx: ctx,
    nativeIndex: nativeIndex,
  );
  return 'source.isMap(${_pathLiteral(path)}) ? $record '
      ": (throw ArgumentError('$ownerLabel is required.'))";
}
// END CUSTOMER MAP RECONSTRUCTION

/// The customer structured `sourceType` a widget [prop] on [entry] targets —
/// resolved via the slot map (keyed by the widget's `flutterType` + property
/// name, the same key discovery recorded) — or `null` when [prop] is not a
/// reconstructable customer structured slot.
String? _customerPropSourceType(
  PropertyEntry prop,
  WidgetEntry entry,
  CustomerReconstruction? customer,
) {
  if (customer == null || !isCustomerStructuredPropertySlot(prop)) {
    return null;
  }
  final sourceType =
      customer.slotTargets[structuredSlotKey(entry.flutterType, prop.name)];
  return _canReconstructCustomer(customer, sourceType) ? sourceType : null;
}

/// Whether [prop] on [entry] renders through the inline customer reconstructor.
bool _customerReconstructableProp(
  PropertyEntry prop,
  WidgetEntry entry,
  CustomerReconstruction? customer,
) =>
    _customerPropSourceType(prop, entry, customer) != null;

final class _PathIndex {
  const _PathIndex(this.expression);

  final String expression;
}

String _pathLiteral(List<Object> path) =>
    "<Object>[${path.map(_pathSegmentLiteral).join(', ')}]";

String _pathSegmentLiteral(Object segment) {
  if (segment is _PathIndex) return segment.expression;
  return "'$segment'";
}

/// The argument VALUE expression for a customer structured WIDGET property [p]
/// on [entry] targeting [sourceType] — the LEVEL-0 reconstruction entry, shared
/// by the named and positional arg loops so both emit the same fail-closed
/// value (the named loop prepends `p.name:`, the positional loop emits bare).
///
/// Absent-map behavior by the prop's kind (`p.required` + the build-time
/// nullability signal `customer.nullableStructuredSlots`):
///  * REQUIRED -> presence-check + throw (its target's fields may all be
///    optional, so the leaf fail-closes never fire), never fabricating;
///  * OPTIONAL NULLABLE (`Badge? badge`) -> presence-check to `null` (absent ->
///    null, never crashes on an absent nested-required leaf);
///  * OPTIONAL NON-NULLABLE (`Badge badge = const Badge(...)`) -> reconstruct
///    UNCONDITIONALLY (a `: null` arm would type-error the non-null slot; the
///    absent-with-default reconstructs-from-wire boundary is an accepted
///    boundary for now).
String _customerStructuredPropValue(
  String sourceType,
  PropertyEntry p,
  WidgetEntry entry,
  CustomerReconstruction customer,
  NativeCatalogIndex? nativeIndex,
) {
  if (isCustomerStructuredListShape(p.valueShape)) {
    final slotKey = structuredSlotKey(entry.flutterType, p.name);
    return _customerStructuredListValue(
      sourceType,
      [p.name],
      ctx: customer,
      nativeIndex: nativeIndex,
      elementMessage: "'${entry.name}.${p.name} element must be an object.'",
      requiredMessage: "'${entry.name}.${p.name} is required.'",
      isRequired: p.required,
      isNullable: customer.nullableStructuredSlots.contains(slotKey),
      defaultCode: _defaultExpressionFor(p, aliases: customer.aliases),
    );
  }
  final reconstruction =
      _emitCustomerReconstruction(sourceType, [p.name], customer, nativeIndex);
  final pathLiteral = _pathLiteral([p.name]);
  if (p.required) {
    final message = "'${entry.name}.${p.name} is required.'";
    return 'source.isMap($pathLiteral) ? $reconstruction '
        ': (throw ArgumentError($message))';
  }
  final slotKey = structuredSlotKey(entry.flutterType, p.name);
  if (customer.nullableStructuredSlots.contains(slotKey)) {
    return 'source.isMap($pathLiteral) ? $reconstruction : null';
  }
  return reconstruction;
}

String _customerStructuredListValue(
  String itemSourceType,
  List<Object> path, {
  required CustomerReconstruction ctx,
  required NativeCatalogIndex? nativeIndex,
  required String elementMessage,
  required String requiredMessage,
  required bool isRequired,
  required bool isNullable,
  required String? defaultCode,
  int depth = 0,
}) {
  final listPath = _pathLiteral(path);
  final indexName = 'i$depth';
  final itemPath = <Object>[...path, _PathIndex(indexName)];
  final itemPathLiteral = _pathLiteral(itemPath);
  final item = _emitCustomerReconstruction(
    itemSourceType,
    itemPath,
    ctx,
    nativeIndex,
    depth: depth + 1,
  );
  // The element count is read ONCE, as a second declarator because a
  // collection-for admits no statement ahead of it. Left in the condition it is
  // re-evaluated per element, allocating a fresh path list and a lookup each
  // time, and a nested list multiplies that per level.
  final lengthName = 'n$depth';
  final list = '[for (var $indexName = 0, '
      '$lengthName = source.length($listPath); '
      '$indexName < $lengthName; $indexName++) '
      'source.isMap($itemPathLiteral) ? $item '
      ': (throw ArgumentError($elementMessage))]';
  if (isRequired) {
    return 'source.isList($listPath) ? $list '
        ': (throw ArgumentError($requiredMessage))';
  }
  if (isNullable) {
    return 'source.isList($listPath) ? $list : null';
  }
  if (defaultCode != null) {
    return 'source.isList($listPath) ? $list : $defaultCode';
  }
  return list;
}

/// Emits the inline reconstruction expression for the customer structured type
/// [sourceType], reading each field from the wire map at [path] + the field
/// name.
/// Args are emitted in the plan's constructor order and KIND (positional /
/// named), so a positional-param class doesn't compile-error under named args.
/// Recurses for nested structured fields; fail-closed on a missing required
/// scalar field.
String _emitCustomerReconstruction(
  String sourceType,
  List<Object> path,
  CustomerReconstruction ctx,
  NativeCatalogIndex? nativeIndex, {
  int depth = 0,
}) {
  final structured = ctx.structuredBySourceType[sourceType]!;
  final plan = ctx.plansBySourceType[sourceType]!;
  // Qualify the type through its import alias so two same-name structured
  // types from different libraries never collide (the alias scheme keeps both).
  final typeName = _qualifyName(
    _typeNameForSourceType(sourceType),
    _libraryUriOf(sourceType),
    ctx.aliases,
  );
  final ctorName = plan.namedConstructor == null
      ? typeName
      : '$typeName.${plan.namedConstructor}';
  final fieldsByName = {
    for (final field in structured.fields) field.name: field,
  };
  final args = <String>[];
  for (final arg in plan.args) {
    final field = fieldsByName[arg.fieldName]!;
    final value = _customerFieldDecode(
      field,
      sourceType,
      [...path, arg.fieldName],
      ctx,
      nativeIndex,
      isRequired: arg.isRequired,
      defaultCode: arg.defaultCode,
      defaultEnumValue: arg.defaultEnumValue,
      depth: depth,
    );
    args.add(arg.isNamed ? '${arg.fieldName}: $value' : value);
  }
  return '$ctorName(${args.join(', ')})';
}

/// The decode expression for a single customer structured [field] at [path]. A
/// nested structured field recurses; every other type reuses the built-in
/// [_decoderCallFor] via a synthetic property (so scalars/color/enum decode
/// identically to a widget property). Fail-closed + type-correct:
///  * a REQUIRED leaf field fail-closes on a missing value (throws);
///  * a REQUIRED nested field presence-checks its map (throws when absent)
///    rather than fabricating an empty nested object;
///  * an OPTIONAL NON-NULLABLE field coalesces the nullable decode to its
///    reproduced ctor default — a primitive literal ([defaultCode]) or a
///    customer-enum constant ([defaultEnumValue], qualified here through the
///    field's import alias) — so it type-checks against the non-null parameter;
///  * an OPTIONAL NULLABLE nested field yields `null` on an absent map (never
///    fabricates a nested object from missing wire values).
String _customerFieldDecode(
  StructuredField field,
  String ownerSourceType,
  List<Object> path,
  CustomerReconstruction ctx,
  NativeCatalogIndex? nativeIndex, {
  required bool isRequired,
  required String? defaultCode,
  required String? defaultEnumValue,
  required int depth,
}) {
  final pathLiteral = _pathLiteral(path);
  final mapOrRecordValue = _customerMapOrRecordFieldValue(
    field,
    ownerSourceType,
    path,
    ctx,
    nativeIndex,
    depth: depth,
  );
  if (mapOrRecordValue != null) return mapOrRecordValue;
  if (field.type == PropertyType.structured) {
    final nested =
        ctx.slotTargets[structuredSlotKey(ownerSourceType, field.name)];
    if (_canReconstructCustomer(ctx, nested)) {
      final reconstruction = _emitCustomerReconstruction(
        nested!,
        path,
        ctx,
        nativeIndex,
        depth: depth,
      );
      if (isRequired) {
        // A required nested object: its own fields may all be optional, so the
        // recursion's leaf fail-closes would not fire — presence-check the
        // nested map itself and throw when absent, never fabricate.
        final owner = _typeNameForSourceType(ownerSourceType);
        final message = "'$owner.${field.name} is required.'";
        return 'source.isMap($pathLiteral) ? $reconstruction '
            ': (throw ArgumentError($message))';
      }
      // An optional nested object: presence-check the map and, on an absent
      // map, supply the reproduced ctor default (an optional non-nullable
      // nested field — rare, a primitive default is impossible for a data
      // class so this is excluded upstream) or `null` (an optional nullable
      // nested field). Never fabricate a nested object from missing values.
      final absent = defaultCode ?? 'null';
      return 'source.isMap($pathLiteral) ? $reconstruction : $absent';
    }
  }
  if (isCustomerStructuredListShape(field.valueShape)) {
    final itemSourceType =
        ctx.slotTargets[structuredSlotKey(ownerSourceType, field.name)];
    if (_canReconstructCustomer(ctx, itemSourceType)) {
      final owner = _typeNameForSourceType(ownerSourceType);
      return _customerStructuredListValue(
        itemSourceType!,
        path,
        ctx: ctx,
        nativeIndex: nativeIndex,
        elementMessage: "'$owner.${field.name} element must be an object.'",
        requiredMessage: "'$owner.${field.name} is required.'",
        isRequired: isRequired,
        isNullable: !isRequired && defaultCode == null,
        defaultCode: defaultCode,
        depth: depth,
      );
    }
  }
  final synthetic = PropertyEntry(
    wireId: field.wireId,
    name: field.name,
    type: field.type,
    description: field.description,
    required: isRequired,
    structuredRef: field.structuredRef,
    valueShape: field.valueShape,
  );
  final decoded = _decoderCallFor(
    synthetic,
    pathLiteral,
    index: nativeIndex,
    aliases: ctx.aliases,
  );
  if (isRequired && _decoderReturnsNullable(field.type)) {
    final owner = _typeNameForSourceType(ownerSourceType);
    final message = "'$owner.${field.name} is required.'";
    return '$decoded ?? (throw ArgumentError($message))';
  }
  if (defaultEnumValue != null) {
    // An optional non-nullable ENUM leaf: coalesce the nullable enum decode to
    // its reproduced default, qualified through the field's import alias
    // (`s0.Tone.soft`) so it resolves.
    final enumType = _enumDartTypeName(synthetic);
    if (enumType == null) {
      throw StateError(
        'Field ${field.name} carries an enum default but no enum type '
        'metadata; the reconstruction plan and lowered field disagree.',
      );
    }
    final qualified =
        _qualifyName(enumType, _enumLibraryUri(synthetic), ctx.aliases);
    return '$decoded ?? $qualified.$defaultEnumValue';
  }
  if (defaultCode != null) {
    // An optional non-nullable leaf: coalesce the nullable decode to the
    // reproduced primitive-literal ctor default so it type-checks against the
    // non-null param.
    return '$decoded ?? $defaultCode';
  }
  return decoded;
}

/// The structured reference a `structured` property points at: the top-level
/// `structuredRef` when set, otherwise the ref carried on a resolved
/// [StructuredShape] `valueShape`.
WireIdRef? _structuredRefOf(PropertyEntry prop) {
  final ref = prop.structuredRef;
  if (ref != null) return ref;
  final shape = prop.valueShape;
  return shape is StructuredShape ? shape.structuredRef : null;
}

String _decoderCallFor(
  PropertyEntry prop,
  String path, {
  NativeCatalogIndex? index,
  Map<String, String> aliases = const {},
  bool tolerantNumbers = false,
}) {
  switch (prop.type) {
    case PropertyType.boolean:
      return 'source.v<bool>($path)';
    case PropertyType.integer:
      return 'source.v<int>($path)';
    case PropertyType.real:
    case PropertyType.length:
      // `source.v<double>` is a strict type check: an `int` on the wire reads
      // as null through it, indistinguishable from an absent slot, so the slot
      // silently takes its default. Slots feeding a repaired structured
      // reassembly read tolerantly instead — the repair runs on the assembled
      // value, far too late to recover a number that was dropped here.
      return tolerantNumbers
          ? 'RestageDecoders.number(source, $path)'
          : 'source.v<double>($path)';
    case PropertyType.string:
      return 'source.v<String>($path)';
    case PropertyType.stringList:
      // Fail-safe: a present-but-degenerate list (a non-string element on a
      // corrupt / tamper wire) DROPS the bad element rather than throwing,
      // matching the `booleanList` / `selectionOptionList` present-malformed
      // convention so a malformed wire degrades instead of crashing the render.
      // Absent → null (the required-slot contract still applies upstream).
      return 'RestageDecoders.stringList(source, $path)';
    case PropertyType.color:
      return 'ArgumentDecoders.color(source, $path)';
    case PropertyType.edgeInsets:
      // An inset is layout-bearing: it is subtracted from the space a box or a
      // sliver has to give its child, and the widgets that consume one check it
      // with an `assert` — stripped from release and profile alike. So rfw's
      // decoder, which passes a NaN, an infinity, or a negative component
      // straight through, would land the failure inside `performLayout`, where
      // nothing catches it and no error boundary can see it. Decode through the
      // repair instead.
      return 'RestageDecoders.edgeInsets(source, $path)';
    case PropertyType.alignment:
      return 'ArgumentDecoders.alignment(source, $path)';
    case PropertyType.alignmentXY:
      return 'RestageDecoders.alignmentXY(source, $path)';
    case PropertyType.offset:
      return 'RestageDecoders.offset(source, $path)';
    case PropertyType.fontWeight:
      return 'ArgumentDecoders.enumValue<FontWeight>('
          'FontWeight.values, source, $path)';
    case PropertyType.duration:
      return 'RestageDecoders.duration(source, $path)';
    case PropertyType.curve:
      return 'RestageDecoders.curve(source, $path)';
    case PropertyType.gradient:
      return 'ArgumentDecoders.gradient(source, $path)';
    case PropertyType.border:
      return 'ArgumentDecoders.border(source, $path)';
    case PropertyType.boxShadowList:
      // rfw's `boxShadow` is a single-value decoder; pair with `list`
      // to read the list-of-maps wire shape. The result is
      // `List<BoxShadow>?`. Empty list ≡ no shadows (Flutter's own
      // BoxDecoration default treats the missing slot as no shadows).
      return 'ArgumentDecoders.list<BoxShadow>(source, $path, '
          'ArgumentDecoders.boxShadow)';
    case PropertyType.locale:
      return 'ArgumentDecoders.locale(source, $path)';
    case PropertyType.paint:
      return 'ArgumentDecoders.paint(source, $path)';
    case PropertyType.shadowList:
      return 'RestageDecoders.shadows(source, $path)';
    case PropertyType.fontFeatureList:
      return 'RestageDecoders.fontFeatures(source, $path)';
    case PropertyType.fontVariationList:
      return 'RestageDecoders.fontVariations(source, $path)';
    case PropertyType.textDecoration:
      return 'RestageDecoders.textDecoration(source, $path)';
    case PropertyType.shapeBorder:
      return 'RestageDecoders.shapeBorder(source, $path)';
    case PropertyType.inlineSpan:
      // A recursive span map (Text.rich / TextSpan), decoded into a real
      // `InlineSpan?` by the bespoke depth-bounded decoder.
      return 'RestageDecoders.inlineSpan(source, $path)';
    case PropertyType.decorationImage:
      // A self-describing image map (DecorationImage), decoded into a real
      // `DecorationImage?` by the bespoke image decoder.
      return 'RestageDecoders.decorationImage(source, $path)';
    case PropertyType.selectionOptionList:
      // A list of `{value, label}` option maps (a single-select widget's
      // items), decoded into a real `List<RestageSelectionOption>?` by the
      // bespoke option-list decoder.
      return 'RestageDecoders.selectionOptionList(source, $path)';
    case PropertyType.booleanList:
      // A list of booleans (a multi-toggle widget's per-child selection
      // flags), decoded into a real `List<bool>?` by the bespoke decoder.
      return 'RestageDecoders.booleanList(source, $path)';
    case PropertyType.widget:
      // Required widgets emit `source.child(path)` (returns Widget;
      // RFW substitutes a visible error widget when the slot is
      // absent at runtime). Optional widgets emit
      // `source.optionalChild(path)` (returns Widget?). When
      // `widgetType` is set, the slot is narrower than `Widget?`
      // (e.g. `Scaffold.appBar` is `PreferredSizeWidget?`); append
      // a downcast so the result type-checks against the Flutter
      // ctor parameter.
      final base =
          prop.required ? 'source.child($path)' : 'source.optionalChild($path)';
      if (prop.widgetType == null) return base;
      return prop.required
          ? '$base as ${prop.widgetType}'
          : '$base as ${prop.widgetType}?';
    case PropertyType.widgetList:
      return 'source.childList($path)';
    case PropertyType.enumValue:
      final t = _enumDartTypeName(prop);
      if (t == null) {
        // Eligibility gate should reject enumValue properties without
        // enum type metadata before reaching here. This guard surfaces the
        // bypassed-gate case with the offending property name instead
        // of a bare null-deref.
        throw StateError(
          "enumValue property '${prop.name}' missing enum metadata. "
          'Eligibility gate should have rejected this entry.',
        );
      }
      // A CUSTOMER enum (its defining library aliased) is qualified so it
      // resolves through the uniform-prefix import; a built-in (Flutter) enum
      // stays bare (it comes through the `widgets.dart` re-exports).
      final e = _qualifyName(t, _enumLibraryUri(prop), aliases);
      return 'ArgumentDecoders.enumValue<$e>($e.values, source, $path)';
    case PropertyType.event:
      final signature = prop.callbackSignature;
      if (signature == null) {
        // Void-callback events (`VoidCallback?`): the rfw shortcut
        // wraps the trigger directly.
        return 'source.voidHandler($path)';
      }
      // Typed handler — currently only `ValueChanged<T>` shapes are
      // recognized. The eligibility gate rejects any signature that
      // [_isSupportedCallbackSignature] doesn't accept.
      final argType = _valueChangedTypeParam(signature)!;
      return 'source.handler<$signature>($path, '
          '(HandlerTrigger trigger) => ($argType value) => '
          "trigger(<String, Object?>{'value': value}))";
    case PropertyType.structured:
      // A structured value slot with a registered runtime decoder (a
      // `structuredRef` resolving to a structured type named in
      // `_kStructuredRefDecoders`) lowers to that decoder. Anything else —
      // no `structuredRef`, or a `structuredRef` whose structured type has
      // no registered decoder — has no emission path and surfaces loudly so
      // an authored-but-unsupported structured slot fails the build rather
      // than being silently dropped or defaulted.
      final decoder = _structuredRefDecoderFor(prop, index);
      if (decoder != null) return '$decoder(source, $path)';
      throw StateError(
        'PropertyType.structured slot has no registered decoder. A '
        'structured property must carry a structuredRef resolving to a '
        'structured type registered in the structured-ref decoder table. '
        'Property: $path',
      );
    case PropertyType.dataReference:
      // Data-reference slots resolve via the translator rather than the
      // scalar decoder. The eligibility gate excludes them before reaching
      // here; if one slips through, surface loudly.
      throw StateError(
        '${prop.type} cannot be decoded by the mechanical '
        'emitter. Property: $path',
      );
    case PropertyType.unknown:
      if (isCustomerMapShape(prop.valueShape)) {
        throw StateError(
          'Customer map slot reached the generic decoder path; it must be '
          'emitted through the customer reconstruction path. Property: $path',
        );
      }
      if (isCustomerRecordShape(prop.valueShape)) {
        throw StateError(
          'Customer record slot reached the generic decoder path; it must be '
          'emitted through the customer reconstruction path. Property: $path',
        );
      }
      if (isCustomerStructuredListShape(prop.valueShape)) {
        throw StateError(
          'Customer structured list slot reached the generic decoder path; '
          'it must be emitted through the customer reconstruction path. '
          'Property: $path',
        );
      }
      // Local builds construct PropertyEntry from annotations, never
      // from decoded JSON, so PropertyType.unknown should never reach
      // codegen. Surface loudly if it does.
      throw StateError(
        'PropertyType.unknown is a decoder-side forward-compat '
        'sentinel and must not appear in a locally-built catalog. '
        'Property: $path',
      );
  }
}

/// Returns the Dart source for a `??` fallback when [prop] declares a
/// literal `defaultValue`, or `null` otherwise. Brand-token defaults
/// fall through here as `null` — the underlying Flutter widget's own
/// parameter default (typically theme-resolved at construction time)
/// supplies the value. Brand-token resolution is not wired through this
/// emitter path.
String? _defaultExpressionFor(
  PropertyEntry prop, {
  Map<String, String> aliases = const {},
}) {
  // Theme-binding defaults resolve at render time against the active
  // Flutter theme — codegen emits a call to the runtime resolver
  // (`resolveThemeBinding`, exported from the core runtime package).
  // `FlutterCtorDefault` / `TokenRefDefault` / `null` sources fall through
  // to the legacy `defaultValue` path below; they usually end up returning
  // `null` here (no `??` fallback), so the underlying Flutter ctor default
  // applies.
  final source = prop.defaultSource;
  if (source is ThemeBindingDefault) {
    final path = source.path.path;
    if (path != null) {
      // `resolveThemeBinding` returns `Object?`; cast to the property's
      // nullable Flutter type so the emitted `??` fallback type-checks.
      // The cast is nullable on purpose — a theme property may itself be
      // null (e.g. `iconTheme.color`), and a non-null cast would throw.
      return 'resolveThemeBinding(context, path: ${_dartStringLiteral(path)}) '
          'as ${_nullableFlutterType(prop.type)}';
    }
    // resolverName-only bindings are not currently supported — fall
    // through to no `??` fallback.
    return null;
  }

  final value = source is LiteralDefault ? source.value : prop.defaultValue;
  if (value == null) return null;
  if (value is bool) return value.toString();
  if (value is int) return value.toString();
  if (value is double) return value.toString();
  if (value is String) {
    // String defaults on enum properties carry the enum value name
    // (e.g. `'start'`); render as `<EnumType>.<name>` rather than
    // a string literal so the emitted fallback type-checks against
    // the Flutter ctor parameter.
    final enumType = _enumDartTypeName(prop);
    if (prop.type == PropertyType.enumValue && enumType != null) {
      // A CUSTOMER enum default is qualified through its import alias so it
      // resolves; a built-in (Flutter) enum stays bare.
      final e = _qualifyName(enumType, _enumLibraryUri(prop), aliases);
      return '$e.$value';
    }
    // String defaults on `alignment` properties name a member on
    // `AlignmentDirectional` (e.g. `'topStart'`, `'center'`). The
    // fallback renders as `AlignmentDirectional.<value>` so the
    // emitted code matches the legacy hand-written closures and
    // satisfies non-nullable `AlignmentGeometry` Flutter ctor params.
    if (prop.type == PropertyType.alignment) {
      return 'AlignmentDirectional.$value';
    }
    // String defaults on `alignmentXY` properties name a member on the
    // concrete `Alignment` (e.g. `'center'`). The fallback renders as
    // `Alignment.<value>` so the emitted code satisfies the concrete
    // `Alignment` Flutter ctor parameter (which can't accept the
    // `AlignmentDirectional` the `alignment` branch above emits).
    if (prop.type == PropertyType.alignmentXY) {
      return 'Alignment.$value';
    }
    // String defaults on `offset` properties name a member on `Offset`
    // (e.g. `'zero'`). The fallback renders as `Offset.<value>` so the
    // emitted code supplies the documented default to the concrete `Offset`
    // Flutter ctor parameter when the slot is absent on the wire.
    if (prop.type == PropertyType.offset) {
      return 'Offset.$value';
    }
    // Curve defaults are catalogued as `Curves` member names, not string
    // literals, so the generated fallback renders the Flutter constant.
    if (prop.type == PropertyType.curve) {
      return 'Curves.$value';
    }
    // String defaults on `shapeBorder` properties name the shape's wire
    // type (the same discriminator the runtime decoder reads). The
    // fallback renders the corresponding const `ShapeBorder` so a
    // non-nullable `ShapeBorder` Flutter ctor param still gets the
    // documented default when the slot is absent.
    if (prop.type == PropertyType.shapeBorder) {
      final shapeDefault = _shapeBorderDefaultExpression(value);
      if (shapeDefault != null) return shapeDefault;
    }
    return _dartStringLiteral(value);
  }
  if (value is List && prop.type == PropertyType.edgeInsets) {
    // Catalog encodes EdgeInsets defaults as a 4-element [L, T, R, B]
    // list of doubles (matching the rfw on-wire shape). Translate to
    // an `EdgeInsets.fromLTRB(...)` literal. Reject other shapes early
    // — silently dropping them would lose the declared default at
    // runtime with no diagnostic.
    if (value.length != 4 || !value.every((e) => e is num)) {
      throw StateError(
        "EdgeInsets default for property '${prop.name}' must be a "
        '4-element list of numbers (left, top, right, bottom); got '
        '$value.',
      );
    }
    final ltrb = value.map((e) => '${(e as num).toDouble()}').join(', ');
    return 'const EdgeInsets.fromLTRB($ltrb)';
  }
  // Unsupported default shape; fall through to no-fallback so the
  // emitted code at least compiles. The current registries only carry
  // the literal shapes handled above; richer default expressions
  // (e.g. composite Dart values) would gain support here when needed.
  return null;
}

/// Maps a `shapeBorder` default's wire type discriminator to a const
/// `ShapeBorder` expression. Returns `null` for unrecognized values so
/// the caller can fall through. Currently only the parameter-less
/// `'circle'` shape (used for circular avatar clips) is representable as
/// a default; other shapes carry constructor parameters that a flat
/// default token cannot express.
String? _shapeBorderDefaultExpression(String value) {
  switch (value) {
    case 'circle':
      return 'const CircleBorder()';
    default:
      return null;
  }
}

String? _enumDartTypeName(PropertyEntry prop) {
  final shape = prop.valueShape;
  final enumRef = shape is EnumShape ? shape.enumRef : null;
  return enumRef?.symbolName ?? prop.enumType;
}

/// Renders [value] as a single-quoted Dart string literal, escaping
/// backslashes, single quotes, `$` (so it is a literal, not interpolation),
/// and newlines so the emitted source parses byte-stably.
String _dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

/// Returns the nullable Flutter type a [type] property's value occupies
/// at a ctor-arg call site. Used as the cast target for a theme-binding
/// `??` fallback — `resolveThemeBinding` returns `Object?`, and the
/// theme property it forwards may itself be `null`, so the cast must be
/// nullable. Covers the theme-binding seed-table property types only.
String _nullableFlutterType(PropertyType type) {
  switch (type) {
    case PropertyType.color:
      return 'Color?';
    case PropertyType.length:
    case PropertyType.real:
      return 'double?';
    case PropertyType.fontWeight:
      return 'FontWeight?';
    // No other PropertyType is reachable via a theme-binding seed; if
    // one ever is, surface it loudly rather than emit an unresolvable
    // cast.
    // ignore: no_default_cases
    default:
      throw StateError(
        'No theme-binding cast type for $type. '
        'Theme-binding seeds cover color / length / real / fontWeight.',
      );
  }
}
