import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/surface_publication/recorded_layouts.dart';
import 'package:restage_codegen/src/surface_publication/split_widgets.dart'
    show kPlacementItemsArgument;
import 'package:restage_codegen/src/widget_builder_lowering.dart';
import 'package:restage_shared/restage_shared.dart'
    show WidgetVocabulary, kNativeVoidCallbackType;
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart'
    show knownRecipeStructuredTypes, resolveValueShape, valueShapeNeedsLinking;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The public name of [island]'s mount-free builder.
String islandPreviewName(Island island) => 'restagePreview\$${island.name}';

/// Marks a slot or property argument in an [Island.template].
String islandHole(String name) => '\u0002$name\u0002';

/// Every hole in an island template.
final RegExp islandHolePattern = RegExp('\u0002([A-Za-z0-9_\$]+)\u0002');

/// A delivered widget argument of an island.
final class IslandSlot {
  /// Creates a slot.
  const IslandSlot(
    this.name, {
    required this.list,
    required this.dsl,
    required this.node,
    this.builder,
  });

  /// The argument name.
  final String name;

  /// The argument's expression.
  final AstNode node;

  /// Whether the argument is a list of widgets.
  final bool list;

  /// The delivered content.
  final String dsl;

  /// The app builder whose body this slot delivers, if it is one.
  final AppValueSlot? builder;
}

/// Why an island argument stays in the app's compiled code.
enum IslandCompiledReason {
  /// It's a callback, which runs the app's code.
  callback,

  /// It builds widgets in a form a design can't take.
  builder,

  /// A builder whose body Restage can't deliver.
  builderBody,

  /// An object of a type a design can't carry.
  appObject,

  /// A parameter that takes any value, such as `Object`.
  untyped,

  /// A value of a type only catalog widgets take from a design.
  catalogType,

  /// A value the build computes.
  notLiteral,

  /// A literal Restage can't evaluate without running the app.
  notEvaluable,

  /// A widget Restage can't deliver.
  slotContent,

  /// It matches no parameter.
  unresolved,

  /// Its parameter is the wildcard `_`.
  wildcard,

  /// An argument to a function that renders from the app.
  helperCall,

  /// An argument of a widget the build keeps in a local.
  sharedLocal,
}

/// An island argument that stays in the app's compiled code.
final class IslandCompiledArgument {
  /// Creates a record; [detail] is the type, source or nested refusal the
  /// message names.
  const IslandCompiledArgument(this.name, this.reason, {this.detail});

  /// The parameter name, or the argument's position when it has none.
  final String name;

  /// Why it stays compiled.
  final IslandCompiledReason reason;

  /// What the message names besides the argument.
  final String? detail;

