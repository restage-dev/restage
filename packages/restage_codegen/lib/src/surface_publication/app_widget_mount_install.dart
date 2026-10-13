import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:restage_shared/restage_shared.dart' show WidgetVocabulary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _sdkLibrary = 'package:restage/restage.dart';
const String _aliasStem = r'_$restageLibrary';
const Set<String> _languageTypes = {'void', 'dynamic', 'Never'};

/// How a generated mount installs the app widgets its surface draws.
///
/// `libraries` is the `SurfaceVocabulary.libraries` source, `null` when the
/// surface draws none or cannot install them; `fragments` are the factory
/// declarations the owning part must carry; `problem` says why nothing was
/// installed.
typedef AppWidgetMountInstall = ({
  String? libraries,
  List<String> fragments,
  String? problem,
});

const AppWidgetMountInstall _nothing =
    (libraries: null, fragments: <String>[], problem: null);

/// Where the app widget factory sidecar sits in a package.
const String kAppWidgetFactoriesPath =
    'lib/src/widget_catalog/app_widget_factories.json';

/// The package's app widget factories, emitted once per build and spelled for
/// each generated part that installs them.
final class AppWidgetMountFactories {
  AppWidgetMountFactories._(
    this._factories,
    this._uriByAlias,
    this._versions,
  );

  /// Builds the factories of every admitted widget in [collection].
  factory AppWidgetMountFactories.fromCollection(
    RestageWidgetCollection collection,
  ) {
    final uris = referencedAppWidgetLibraryUris(
      collection.widgets,
      structuredTypes: collection.structuredTypes,
      slotTargets: collection.slotTargets,
      mapPlans: collection.mapPlans,
      recordPlans: collection.recordPlans,
    ).where((uri) => uri != 'dart:core').toList()
      ..sort();
    // Every library is named through a placeholder prefix, spelled later for
    // the library that owns the part.
    final aliases = {
      for (var i = 0; i < uris.length; i++) uris[i]: '$_aliasStem$i',
    };
    final custom = collection.structuredTypes.isEmpty &&
            collection.mapPlans.isEmpty &&
            collection.recordPlans.isEmpty
        ? null
        : (
            structuredBySourceType: {
              for (final structured in collection.structuredTypes)
                structured.sourceType: structured,
            },
            plansBySourceType: collection.reconstructionPlans,
            mapPlans: collection.mapPlans,
            recordPlans: collection.recordPlans,
            slotTargets: collection.slotTargets,
            nullableStructuredSlots: collection.nullableStructuredSlots,
            aliases: aliases,
          );
    final factories = <String, _Factory>{};
    for (final entry in collection.widgets) {
      final body = emitFactoryFunction(
        entry,
        custom: custom,
        aliases: aliases,
        customChildProperties: true,
      );
      if (body == null) continue;
      factories[WidgetVocabulary.qualifiedName(
        entry.library.namespace,
        entry.name,
      )] = _Factory(functionNameFor(entry), body);
    }
    return AppWidgetMountFactories._(
      factories,
      {for (final MapEntry(:key, :value) in aliases.entries) value: key},
      collection.stampedCapabilityVersions,
    );
  }

  /// Reads the factories [toJson] wrote.
  factory AppWidgetMountFactories.fromJson(Map<String, Object?> json) {
    final factories = json['factories']! as Map<String, Object?>;
    return AppWidgetMountFactories._(
      {
        for (final MapEntry(:key, :value) in factories.entries)
          if (value
              case {
                'function': final String function,
                'source': final String source
              })
            key: _Factory(function, source),
      },
      (json['libraries']! as Map<String, Object?>).cast<String, String>(),
      (json['capabilityVersions']! as Map<String, Object?>).cast<String, int>(),
    );
  }

  /// A package with no app widget.
  static final AppWidgetMountFactories none =
      AppWidgetMountFactories._(const {}, const {}, const {});

  final Map<String, _Factory> _factories;
  final Map<String, String> _uriByAlias;
  final Map<String, int> _versions;
  final Map<LibraryElement, _PartSpeller> _spellers = Map.identity();
  final Map<LibraryElement, Map<String, String>> _functionsByLibrary =
      Map.identity();

  /// Whether the package has no app widget factory.
  bool get isEmpty => _factories.isEmpty;

  /// The sidecar form [AppWidgetMountFactories.fromJson] reads.
  Map<String, Object?> toJson() => {
        'libraries': _uriByAlias,
        'capabilityVersions': _versions,
        'factories': {
          for (final MapEntry(:key, :value) in _factories.entries)
            key: {'function': value.function, 'source': value.source},
        },
      };

