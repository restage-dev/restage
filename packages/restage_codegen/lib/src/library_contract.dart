import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/durable_state.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        LibraryContractHeader,
        libraryContractDraftDirectory,
        libraryContractSnapshotDirectory,
        libraryContractSnapshotVersion;
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _kSnapshotGeneratedAt = '1970-01-01T00:00:00Z';

/// One custom library's recorded contract at one capability version.
@immutable
final class LibraryContractSnapshot {
  /// Creates a snapshot of [catalog], which holds only [library]'s entries.
  const LibraryContractSnapshot({
    required this.library,
    required this.capabilityVersion,
    required this.compatibleSince,
    required this.catalog,
    this.enumMembers = const {},
  });

  /// Decodes a snapshot file's [contents]; [source] names it in errors.
  factory LibraryContractSnapshot.decode(String contents, String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException catch (error) {
      throw FormatException('$source is not a library contract: $error');
    }
    final LibraryContractHeader(
      :namespace,
      :capabilityVersion,
      :compatibleSince,
    ) = LibraryContractHeader.fromJson(decoded, source);
    final json = decoded! as Map<String, Object?>;
    final enums = json['enumMembers'];
    if (enums != null && enums is! Map<String, Object?>) {
      throw FormatException('$source has malformed enumMembers.');
    }
    final entries = Map<String, Object?>.of(json)
      ..remove('namespace')
      ..remove('capabilityVersion')
      ..remove('compatibleSince')
      ..remove('enumMembers');
    final catalog = decodeCatalog(
      jsonEncode({
        ...entries,
        'generatedAt': _kSnapshotGeneratedAt,
        'libraries': {
          namespace: {
            'version': '0.0.0',
            'capabilityVersion': capabilityVersion,
            if (compatibleSince > 1) 'compatibleSince': compatibleSince,
          },
        },
      }),
    );
    return LibraryContractSnapshot(
      library: catalog.libraries.keys.single,
      capabilityVersion: capabilityVersion,
      compatibleSince: compatibleSince,
      catalog: catalog,
      enumMembers: {
        if (enums is Map<String, Object?>)
          for (final MapEntry(:key, :value) in enums.entries)
            key: (value! as List<Object?>).cast<String>(),
      },
    );
  }

  /// The snapshot of [library] in [catalog], or `null` when the library
  /// declares no capability version.
  ///
  /// [enumMembers] maps `<library uri>#<enum>` to its member names.
  static LibraryContractSnapshot? of(
    Catalog catalog,
    WidgetLibrary library, {
    Map<String, List<String>> enumMembers = const {},
  }) {
    final info = catalog.libraries[library];
    final capabilityVersion = info?.capabilityVersion;
    if (info == null || capabilityVersion == null) return null;
    final entries = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: _kSnapshotGeneratedAt,
      libraries: {
        library: LibraryInfo(
          version: '0.0.0',
          capabilityVersion: capabilityVersion,
          compatibleSince: info.compatibleSince,
        ),
      },
      widgets: [
        for (final widget in catalog.widgets)
          if (widget.library == library) widget,
      ],
      structuredTypes: [
        for (final structured in catalog.structuredTypes)
          if (structured.library == library) structured,
      ],
      unions: [
        for (final union in catalog.unions)
          if (union.library == library) union,
      ],
      designTokens: [
        for (final token in catalog.designTokens)
          if (token.library == library) token,
      ],
    );
    final referenced = _enumRefs(entries);
    return LibraryContractSnapshot(
      library: library,
      capabilityVersion: capabilityVersion,
      compatibleSince: info.compatibleSince,
      catalog: entries,
      enumMembers: {
        for (final ref in referenced.toList()..sort())
          if (enumMembers[ref] case final members?) ref: members,
      },
    );
  }

  /// The library this snapshot records.
  final WidgetLibrary library;

  /// The declared capability version.
  final int capabilityVersion;

  /// The oldest capability version this build still renders.
  final int compatibleSince;

  /// The library's catalog entries.
  final Catalog catalog;

  /// Member names of each enum the entries use, keyed `<library uri>#<enum>`.
  final Map<String, List<String>> enumMembers;

  /// Canonical JSON, free of timestamps and tool versions.
  String encode() {
    final entries = jsonDecode(encodeCatalog(catalog)) as Map<String, Object?>
      ..remove('generatedAt')
      ..remove('flutterVersion')
      ..remove('libraries')
      ..remove('compatRules')
      ..remove('exclusions');
    return '${const JsonEncoder.withIndent('  ').convert({
          'namespace': library.namespace,
          'capabilityVersion': capabilityVersion,
          'compatibleSince': compatibleSince,
          if (enumMembers.isNotEmpty) 'enumMembers': enumMembers,
          ...entries,
        })}\n';
  }
}