  /// The problem, then a general fix, for the island of [widget];
  /// [appWidget] says whether the app could add it to its catalog.
  String message(String widget, {bool appWidget = true}) {
    final detail = this.detail ?? '';
    final because = switch (reason) {
      IslandCompiledReason.callback =>
        "it's a callback, so it runs the app's code. Try leaving it as it "
            'is: a design changes what `$widget` shows, not what it does.',
      IslandCompiledReason.builder =>
        "it builds widgets in the app's code, and a design takes a builder "
            'only when the app passes it values. Try moving what designs '
            'should change outside the builder.',
      IslandCompiledReason.builderBody =>
        "a design can't take its body. ${_withFix(detail, 'Try moving what '
        'designs should change outside the builder.')}",
      IslandCompiledReason.appObject =>
        "it's ${_article(detail)} `$detail`, which a design can't carry. "
            'Try leaving it as it is: designs change the literal arguments '
            'of `$widget`.',
      IslandCompiledReason.untyped =>
        "its parameter takes any value, so a design can't tell what to "
            'carry. Try leaving it as it is: designs change the typed '
            'literal arguments of `$widget`.',
      IslandCompiledReason.catalogType when appWidget =>
        'a design sets ${_article(detail)} `$detail` only on a catalog '
            'widget. Try adding `$widget` to your widget catalog if designs '
            'should change it.',
      IslandCompiledReason.catalogType =>
        '`$widget` renders from the app here, so it keeps the '
            '`$detail` it is given. Try leaving it as it is: designs '
            'change it where `$widget` is delivered.',
      IslandCompiledReason.notLiteral =>
        'it reads `$detail`, which the app computes. Try writing a literal '
            'if designs should change it.',
      IslandCompiledReason.notEvaluable =>
        "Restage can't read `$detail` without running the app. Try "
            'writing it as a plain literal if designs should change it.',
      IslandCompiledReason.slotContent =>
        "a design can't deliver the widget it passes. ${_withFix(detail, 'Try '
        'a widget from your widget catalog there.')}",
      IslandCompiledReason.unresolved =>
        "Restage can't match it to a parameter of `$widget`. Try running "
            '`dart analyze` and fixing what it reports.',
      IslandCompiledReason.wildcard =>
        'its parameter is the wildcard `_`, so a design has no name to set '
            'it by. Try naming the parameter.',
      IslandCompiledReason.helperCall =>
        "it's an argument to `$widget`, a function that renders from the "
            'app. Try making `$widget` a widget class if designs should '
            'change it.',
      IslandCompiledReason.sharedLocal =>
        'the build keeps `$widget` in the local `$detail`. Try building it '
            'where it is placed if designs should change it.',
    };
    return "`$name` stays in the app's code: $because";
  }

  static String _article(String word) =>
      RegExp('^[AEIOUaeiou]').hasMatch(word) ? 'an' : 'a';

  // A nested refusal, ending with [fix] when it gives none of its own.
  static String _withFix(String refusal, String fix) {
    final sentence = refusal.isEmpty || refusal.endsWith('.')
        ? refusal
        : '$refusal.';
    return sentence.contains('Try ') ? sentence : '$sentence $fix'.trim();
  }
}

/// A literal argument of an island, passed from the payload.
final class IslandProperty {
  /// Creates a property.
  const IslandProperty(
    this.name, {
    required this.argument,
    required this.shape,
    required this.dsl,
    required String fallback,
    this.closed = true,
    this.nullable = false,
  }) : _fallback = fallback;

  /// Whether the value as written reads nothing the build declares, so a
  /// preview may copy it.
  final bool closed;

  /// Whether the widget's parameter takes null.
  final bool nullable;

  /// The argument name.
  final String name;

  /// The argument as written, named or positional.
  final Argument argument;

  /// How the payload carries it.
  final CatalogValueShape shape;

  /// The property type of [shape].
  PropertyType get type => shape.propertyType;

  /// The payload value.
  final String dsl;

  final String _fallback;

  /// The mount's source for the value as written, used when the payload
  /// omits it; [slot] spells the mount's inputs.
  String fallbackSource(String Function(String) slot, {String? itemSource}) =>
      mountTemplateSource(_fallback, slot, itemSource: itemSource);

  /// The preview's source for the value, given its [decoded] payload read:
  /// the value as written when it is closed, else the payload's alone.
  String previewSource(String decoded, String Function(String) slot) => closed
      ? '($decoded ?? ${fallbackSource(slot, itemSource: 'restageItem')})'
      : nullable
      ? decoded
      : '($decoded)!';
}

/// Why an argument of [type] can't be an island property, or null when a
/// design can carry it.
IslandCompiledReason? islandTypeReason(DartType? type) {
  if (type is FunctionType) {
    return classifyHoistType(type.returnType) is HoistIsWidget
        ? IslandCompiledReason.builder
        : IslandCompiledReason.callback;
  }
  if (islandPropertyShape(type) != null) return null;
  if (type == null ||
      type is DynamicType ||
      type is TypeParameterType ||
      type.isDartCoreObject) {
    return IslandCompiledReason.untyped;
  }
  final catalogOnly =
      resolveValueShape(type) != null ||
      knownRecipeStructuredTypes.contains(type.element?.name);
  return catalogOnly
      ? IslandCompiledReason.catalogType
      : IslandCompiledReason.appObject;
}