  /// Plans registration of complete custom libraries used by [widgetNames].
  /// Delivery may select any widget within an admitted library version.
  /// [takenNames] prevents local name collisions. An inaccessible widget leaves
  /// the surface on its compiled fallback.
  AppWidgetMountInstall plan(
    Iterable<String> widgetNames,
    LibraryElement library, {
    required String sdkPrefix,
    required Set<String> takenNames,
  }) {
    final drawn = <String, Set<String>>{};
    for (final qualified in widgetNames) {
      final separator = qualified.indexOf(':');
      if (separator <= 0) continue;
      final namespace = qualified.substring(0, separator);
      if (WidgetLibrary.builtInByNamespace(namespace) != null) continue;
      (drawn[namespace] ??= {}).add(qualified.substring(separator + 1));
    }
    if (drawn.isEmpty) return _nothing;

    final speller =
        _spellers[library] ??= _PartSpeller(library, _uriByAlias.keys.toSet());
    final declared = _functionsByLibrary[library] ??= {};
    final fragments = <String>[];
    final registrations = StringBuffer('[');
    for (final namespace in drawn.keys.toList()..sort()) {
      final installed = _namesByNamespace[namespace] ?? const <String>[];
      for (final name in drawn[namespace]!) {
        if (!installed.contains(name)) {
          return _unavailable(name, 'no widget factory was generated for it');
        }
      }
      final version = _versions[namespace];
      registrations
        ..write('${sdkPrefix}RestageWidgetLibraryRegistration.constant(')
        ..write('library: ${sdkPrefix}WidgetLibrary.custom(')
        ..write('${dartStringLiteral(namespace)}),')
        ..write(version == null ? '' : 'capabilityVersion: $version,')
        ..write('widgets: [');
      for (final name in installed) {
        final qualified = WidgetVocabulary.qualifiedName(namespace, name);
        final factory = _factories[qualified]!;
        final function = _factoryFunctionName(namespace, name);
        if (takenNames.contains(function)) {
          return _unavailable(
            name,
            '${library.uri} already declares $function',
          );
        }
        if (declared[function] case final other? when other != qualified) {
          return _unavailable(
            name,
            '$function also names the factory of $other',
          );
        }
        final spelled = speller.spell(
          factory,
          _uriByAlias,
          rename: {factory.function: function},
        );
        if (spelled.unresolved case final missing?) {
          return _unavailable(
            name,
            '${library.uri} cannot name $missing; import it there',
          );
        }
        declared[function] = qualified;
        fragments.add(spelled.source!);
        registrations.write(
          '${sdkPrefix}RestageWidgetFactory('
          'name: ${dartStringLiteral(name)}, builder: $function),',
        );
      }
      registrations.write('],),');
    }
    registrations.write(']');
    return (
      libraries: registrations.toString(),
      fragments: fragments,
      problem: null,
    );
  }

  late final Map<String, List<String>> _namesByNamespace = () {
    final byNamespace = <String, List<String>>{};
    for (final qualified in _factories.keys) {
      final separator = qualified.indexOf(':');
      (byNamespace[qualified.substring(0, separator)] ??= [])
          .add(qualified.substring(separator + 1));
    }
    for (final names in byNamespace.values) {
      names.sort();
    }
    return byNamespace;
  }();
}

// Namespaces never hold `$`, so `$$` ends the namespace and dots stay apart
// from underscores.
String _factoryFunctionName(String namespace, String name) =>
    '_restage\$${namespace.replaceAll('.', r'$')}\$\$'
    '${name.replaceAll('.', r'$')}';

/// One factory declaration, parsed at most once per build.
final class _Factory {
  _Factory(this.function, this.source);

  final String function;
  final String source;
  _NameCollector? _names;
  CompilationUnit? _unit;

  CompilationUnit get unit =>
      _unit ??= parseString(content: source, throwIfDiagnostics: false).unit;

  _NameCollector names(Set<String> aliases) {
    if (_names case final names?) return names;
    final collector = _NameCollector(aliases);
    unit.accept(collector);
    return _names = collector;
  }
}

AppWidgetMountInstall _unavailable(String widget, String reason) => (
      libraries: null,
      fragments: const <String>[],
      problem: 'The generated mount cannot install the app widget $widget: '
          '$reason. Published versions of this surface render only after '
          'registerRestageWidgets() runs at startup.',
    );

/// Spells generated factory source for the library that owns a part.
final class _PartSpeller {
  _PartSpeller(this.library, this.aliases)
      : namespace = OwningLibraryNamespace(library);

  final LibraryElement library;
  final Set<String> aliases;
  final OwningLibraryNamespace namespace;
  final Map<String, String?> _spellings = {};
  LibraryElement? _sdk;
  bool _sdkSearched = false;