/// What a build does with one library after comparing it to its snapshots.
sealed class LibraryContractOutcome {
  const LibraryContractOutcome();
}

/// The build passes.
final class LibraryContractAccepted extends LibraryContractOutcome {
  /// Creates an accepted outcome.
  const LibraryContractAccepted();
}

/// The build fails; each line names one problem.
final class LibraryContractRefused extends LibraryContractOutcome {
  /// Creates a refused outcome.
  const LibraryContractRefused(this.lines);

  /// Creates a refused outcome with one [line].
  LibraryContractRefused.of(String line) : lines = [line];

  /// One line per problem.
  final List<String> lines;
}

/// Compares [current] with the [recorded] snapshots of the same library,
/// keyed by capability version. Only a push records a snapshot, so an
/// unpublished library has none and any change passes.
LibraryContractOutcome evaluateLibraryContract(
  LibraryContractSnapshot current,
  Map<int, LibraryContractSnapshot> recorded,
) {
  if (recorded.isEmpty) return const LibraryContractAccepted();
  final namespace = current.library.namespace;
  final latestVersion = recorded.keys.reduce((a, b) => a > b ? a : b);
  final latest = recorded[latestVersion]!;
  final version = current.capabilityVersion;
  if (version < latestVersion) {
    return LibraryContractRefused.of(
      'Library `$namespace` declares capabilityVersion $version, below the '
      'recorded v$latestVersion. It never moves back.',
    );
  }
  if (current.compatibleSince < latest.compatibleSince) {
    return LibraryContractRefused.of(
      'Library `$namespace` declares compatibleSince '
      '${current.compatibleSince}, below ${latest.compatibleSince} at '
      'v$latestVersion. It never moves back.',
    );
  }

  final changes = [
    for (final change in diffCatalogs(latest.catalog, current.catalog))
      if (_isContractBearing(change)) change,
    ..._enumMemberChanges(latest, current),
  ];
  final breaking = [
    for (final change in changes)
      if (switch (classifyCatalogChange(change)) {
        CompatClassification.breaking ||
        CompatClassification.forwarding =>
          true,
        CompatClassification.free || CompatClassification.additive => false,
      })
        change,
  ];
  final additive = changes.any(
        (change) =>
            classifyCatalogChange(change) == CompatClassification.additive,
      ) ||
      _enumMembersAdded(latest, current);

  if (breaking.isNotEmpty) {
    if (version > latestVersion && current.compatibleSince == version) {
      return const LibraryContractAccepted();
    }
    final target = version > latestVersion ? version : latestVersion + 1;
    final labels = _EntryLabels(latest.catalog, current.catalog);
    String line(CatalogChange change) =>
        '`${labels.of(change.affected)}` ${labels.describe(change)} since '
        'library `$namespace` v$latestVersion. To ship this break, set '
        'capabilityVersion: $target and compatibleSince: $target.';
    return LibraryContractRefused([
      for (final change in breaking) line(change),
    ]);
  }
  if (version > latestVersion) return const LibraryContractAccepted();
  if (additive) {
    return LibraryContractRefused.of(
      'Library `$namespace` changed since v$latestVersion. Raise '
      'capabilityVersion to ${latestVersion + 1}.',
    );
  }
  if (current.compatibleSince != latest.compatibleSince) {
    return LibraryContractRefused.of(
      'Library `$namespace` changed compatibleSince at v$latestVersion. To '
      'ship this break, set capabilityVersion: ${latestVersion + 1} and '
      'compatibleSince: ${latestVersion + 1}.',
    );
  }
  return const LibraryContractAccepted();
}

// Editor metadata and token resolution do not change what an installed app
// accepts.
bool _isContractBearing(CatalogChange change) => switch (change) {
      PropertyMetadataChanged() ||
      TokenResolverChanged() ||
      TokenFallbackChanged() =>
        false,
      _ => true,
    };