/// Whether [island] is an app widget its app could add to its catalog: one
/// the app declares, an island only for want of an entry.
bool islandCanJoinCatalog(Island island) {
  final cause = island.reason?.code;
  final element = switch (island.node) {
    InstanceCreationExpression(:final constructorName) =>
      constructorName.type.element,
    _ => null,
  };
  final uri = element?.library?.uri.toString() ?? '';
  return (cause == null ||
          cause == IssueCode.unknownWidget ||
          cause.name.startsWith('customWidget')) &&
      !uri.startsWith('dart:') &&
      !uri.startsWith('package:flutter/');
}

/// The name of [type] as a message writes it, without its `?`.
String islandTypeName(DartType type) =>
    type.getDisplayString().replaceFirst(RegExp(r'\?$'), '');

/// The name a design sets [parameter] by: its own, without a leading
/// underscore, or its position when that name is taken or not a legal one.

String? islandArgumentName(FormalParameterElement? parameter) {
  final name = parameter?.name;
  if (name == null || name == '_') return null;
  final public = name.replaceFirst(RegExp('^_+'), '');
  if (public == name) return name;
  final names = switch (parameter!.enclosingElement) {
    final ExecutableElement owner => [
      for (final other in owner.formalParameters) other.name,
    ],
    _ => [name],
  };
  // Another parameter may already have, or strip to, the same name.
  final taken = {
    for (final other in names)
      if (other != name) ...[other, other?.replaceFirst(RegExp('^_+'), '')],
  };
  return public != 'key' &&
          !taken.contains(public) &&
          isPublicDartIdentifier(
            public,
            position: DartIdentifierPosition.namedParameter,
          )
      ? public
      : 'argument${names.indexOf(name) + 1}';
}

/// The catalog shape a literal island argument of [type] crosses as, if the
/// payload can carry it without naming an app type.
CatalogValueShape? islandPropertyShape(DartType? type) {
  if (type == null) return null;
  final shape = resolveValueShape(type);
  if (shape == null || valueShapeNeedsLinking(shape)) return null;
  return switch (shape.propertyType) {
    PropertyType.widget ||
    PropertyType.widgetList ||
    PropertyType.widgetBuilder ||
    PropertyType.scalarCallback ||
    PropertyType.event ||
    PropertyType.enumValue ||
    PropertyType.structured ||
    PropertyType.dataReference ||
    PropertyType.unknown => null,
    _ => shape,
  };
}

/// A widget expression that renders from the app's compiled code.
final class Island {
  /// Creates an island.
  Island({
    required this.id,
    required this.name,
    required this.widget,
    required this.screen,
    required this.location,
    required this.reason,
    required this.slots,
    required this.properties,
    required String template,
    required this.library,
    required this.node,
    required this.scope,
    this.compiled = const [],
    this.items = const [],
    this.reads = const {},
    this.placements = const [],
    String? preview,
  }) : _template = template,
       _preview = preview;

  /// The island's expression.
  final AstNode node;

  /// The call sites and unrolled iterations from the surface's build.
  final String scope;

  /// The island library namespace.
  final String library;

  /// The structural ID: surface, [scope], widget type and the order the
  /// scope uses its islands of that type.
  final String id;

  /// The widget name the payload uses, derived from [id].
  final String name;

  /// The widget type as written.
  final String widget;

  /// The surface class's name as written.
  final String screen;

  /// The island as a developer reads it, `<widget> in <screen>`, with an
  /// ordinal when the screen has several of that widget; positionless, so it
  /// may be published. Set by [assignIslandTokens].
  late final String label;

  /// Where the island's expression is.
  final String location;

  /// The first construct the compiler could not lower; `null` for a local
  /// the mount computes once.
  final Issue? reason;

  /// Delivered widget arguments.
  final List<IslandSlot> slots;

  /// Literal arguments the payload passes.
  final List<IslandProperty> properties;

  /// Arguments that stay in the app's compiled code.
  final List<IslandCompiledArgument> compiled;