  /// [factory] with every placeholder and free name spelled as [library]
  /// sees it, or the first name it cannot see.
  ({String? source, String? unresolved}) spell(
    _Factory factory,
    Map<String, String> uriByAlias, {
    required Map<String, String> rename,
  }) {
    final collector = factory.names(aliases);
    final edits = <({int offset, int end, String text})>[];
    for (final declaration in factory.unit.declarations) {
      if (declaration is FunctionDeclaration) {
        final replacement = rename[declaration.name.lexeme];
        if (replacement != null) {
          edits.add(
            (
              offset: declaration.name.offset,
              end: declaration.name.end,
              text: replacement,
            ),
          );
        }
      }
    }
    for (final use in collector.uses) {
      if (collector.declared.contains(use.name) && use.alias == null) {
        final replacement = rename[use.name];
        if (replacement != null) {
          edits.add((offset: use.offset, end: use.end, text: replacement));
        }
        continue;
      }
      final alias = use.alias;
      final uri = alias == null ? null : uriByAlias[alias]!;
      final spelling = _spellings.putIfAbsent(
        '${uri ?? ''}#${use.name}',
        () => uri == null
            ? _freeSpelling(use.name)
            : _librarySpelling(uri, use.name),
      );
      if (spelling == null) {
        return (source: null, unresolved: uri ?? use.name);
      }
      if (alias != null || spelling != use.name) {
        edits.add((offset: use.offset, end: use.end, text: spelling));
      }
    }
    edits.sort((left, right) => right.offset.compareTo(left.offset));
    var result = factory.source;
    for (final edit in edits) {
      result = result.replaceRange(edit.offset, edit.end, edit.text);
    }
    return (source: result, unresolved: null);
  }

  // A name the factory source leaves bare: an SDK, Flutter or core name.
  String? _freeSpelling(String name) => _spelling(name, (element) {
        final uri = element.library?.identifier ?? '';
        if (uri.startsWith('dart:') || uri.startsWith('package:flutter/')) {
          return true;
        }
        final exported = _sdkLibrary_()?.exportNamespace.get2(name);
        return exported != null && _same(exported, element);
      });

  String? _librarySpelling(String uri, String name) =>
      _spelling(name, (element) => element.library?.identifier == uri);

  String? _spelling(String name, bool Function(Element) accepts) {
    final candidates = <Element?>[
      library.firstFragment.scope.lookup(name).getter,
      for (final prefix in library.firstFragment.prefixes)
        prefix.scope.lookup(name).getter,
    ];
    for (final candidate in candidates) {
      if (candidate == null || !accepts(candidate)) continue;
      final spelling = namespace.elementName(candidate);
      if (spelling != null) return spelling;
    }
    return null;
  }

  LibraryElement? _sdkLibrary_() {
    if (_sdkSearched) return _sdk;
    _sdkSearched = true;
    final seen = <String>{};
    final pending = <LibraryElement>[library];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (!seen.add(next.identifier)) continue;
      if (next.identifier == _sdkLibrary) return _sdk = next;
      for (final import in next.firstFragment.libraryImports) {
        if (import.importedLibrary case final imported?) pending.add(imported);
      }
      for (final export in next.firstFragment.libraryExports) {
        if (export.exportedLibrary case final exported?) pending.add(exported);
      }
    }
    return null;
  }
}

bool _same(Element left, Element right) {
  Element base(Element element) =>
      (element is PropertyAccessorElement ? element.variable : element)
          .baseElement;
  return base(left) == base(right);
}

/// Every name a factory declaration refers to, with its placeholder prefix.
final class _NameCollector extends RecursiveAstVisitor<void> {
  _NameCollector(this.aliases);

  final Set<String> aliases;
  final Set<String> declared = {};
  final List<({String? alias, String name, int offset, int end})> uses = [];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    declared.add(node.name.lexeme);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitRegularFormalParameter(RegularFormalParameter node) {
    if (node.name case final name?) declared.add(name.lexeme);
    super.visitRegularFormalParameter(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    declared.add(node.name.lexeme);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    declared.add(node.name.lexeme);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    declared.add(node.name.lexeme);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitNamedType(NamedType node) {
    final prefix = node.importPrefix;
    if (prefix == null && _languageTypes.contains(node.name.lexeme)) {
      // Spelled the same in every library.
    } else if (prefix == null) {
      uses.add(
        (
          alias: null,
          name: node.name.lexeme,
          offset: node.name.offset,
          end: node.name.end,
        ),
      );
    } else if (aliases.contains(prefix.name.lexeme)) {
      uses.add(
        (
          alias: prefix.name.lexeme,
          name: node.name.lexeme,
          offset: prefix.offset,
          end: node.name.end,
        ),
      );
    }
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    final qualifiedMember = switch (parent) {
      PrefixedIdentifier(:final identifier) => identical(identifier, node),
      PropertyAccess(:final propertyName) => identical(propertyName, node),
      MethodInvocation(:final methodName, :final realTarget) =>
        identical(methodName, node) && realTarget != null,
      ConstructorName(:final name) => identical(name, node),
      _ => false,
    };
    if (qualifiedMember) {
      // `alias.Name` reaches here as the member of its placeholder prefix.
      final target = switch (parent) {
        PrefixedIdentifier(:final prefix) => prefix,
        MethodInvocation(:final target) => target,
        _ => null,
      };
      if (target is SimpleIdentifier && aliases.contains(target.name)) {
        uses.add(
          (
            alias: target.name,
            name: node.name,
            offset: target.offset,
            end: node.end,
          ),
        );
      }
      return;
    }
    if (aliases.contains(node.name)) return;
    uses.add(
      (alias: null, name: node.name, offset: node.offset, end: node.end),
    );
  }
}