/// A removed or renamed enum member breaks every property that uses the enum.
List<CatalogChange> _enumMemberChanges(
  LibraryContractSnapshot latest,
  LibraryContractSnapshot current,
) {
  final shrunk = {
    for (final MapEntry(:key, :value) in latest.enumMembers.entries)
      if (current.enumMembers[key] case final now?
          when !value.every(now.contains))
        key,
  };
  if (shrunk.isEmpty) return const [];
  final namespace = current.library.namespace;
  return [
    for (final (wireId, shape) in _propertyShapes(current.catalog))
      if (_enumRefsOf(shape).any(shrunk.contains))
        PropertyShapeChanged(
          affected: WireIdRef(library: namespace, wireId: wireId),
          fields: const ['enumMembers'],
        ),
  ];
}

bool _enumMembersAdded(
  LibraryContractSnapshot latest,
  LibraryContractSnapshot current,
) {
  for (final MapEntry(:key, :value) in current.enumMembers.entries) {
    final before = latest.enumMembers[key];
    if (before != null && !value.every(before.contains)) return true;
  }
  return false;
}

Iterable<(WireId, CatalogValueShape?)> _propertyShapes(Catalog catalog) sync* {
  for (final widget in catalog.widgets) {
    for (final property in widget.properties) {
      yield (property.wireId, property.valueShape);
    }
  }
  for (final structured in catalog.structuredTypes) {
    for (final field in structured.fields) {
      yield (field.wireId, field.valueShape);
    }
  }
}

Iterable<String> _enumRefsOf(CatalogValueShape? shape) sync* {
  switch (shape) {
    case EnumShape(:final enumRef):
      yield '${enumRef.libraryUri}#${enumRef.symbolName}';
    case ListShape(:final itemShape):
      yield* _enumRefsOf(itemShape);
    case _:
      break;
  }
}

Set<String> _enumRefs(Catalog catalog) => {
      for (final (_, shape) in _propertyShapes(catalog)) ..._enumRefsOf(shape),
    };

/// Resolves the members of every enum [catalog]'s entries use.
Future<Map<String, List<String>>> resolveEnumMembers(
  Resolver resolver,
  Catalog catalog,
) async {
  final members = <String, List<String>>{};
  for (final ref in _enumRefs(catalog)) {
    final separator = ref.lastIndexOf('#');
    final LibraryElement library;
    try {
      library = await resolver.libraryFor(
        AssetId.resolve(Uri.parse(ref.substring(0, separator))),
      );
    } on Object {
      continue;
    }
    final element = library.exportNamespace.get2(ref.substring(separator + 1));
    if (element is EnumElement) {
      members[ref] = [
        for (final constant in element.constants)
          if (constant.name case final name?) name,
      ];
    }
  }
  return members;
}

Map<String, String> _readLibraryContractContents(
  Directory root,
  Iterable<WidgetLibrary> libraries, {
  Map<String, String> trackedContents = const {},
  String? requireTrackedForPackage,
}) {
  final contents = Map<String, String>.of(trackedContents);
  for (final library in libraries) {
    final directory = _snapshotDirectory(root, library);
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (libraryContractSnapshotVersion(name) == null) continue;
      final path =
          '$libraryContractSnapshotDirectory/${library.namespace}/$name';
      if (contents.containsKey(path)) continue;
      if (requireTrackedForPackage != null) {
        throw StateError(
            '$requireTrackedForPackage must expose $path as a build input. '
            '$kUntrackedDurableStateAdvice');
      }
      contents[path] = file.readAsStringSync();
    }
  }
  return contents;
}

Map<int, LibraryContractSnapshot> _decodeLibraryContractSnapshots(
  WidgetLibrary library,
  Map<String, String> contents,
) {
  final prefix = '$libraryContractSnapshotDirectory/${library.namespace}/';
  final snapshots = <int, LibraryContractSnapshot>{};
  for (final entry in contents.entries) {
    if (!entry.key.startsWith(prefix)) continue;
    final version =
        libraryContractSnapshotVersion(entry.key.substring(prefix.length));
    if (version == null) continue;
    final snapshot = LibraryContractSnapshot.decode(entry.value, entry.key);
    if (snapshot.library != library || snapshot.capabilityVersion != version) {
      throw FormatException(
        '${entry.key} records library `${snapshot.library.namespace}` '
        'v${snapshot.capabilityVersion}.',
      );
    }
    snapshots[version] = snapshot;
  }
  return snapshots;
}