  final String _template;

  /// The mount's source for the island; [slot] spells the mount's inputs and
  /// [hole] each slot or property argument.
  String source(
    String Function(String) slot, {
    required String Function(String argument) hole,
    String? itemSource,
  }) => mountTemplateSource(
    _template,
    slot,
    itemSource: itemSource,
  ).replaceAllMapped(islandHolePattern, (match) => hole(match[1]!));

  final String? _preview;

  /// The island's source without its mount, used where no mount runs (a
  /// preview): arguments that need the mount are left out when optional and
  /// do nothing when they are void callbacks. `null` when a required one
  /// needs the mount; it then shows as a placeholder.
  String? previewSource(String Function(String argument) hole) =>
      _preview == null
      ? null
      : mountTemplateSource(
          _preview,
          (slot) => slot == kRootContext ? 'restageContext' : slot,
        ).replaceAllMapped(islandHolePattern, (match) => hole(match[1]!));

  /// The lists of the loops around the island, outermost first; the island
  /// takes its position in each.
  final List<String> items;

  /// The levels of [items] whose item the island reads.
  final Set<int> reads;

  /// Where the island is placed, one entry per exclusive placement: the node
  /// and the build locals it is reached through, outermost first, each read
  /// and the initializer it stands for.
  final List<
    ({
      AstNode at,
      List<({SimpleIdentifier read, Expression initializer})> through,
    })
  >
  placements;

  /// What fit compares: inputs and slots, by name and type.
  late final String interface = [
    for (final slot in slots)
      'slot ${slot.name}${slot.list ? '[]' : ''}'
          '${slot.builder?.signature ?? ''}',
    for (final property in properties)
      'property ${property.name}: ${property.type.name}',
    for (final (level, _) in items.indexed) 'item $level',
  ].join('\n');

  /// What fit matches published content against, set by [assignIslandTokens].
  late final String token;

  /// The implementation hash: the compiled code, not the literals a design
  /// delivers, so a literal edit keeps a twin island's fit token.
  late final String implementation = crypto.sha256
      .convert(
        utf8.encode(
          [
            canonicalHoistSource(
              _template.replaceAllMapped(
                islandHolePattern,
                (m) => 'hole\$${m[1]}',
              ),
            ),
            interface,
            items.join(','),
            reads.join(','),
          ].join('\n'),
        ),
      )
      .toString()
      .substring(0, 16);
}

/// The structural ID and payload name of the [ordinal]th island of [widget]
/// in [scope] of [surface].
({String id, String name}) islandIdentity(
  ({String name, String method, String screen}) surface,
  String scope,
  String widget,
  int ordinal,
) {
  final path = scope.isEmpty ? '' : '>$scope';
  final stem =
      [
            _identifierPart(surface.name),
            ...scope.split('>'),
            widget,
            '$ordinal',
          ]
          .where((part) => part.isNotEmpty)
          .join('_')
          .replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  return (
    id: '${surface.name}.${surface.method}$path/$widget#$ordinal',
    name: stem.startsWith('_') ? 'Island$stem' : stem,
  );
}

// [id] in identifier characters, one to one: `_` doubles, any other
// character outside letters and digits is `_x<hex>_`, and a leading digit
// takes a `_d` prefix no other id can produce.
String _identifierPart(String id) {
  final encoded = StringBuffer(id.startsWith(RegExp('[0-9]')) ? '_d' : '');
  for (final rune in id.runes) {
    final character = String.fromCharCode(rune);
    encoded.write(switch (character) {
      '_' => '__',
      _ when RegExp('[A-Za-z0-9]').hasMatch(character) => character,
      _ => '_x${rune.toRadixString(16)}_',
    });
  }
  return encoded.toString();
}

/// The widget type [node] constructs, as written.
String islandWidgetType(Expression node) => switch (node) {
  InstanceCreationExpression(:final constructorName) =>
    '${constructorName.type.name.lexeme}'
        '${constructorName.name == null ? '' : '.${constructorName.name!.name}'}',
  MethodInvocation(:final methodName) => methodName.name,
  _ => node.runtimeType.toString(),
};

/// The surface whose method contains [root], named by its [id] when it has
/// one, which is unique in its package; a `State`'s surface is its widget.
///
/// [screen] is the surface class's name as written.
({String name, String method, String screen}) islandSurface(
  AstNode root, {
  String? id,
}) {
  final element = root
      .thisOrAncestorOfType<ClassDeclaration>()
      ?.declaredFragment
      ?.element;
  final screen = (stateWidgetOf(element) ?? element)?.name ?? '';
  return (
    screen: screen,
    name: id ?? screen,
    method: root.thisOrAncestorOfType<MethodDeclaration>()?.name.lexeme ?? '',
  );
}

/// [call]'s scope step: its name and ordinal among same-named calls in its
/// declaration.
String islandCallStep(MethodInvocation call) {
  final name = call.methodName.name;
  final declaration =
      call.thisOrAncestorMatching(
        (n) => n is FunctionDeclaration || n is MethodDeclaration,
      ) ??
      call.root;
  final calls = <MethodInvocation>[];
  declaration.accept(_Calls(name, calls));
  calls.sort((a, b) => a.offset.compareTo(b.offset));
  return '$name${calls.indexWhere((peer) => identical(peer, call))}';
}

final class _Calls extends RecursiveAstVisitor<void> {
  _Calls(this.name, this.calls);

  final String name;
  final List<MethodInvocation> calls;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == name) calls.add(node);
    super.visitMethodInvocation(node);
  }
}

/// Why the generated mount keeps part of a surface.
enum MountReason {
  /// A root wrapper the payload cannot carry.
  notDelivered,

  /// A root builder; its parameters become values.
  builder,

  /// The surface's own `State`, moved whole.
  state,
}

/// Whether [value] is an action: a void callback the mount computes.
bool isIslandAction(HoistedValue value) {
  final contract = value.nativeContract;
  return contract != null &&
      (contract.type == kNativeVoidCallbackType ||
          contract.call?.result.nativeType == kNativeVoidCallbackType);
}

WireId _wire(String kind, String seed) {
  final digest = crypto.sha256.convert(utf8.encode(seed)).toString();
  final sequence = int.parse(digest.substring(0, 7), radix: 16) + 1;
  return WireId('$kind${'$sequence'.padLeft(4, '0')}');
}

/// Sets the label and fit token of each of [islands], one surface's, in the
/// order the surface uses them. The token is the ID and interface, plus the
/// implementation when another island has the same widget type and interface,
/// since only those can trade places unnoticed.
void assignIslandTokens(Iterable<Island> islands) {
  final shapes = <(String, String), int>{};
  final widgets = <String, int>{};
  for (final island in islands) {
    final shape = (island.widget, island.interface);
    shapes[shape] = (shapes[shape] ?? 0) + 1;
    widgets[island.widget] = (widgets[island.widget] ?? 0) + 1;
  }
  final seen = <String, int>{};
  for (final island in islands) {
    final seed = [
      island.id,
      island.interface,
      if (shapes[(island.widget, island.interface)]! > 1) island.implementation,
    ];
    island.token = _wire('w', seed.join('\n')).value;
    final ordinal = seen[island.widget] = (seen[island.widget] ?? 0) + 1;
    island.label =
        '${island.widget} in ${island.screen}'
        '${widgets[island.widget]! > 1 && ordinal > 1 ? ' (${_nth(ordinal)})' : ''}';
  }
}

String _nth(int n) =>
    '$n${switch (n % 100) {
      11 || 12 || 13 => 'th',
      _ => switch (n % 10) {
        1 => 'st',
        2 => 'nd',
        3 => 'rd',
        _ => 'th',
      },
    }}';

/// The islands of a mount, as its host contract lists them.
Map<String, String> islandHostFacet(Iterable<Island> islands) => {
  for (final island in islands)
    WidgetVocabulary.qualifiedName(island.library, island.name): island.token,
};