/// Writes [snapshot] as the library's only draft under [root], where the
/// next push that depends on it binds it.
void writeLibraryContractDraft(
  Directory root,
  LibraryContractSnapshot snapshot,
) {
  final directory = Directory.fromUri(
    root.uri.resolve(
      '$libraryContractDraftDirectory/${snapshot.library.namespace}/',
    ),
  );
  if (directory.existsSync()) directory.deleteSync(recursive: true);
  directory.createSync(recursive: true);
  File.fromUri(directory.uri.resolve('v${snapshot.capabilityVersion}.json'))
      .writeAsStringSync(snapshot.encode());
}

/// Checks every versioned custom library in [catalog] against the snapshots
/// under [root], writing every library's draft when all pass and [write] is
/// set. Returns the libraries that have no recorded snapshot.
///
/// Throws [LibraryContractException] naming every problem.
List<LibraryContractSnapshot> enforceLibraryContracts(
  Catalog catalog, {
  required Directory root,
  required bool write,
  Map<String, List<String>> enumMembers = const {},
}) {
  return _enforceLibraryContracts(
    catalog,
    contents:
        _readLibraryContractContents(root, _versionedCustomLibraries(catalog)),
    root: root,
    write: write,
    enumMembers: enumMembers,
  );
}

Iterable<WidgetLibrary> _versionedCustomLibraries(Catalog catalog) =>
    catalog.libraries.keys.where((library) =>
        WidgetLibrary.builtInByNamespace(library.namespace) == null &&
        catalog.libraries[library]!.capabilityVersion != null);

List<LibraryContractSnapshot> _enforceLibraryContracts(
  Catalog catalog, {
  required Map<String, String> contents,
  required Directory? root,
  required bool write,
  required Map<String, List<String>> enumMembers,
}) {
  final lines = <String>[];
  final accepted = <LibraryContractSnapshot>[];
  final unrecorded = <LibraryContractSnapshot>[];
  final libraries = _versionedCustomLibraries(catalog).toList()
    ..sort((a, b) => a.namespace.compareTo(b.namespace));
  for (final library in libraries) {
    final current = LibraryContractSnapshot.of(
      catalog,
      library,
      enumMembers: enumMembers,
    );
    if (current == null) continue;
    final recorded = _decodeLibraryContractSnapshots(library, contents);
    if (recorded.isEmpty) unrecorded.add(current);
    final outcome = evaluateLibraryContract(current, recorded);
    switch (outcome) {
      case LibraryContractAccepted():
        accepted.add(current);
      case LibraryContractRefused(lines: final refused):
        lines.addAll(refused);
    }
  }
  if (lines.isNotEmpty) throw LibraryContractException(lines);
  // Drafts change only with a build that passes, so they match its output.
  if (write && root != null) {
    for (final snapshot in accepted) {
      writeLibraryContractDraft(root, snapshot);
    }
  }
  return unrecorded;
}

/// Checks package library contracts, tracking source snapshots when building.
Future<void> enforcePackageLibraryContracts(
  Catalog catalog, {
  required String package,
  required bool write,
  required BuildStep buildStep,
  bool requireTracked = false,
  Map<String, List<String>> enumMembers = const {},
}) async {
  final rootUri = await restagePackageRoot(package);
  final root = rootUri == null ? null : Directory.fromUri(rootUri);
  final contents = <String, String>{};
  await for (final asset in buildStep.findAssets(
    Glob('$libraryContractSnapshotDirectory/*/v*.json'),
  )) {
    contents[asset.path] = await buildStep.readAsString(asset);
  }
  final unrecorded = _enforceLibraryContracts(
    catalog,
    contents: root == null
        ? contents
        : _readLibraryContractContents(
            root,
            _versionedCustomLibraries(catalog),
            trackedContents: contents,
            requireTrackedForPackage: requireTracked ? package : null,
          ),
    root: root,
    write: write,
    enumMembers: enumMembers,
  );
  // An app records its libraries when it pushes; a package records them itself.
  if (write &&
      root != null &&
      !File.fromUri(root.uri.resolve('restage_config.yaml')).existsSync()) {
    for (final snapshot in unrecorded) {
      log.warning(unrecordedLibraryWarning(snapshot));
    }
  }
}