/// The catalog entry of [island]; its wire ID is the island's fit token.
WidgetEntry islandWidgetEntry(Island island) {
  PropertyEntry property(
    String name,
    PropertyType type, [
    CatalogValueShape? shape,
    WidgetBuilderContract? builder,
  ]) => PropertyEntry(
    wireId: _wire('p', '${island.id}/$name'),
    name: name,
    type: type,
    description: name,
    required: true,
    valueShape: shape,
    builderContract: builder,
  );
  return WidgetEntry(
    wireId: WireId(island.token),
    name: island.name,
    library: WidgetLibrary.custom(island.library),
    category: null,
    description: island.label,
    flutterType: island.name,
    childrenSlot: ChildrenSlot.none,
    itemInputs: island.items.length,
    properties: [
      for (final slot in island.slots)
        if (slot.builder case final builder?)
          property(
            slot.name,
            PropertyType.widgetBuilder,
            null,
            builder.contract,
          )
        else
          property(
            slot.name,
            slot.list ? PropertyType.widgetList : PropertyType.widget,
          ),
      for (final value in island.properties)
        property(value.name, value.type, value.shape),
      if (island.items.isNotEmpty)
        property(kPlacementItemsArgument, PropertyType.integerList),
    ],
  );
}

/// [catalog] with each of [islands] as a widget of its island library.
Catalog withIslands(Catalog catalog, Iterable<Island> islands) {
  final entries = {for (final island in islands) island.name: island};
  if (entries.isEmpty) return catalog;
  return Catalog(
    schemaVersion: catalog.schemaVersion,
    generatedAt: catalog.generatedAt,
    libraries: {
      ...catalog.libraries,
      for (final island in entries.values)
        WidgetLibrary.custom(island.library): const LibraryInfo(
          version: '1.0.0',
          islands: true,
        ),
    },
    widgets: [
      ...catalog.widgets,
      for (final island in entries.values) islandWidgetEntry(island),
    ],
    structuredTypes: catalog.structuredTypes,
    unions: catalog.unions,
    designTokens: catalog.designTokens,
    exclusions: catalog.exclusions,
    flutterVersion: catalog.flutterVersion,
    compatRules: catalog.compatRules,
  );
}

/// Stands for the runtime import prefix in a recorded build's source.
const String kSdkPrefixMarker = '\u0007';

/// Marks the generated mount's class name in a lifted `State`.
const String kMountNameMarker = '\u0006';

/// How a mount takes over a surface's own code: the root shell, and the
/// surface's `State` when it does not lower.
final class MountSplit {
  /// Creates a split.
  const MountSplit({
    required this.shell,
    required this.kept,
    required this.designRoot,
    this.state,
    this.recorded,
    this.recordProblem,
    this.recordedBuild,
  });

  /// The chain nodes the mount keeps, each with the child it wraps.
  final List<({Expression node, Expression next})> kept;

  /// The top of the delivered design.
  final Expression designRoot;

  /// This split with [recorded] as its build, written from [recordedBuild],
  /// or [problem] when the build can't be recorded.
  MountSplit withRecorded(
    String? recorded, [
    RecordedBuild? recordedBuild,
    Issue? problem,
  ]) => MountSplit(
    shell: shell,
    kept: kept,
    designRoot: designRoot,
    state: state,
    recorded: recorded,
    recordProblem: problem,
    recordedBuild: recordedBuild,
  );

  /// Why the mount can't be generated: its build can't be recorded.
  final Issue? recordProblem;

  /// The build as the app wrote it, as a function that records each value
  /// the design reads where it computes it.
  final String? recorded;

  /// The records [recorded] writes, on the app's own build.
  final RecordedBuild? recordedBuild;

  /// The mount's source for [recorded]; [slot] spells the mount's inputs.
  String? recordedSource(String Function(String) slot) =>
      recorded == null ? null : mountTemplateSource(recorded!, slot);

  /// The wrappers and builders the mount keeps, outermost first.
  final List<({String widget, String location, MountReason reason})> shell;

  /// The lifted `State`.
  final LiftedState? state;
}

/// A surface's `State` that moves into its generated mount.
final class LiftedState {
  /// Creates a lifted State from its class header and members, which spell
  /// the surface's type as [kMountNameMarker].
  LiftedState({
    required this.name,
    required this.location,
    required String header,
    required List<String> members,
    required this.updates,
    this.customBase = false,
  }) : _header = header,
       _members = members;

  /// Whether the State declares `didUpdateWidget`, which the mount calls
  /// with the previous surface instance.
  final bool updates;

  /// Whether the State extends a base other than Flutter's `State`, which
  /// may need the surface's own base kind.
  final bool customBase;

  /// The State class's name.
  final String name;

  /// Where the State is declared.
  final String location;

  final String _header;
  final List<String> _members;

  /// The class header after the class name, naming the mount [mountName].
  String header(String mountName) =>
      _header.replaceAll(kMountNameMarker, mountName);

  /// The class members, naming the mount [mountName] and reading the
  /// mount's slots through [slot].
  List<String> members(String mountName, String Function(String) slot) => [
    for (final member in _members)
      mountTemplateSource(member.replaceAll(kMountNameMarker, mountName), slot),
  ];
}

/// The widget class [state] is the `State` of, when it is a Flutter `State`.
ClassElement? stateWidgetOf(ClassElement? state) {
  for (final type in [...?state?.allSupertypes]) {
    final widget = type.typeArguments.singleOrNull?.element;
    if (type.element.name == 'State' &&
        type.element.library.identifier ==
            'package:flutter/src/widgets/framework.dart' &&
        widget is ClassElement) {
      return widget;
    }
  }
  return null;
}

/// Whether [node] is code that renders from the app: inside an island but
/// outside its slots, or inside a kept shell node but outside its child.
bool rendersFromApp(AstNode node, List<Island> islands, MountSplit? split) {
  Object? unit(AstNode n) => switch (n.root) {
    final CompilationUnit unit => unit.declaredFragment?.source.uri ?? unit,
    final root => root,
  };
  bool within(AstNode outer) =>
      unit(node) == unit(outer) &&
      node.offset >= outer.offset &&
      node.end <= outer.end;
  if (split != null &&
      split.kept.any((kept) => within(kept.node) && !within(kept.next))) {
    return true;
  }
  return islands.any(
    (island) =>
        within(island.node) && !island.slots.any((slot) => within(slot.node)),
  );
}

/// A widget library named [namespace] that the compiler keeps for the
/// package's app-rendered widgets.
Issue islandNamespaceTakenIssue(String namespace) => Issue(
  code: IssueCode.islandNamespaceTaken,
  message:
      "The library namespace `'$namespace'` is reserved for widgets "
      'Restage generates for this package. Try choosing another namespace.',
  location: namespace,
);

/// The Restage bug of two different app-rendered widgets, [widget] at
/// [location], compiling under one generated name.
Issue islandNameConflictIssue(String widget, String location) => Issue(
  code: IssueCode.islandNameConflict,
  message:
      '$widget at $location compiled to two different app-rendered '
      'widgets under one name. Report this as a Restage bug.',
  location: location,
);

/// Whether [element] is an instance field, getter or method.
bool isInstanceMember(Element element) => switch (element) {
  ConstructorElement() => false,
  ExecutableElement(:final isStatic) => !isStatic,
  FieldElement(:final isStatic) => !isStatic,
  _ => false,
};

/// Whether [element] is an instance member of [owner] or of a supertype.
bool isInstanceMemberOf(ClassElement owner, Element element) {
  final declaring = element.enclosingElement;
  return isInstanceMember(element) &&
      (declaring == owner ||
          owner.allSupertypes.any((type) => type.element == declaring));
}

/// [source] as a developer reads it in a message: one line, shortened with
/// an ellipsis past [limit] characters.
String readableSource(String source, {int limit = 60}) {
  final line = source.replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length <= limit ? line : '${line.substring(0, limit - 1)}…';
}