/// The build warning for a package library no contract is recorded for.
String unrecordedLibraryWarning(LibraryContractSnapshot snapshot) =>
    'Library `${snapshot.library.namespace}` '
    'v${snapshot.capabilityVersion} is not recorded yet. Run '
    '`restage library record` before publishing this package.';

/// A library changed in a way its declared capability line does not allow.
final class LibraryContractException implements Exception {
  /// Creates an exception with one line per problem.
  const LibraryContractException(this.lines);

  /// One line per problem.
  final List<String> lines;

  @override
  String toString() => lines.join('\n');
}

Directory _snapshotDirectory(Directory root, WidgetLibrary library) =>
    Directory.fromUri(
      root.uri
          .resolve('$libraryContractSnapshotDirectory/${library.namespace}/'),
    );

/// Names catalog entries the way the developer wrote them.
final class _EntryLabels {
  _EntryLabels(this.before, this.after);

  final Catalog before;
  final Catalog after;

  String of(WireIdRef ref) =>
      _label(before, ref) ?? _label(after, ref) ?? '$ref';

  String describe(CatalogChange change) => switch (change) {
        EntryRemoved() => 'was removed',
        EntryRenamed() => 'was renamed to `${_label(after, change.affected)}`',
        EntryReplaced() => 'was replaced',
        PropertyTypeChanged(:final from, :final to) =>
          'changed type from ${from.name} to ${to.name}',
        PropertyShapeChanged(fields: ['enumMembers']) =>
          'lost or renamed an enum value',
        PropertyShapeChanged(:final fields) => 'changed ${fields.join(', ')}',
        RequiredFlagChanged() => 'became required',
        SyntheticStrategyChanged() => 'changed how it is generated',
        WidgetChildrenSlotChanged(:final from, :final to) =>
          'changed its children from ${from.name} to ${to.name}',
        UnionMemberRemoved(:final member) => 'lost member `${of(member)}`',
        UnionDiscriminatorChanged() => 'changed its discriminator',
        VariantArgumentsChanged() => 'changed its arguments',
        TokenTypeChanged(:final from, :final to) =>
          'changed type from ${from.name} to ${to.name}',
        EntryAdded() ||
        EntrySourceMoved() ||
        EntryDeprecated() ||
        PropertyDefaultChanged() ||
        PropertyMetadataChanged() ||
        UnionMemberAdded() ||
        TokenResolverChanged() ||
        TokenFallbackChanged() =>
          'changed',
      };

  static String? _label(Catalog catalog, WireIdRef ref) {
    for (final widget in catalog.widgets) {
      if (widget.library.namespace != ref.library) continue;
      if (widget.wireId == ref.wireId) return widget.name;
      for (final property in widget.properties) {
        if (property.wireId == ref.wireId) {
          return '${widget.name}.${property.name}';
        }
      }
    }
    for (final structured in catalog.structuredTypes) {
      if (structured.library.namespace != ref.library) continue;
      if (structured.wireId == ref.wireId) return structured.name;
      for (final field in structured.fields) {
        if (field.wireId == ref.wireId) {
          return '${structured.name}.${field.name}';
        }
      }
      for (final variant in structured.variants) {
        if (variant.wireId == ref.wireId) {
          final accessor = switch (variant) {
            ConstructorVariant(:final namedConstructor) => namedConstructor,
            StaticMethodVariant(:final staticAccessor) ||
            StaticGetterVariant(:final staticAccessor) ||
            ConstValueVariant(:final staticAccessor) =>
              staticAccessor,
          };
          return accessor == null || accessor.isEmpty
              ? '${structured.name}()'
              : '${structured.name}.$accessor';
        }
      }
    }
    for (final union in catalog.unions) {
      if (union.library.namespace == ref.library &&
          union.wireId == ref.wireId) {
        return union.name;
      }
    }
    for (final token in catalog.designTokens) {
      if (token.library.namespace == ref.library &&
          token.wireId == ref.wireId) {
        return token.name;
      }
    }
    return null;
  }
}
