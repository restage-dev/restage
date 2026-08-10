import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/restage_widget_package_facts.dart';
import 'package:restage_codegen/src/screen_source_admission.dart';
import 'package:restage_codegen/src/target_config_reader.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const _restageOrigin = 'package:restage';
const _catalogSchemaOrigin = 'package:rfw_catalog_schema';
const _flutterWidgetFrameworkLibrary =
    'package:flutter/src/widgets/framework.dart';
const _packageGraphZoneKey = Object();

/// Runs [body] with Pub package-graph JSON supplied to native-screen tests.
///
/// Production builders never set this zone value; they read Pub's generated
/// graph next to the active package configuration. Keeping the test seam at
/// the graph boundary exercises the same structured parser without adding a
/// builder option that could weaken dependency validation in production.
@visibleForTesting
Future<T> runWithNativeScreenPackageGraphForTesting<T>({
  required String packageGraphSource,
  required Future<T> Function() body,
}) =>
    runZoned(
      body,
      zoneValues: {_packageGraphZoneKey: packageGraphSource},
    );

/// One static event marker retained from a native screen source.
@immutable
final class NativeScreenEventSource {
  /// Creates one resolved event source fact.
  const NativeScreenEventSource({
    required this.fieldName,
    required this.id,
    required this.payloadType,
  });

  /// Static field name on the source class.
  final String fieldName;

  /// Stable event identifier carried by the const marker.
  final String id;

  /// Exact analyzer-resolved event payload type.
  final DartType payloadType;
}

/// Target-neutral native facts for one exact `@ScreenSource` class.
///
/// This adapter intentionally does not retain or reinterpret the RFW build
/// blueprint. The existing onboarding visitor remains the sole owner of that
/// target's build/state/event-expression surface.
@immutable
final class NativeScreenSource {
  /// Creates an immutable native screen source.
  NativeScreenSource({
    required this.id,
    required this.version,
    required this.minClient,
    required this.classIdentity,
    required this.element,
    required this.sourceAsset,
    required this.declarationSourcePath,
    required this.importUri,
    required List<String> importUris,
    required this.description,
    required this.constructorFacts,
    required this.a2uiTargetConfig,
    required this.widgetbookTargetConfig,
    required List<NativeScreenEventSource> events,
  })  : importUris = List.unmodifiable(importUris),
        events = List.unmodifiable(events);

  /// Stable authored screen identifier.
  final String id;

  /// Authored screen descriptor version.
  final int version;

  /// Minimum compatible client catalog version.
  final int minClient;

  /// Exact analyzer identity, `<owning library URI>#<class name>`.
  final String classIdentity;

  /// Exact analyzer class declaration.
  final ClassElement element;

  /// Importable owning-library asset.
  final AssetId sourceAsset;

  /// Exact source path containing the class declaration.
  final String declarationSourcePath;

  /// Canonical import URI for the owning source library.
  final String importUri;

  /// Canonical imports needed to reproduce the native constructor surface.
  final List<String> importUris;

  /// Normalized class Dartdoc.
  final String? description;

  /// Shared unnamed-constructor facts, in declaration order.
  final WidgetConstructorFacts constructorFacts;

  /// A2UI-only authoring configuration on the screen and its inputs.
  final A2uiTargetConfigFacts a2uiTargetConfig;

  /// Widgetbook-only authoring configuration on the screen and its inputs.
  final WidgetbookTargetConfigFacts widgetbookTargetConfig;

  /// Direct static const screen event markers, in field-name order.
  final List<NativeScreenEventSource> events;
}

/// Package-wide exact native screen identities and shared source facts.
@immutable
final class NativeScreenSourceIndex {
  /// Creates an immutable package index.
  NativeScreenSourceIndex({
    required List<NativeScreenSource> screens,
    required List<Issue> issues,
  })  : screens = List.unmodifiable(screens),
        issues = List.unmodifiable(issues);

  /// Screens in deterministic ID then class-identity order.
  final List<NativeScreenSource> screens;

  /// Informational source notices retained by the index.
  final List<Issue> issues;
}

/// Target adapter consuming the shared native screen index.
///
/// Each adapter selects its semantic configuration explicitly so an enabled
/// target cannot be gated by diagnostics owned only by a disabled sibling.
enum NativeScreenSourceConsumer {
  /// The opaque native A2UI component adapter.
  a2ui,

  /// The native Widgetbook story adapter, including mirrored A2UI usage text.
  widgetbook,
}

/// Loads all authored `@ScreenSource` declarations in the current package.
///
/// Parts are indexed through their importable owning library. Annotation,
/// class, constructor-type, and optional A2UI namespace recognition all use
/// resolved analyzer identity. Pub's generated package graph is consulted only
/// for direct-dependency metadata after identity has already been established;
/// it is never a Dart source-recognition fallback.
Future<NativeScreenSourceIndex> loadNativeScreenSourceIndex(
  BuildStep buildStep, {
  required NativeScreenSourceConsumer consumer,
  bool validateA2uiNamespace = false,
}) async {
  final sourceAssets = await buildStep
      .findAssets(Glob('lib/**.dart'))
      .where(_isAuthoredDartAsset)
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  final sources = <ResolvedPackageLibrary>[];
  for (final assetId in sourceAssets) {
    final LibraryElement library;
    try {
      library = await buildStep.resolver.libraryFor(
        assetId,
        allowSyntaxErrors: true,
      );
    } on NonLibraryAssetException {
      continue;
    }
    sources.add((assetId: assetId, library: library));
  }

  final issues = <Issue>[];
  final screens = <NativeScreenSource>[];
  _PackageGraphFacts? packageGraphFacts;

  for (final source in sources) {
    final hasAnnotatedClass = source.library.classes.any(
      (cls) =>
          firstAnnotationFromOriginAny(
            cls,
            const {'ScreenSource', 'OnboardingSource'},
            _restageOrigin,
          ) !=
          null,
    );
    if (!hasAnnotatedClass && !isRfwScreenSourceInput(source.assetId)) {
      continue;
    }

    final admission = await inspectScreenSourceAdmission(
      buildStep,
      assetId: source.assetId,
      library: source.library,
    );
    issues.addAll(admission.issues);
    final cls = admission.admittedClass;
    final admittedSource = admission.admittedSource;
    if (cls == null || admittedSource == null) continue;

    packageGraphFacts ??= await _readPackageGraphFacts(buildStep, issues);

    final className = cls.name ?? '<unnamed>';
    final declarationPath = _elementSourcePath(cls, source.assetId);
    final location = '$declarationPath#$className';
    final identity = '${source.library.identifier}#$className';
    if (className.startsWith('_')) {
      issues.add(
        Issue(
          code: IssueCode.invalidWidgetClass,
          message: 'Native sibling generators cannot name private '
              'annotated screen class $identity. Make the @ScreenSource '
              'class public.',
          location: location,
        ),
      );
      continue;
    }
    if (cls.isAbstract) {
      issues.add(
        Issue(
          code: IssueCode.invalidWidgetClass,
          message: 'Native sibling generators cannot construct abstract '
              '@ScreenSource class $identity. Make the screen class '
              'concrete.',
          location: location,
        ),
      );
      continue;
    }
    if (!_extendsSupportedFlutterWidget(cls)) {
      issues.add(
        Issue(
          code: IssueCode.unsupportedBaseClass,
          message: '@ScreenSource class $identity must extend Flutter '
              'StatelessWidget or StatefulWidget so native sibling '
              'generators can construct it.',
          location: location,
        ),
      );
      continue;
    }
    final widgetAnnotation = firstAnnotationFromOriginAny(
      cls,
      const {'RestageWidget'},
      _catalogSchemaOrigin,
    );
    if (widgetAnnotation != null) {
      issues.add(
        Issue(
          code: IssueCode.invalidWidgetClass,
          message: '@ScreenSource and @RestageWidget cannot annotate the '
              'same exact class $identity; the native screen and customer '
              'widget source contracts are disjoint.',
          location: location,
        ),
      );
    }

    final id = admittedSource.id;

    final constructorFacts = projectWidgetConstructorFacts(
      cls,
      source.assetId,
      readWidgetConstructorFacts(cls, source.assetId),
      target: switch (consumer) {
        NativeScreenSourceConsumer.a2ui => EmitTarget.a2ui,
        NativeScreenSourceConsumer.widgetbook => EmitTarget.widgetbook,
      },
    );
    final a2uiTargetConfig = readA2uiTargetConfig(
      cls,
      source.assetId,
      constructorInputs: constructorFacts.inputs,
      consumer: consumer == NativeScreenSourceConsumer.a2ui
          ? A2uiTargetConfigConsumer.a2ui
          : A2uiTargetConfigConsumer.widgetbookMetadata,
    );
    final widgetbookTargetConfig =
        consumer == NativeScreenSourceConsumer.widgetbook
            ? readWidgetbookTargetConfig(
                cls,
                source.assetId,
                constructorInputs: constructorFacts.inputs,
              )
            : WidgetbookTargetConfigFacts(
                expansion: null,
                maxStories: null,
                properties: const {},
                issues: const [],
              );
    issues
      ..addAll(constructorFacts.issues)
      ..addAll(a2uiTargetConfig.issues);
    if (consumer == NativeScreenSourceConsumer.widgetbook) {
      issues.addAll(widgetbookTargetConfig.issues);
    }

    final importUri = _canonicalSourceImportUri(
      source.library,
      source.assetId,
    );
    final importUris = <String>{importUri};
    for (final input in constructorFacts.inputs) {
      final inputLocation = '$declarationPath#$className.${input.name}';
      final requirements = <_ImportRequirement>[];
      _collectTypeRequirements(
        input.type,
        sourcePath: inputLocation,
        output: requirements,
      );
      final reconstructed = input.constructorDefault.reconstructedValue;
      if (reconstructed != null) {
        _collectConstRequirements(
          reconstructed,
          sourcePath: '$inputLocation default',
          output: requirements,
        );
      }
      _collectResolvedDefaultRequirements(
        input,
        sourcePath: '$inputLocation default',
        output: requirements,
      );
      for (final requirement in requirements) {
        final resolved = _resolveCanonicalImport(
          requirement,
          sourceLibrary: source.library,
          sourceImportUri: importUri,
          rootPackage: buildStep.inputId.package,
          declaredDependencies: packageGraphFacts.dependencies,
          issues: issues,
        );
        if (resolved != null) importUris.add(resolved);
      }
    }

    final events = _readEvents(cls, declarationPath, issues);
    screens.add(
      NativeScreenSource(
        id: id,
        version: admittedSource.version,
        minClient: admittedSource.minClient,
        classIdentity: identity,
        element: cls,
        sourceAsset: source.assetId,
        declarationSourcePath: declarationPath,
        importUri: importUri,
        importUris: importUris.toList()..sort(),
        description: normalizeDartdoc(cls.documentationComment),
        constructorFacts: constructorFacts,
        a2uiTargetConfig: a2uiTargetConfig,
        widgetbookTargetConfig: widgetbookTargetConfig,
        events: events,
      ),
    );
  }

  _validateDuplicateScreenIds(screens, issues);
  if (validateA2uiNamespace) {
    _validateA2uiComponentNamespace(sources, screens, issues);
  }

  issues.sort(_compareIssues);
  for (final issue in issues.where((issue) => issue.code.isInformational)) {
    log.warning(issue.toString());
  }
  final failures = issues
      .where((issue) => !issue.code.isInformational)
      .toList(growable: false);
  if (failures.isNotEmpty) {
    for (final issue in failures) {
      log.severe(issue.toString());
    }
    throw StateError(
      '${failures.length} native ScreenSource issue(s); see log above.',
    );
  }

  screens.sort((left, right) {
    final byId = left.id.compareTo(right.id);
    return byId != 0 ? byId : left.classIdentity.compareTo(right.classIdentity);
  });
  return NativeScreenSourceIndex(screens: screens, issues: issues);
}

bool _extendsSupportedFlutterWidget(ClassElement cls) =>
    cls.allSupertypes.any((type) {
      final element = type.element;
      return element.library.identifier == _flutterWidgetFrameworkLibrary &&
          const {'StatelessWidget', 'StatefulWidget'}.contains(element.name);
    });

void _collectResolvedDefaultRequirements(
  WidgetConstructorInput input, {
  required String sourcePath,
  required List<_ImportRequirement> output,
}) {
  final value = input.formal.computeConstantValue();
  final variable = value?.variable;
  if (variable != null) {
    final member = variable.name;
    final owner = variable.enclosingElement;
    final ownerName = switch (owner) {
      final InterfaceElement element => element.name,
      final ExtensionElement element => element.name,
      _ => null,
    };
    final symbol = ownerName ?? member;
    final libraryUri = variable.library?.identifier;
    if (symbol != null && libraryUri != null) {
      output.add(
        _ImportRequirement(
          libraryUri: libraryUri,
          symbol: symbol,
          sourcePath: sourcePath,
          privateMember: member?.startsWith('_') ?? false,
          privateMemberName: member?.startsWith('_') ?? false ? member : null,
        ),
      );
    }
  }

  final constructor = value?.constructorInvocation?.constructor;
  if (constructor == null) return;
  final owner = constructor.enclosingElement;
  final ownerName = owner.name;
  final constructorName = constructor.name;
  if (ownerName == null) return;
  output.add(
    _ImportRequirement(
      libraryUri: owner.library.identifier,
      symbol: ownerName,
      sourcePath: sourcePath,
      privateMember: constructorName?.startsWith('_') ?? false,
      privateMemberName:
          constructorName?.startsWith('_') ?? false ? constructorName : null,
    ),
  );
}

void _validateDuplicateScreenIds(
  List<NativeScreenSource> screens,
  List<Issue> issues,
) {
  final byId = <String, List<NativeScreenSource>>{};
  for (final screen in screens) {
    byId.putIfAbsent(screen.id, () => []).add(screen);
  }
  final duplicates = byId.entries
      .where((entry) => entry.value.length > 1)
      .toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final duplicate in duplicates) {
    final declarations = duplicate.value
      ..sort(
        (left, right) => left.classIdentity.compareTo(right.classIdentity),
      );
    final declarationList = declarations
        .map(
          (screen) =>
              '${screen.classIdentity} (${screen.declarationSourcePath})',
        )
        .join(', ');
    issues.add(
      Issue(
        code: IssueCode.duplicateId,
        message: '@ScreenSource id "${duplicate.key}" is declared by '
            '$declarationList.',
        location: declarations.first.declarationSourcePath,
      ),
    );
  }
}

void _validateA2uiComponentNamespace(
  List<ResolvedPackageLibrary> sources,
  List<NativeScreenSource> screens,
  List<Issue> issues,
) {
  final packageFacts = indexRestageWidgetPackage(sources);
  final widgetsByName = <String, List<_A2uiWidgetIdentity>>{};
  for (final source in sources) {
    final result = visitRestageWidgetsInPackage(
      source.library,
      source.assetId,
      target: WidgetVisitorTarget.a2ui,
      packageFacts: packageFacts,
    );
    for (final widget in result.widgets) {
      final className = widget.flutterType.split('#').last;
      final matches = source.library.classes.where(
        (element) => element.name == className,
      );
      if (matches.length != 1) continue;
      widgetsByName.putIfAbsent(widget.name, () => []).add(
            _A2uiWidgetIdentity(
              classIdentity: widget.flutterType,
              declarationSourcePath: _elementSourcePath(
                matches.single,
                source.assetId,
              ),
            ),
          );
    }
  }

  for (final screen in screens) {
    final collisions = widgetsByName[screen.id];
    if (collisions == null) continue;
    collisions.sort(
      (left, right) => left.classIdentity.compareTo(right.classIdentity),
    );
    for (final widget in collisions) {
      issues.add(
        Issue(
          code: IssueCode.duplicateWidgetName,
          message: 'A2UI component name "${screen.id}" is declared by both '
              '@ScreenSource ${screen.classIdentity} '
              '(${screen.declarationSourcePath}) and @RestageWidget '
              '${widget.classIdentity} (${widget.declarationSourcePath}).',
          location: screen.declarationSourcePath,
        ),
      );
    }
  }
}

List<NativeScreenEventSource> _readEvents(
  ClassElement cls,
  String declarationPath,
  List<Issue> issues,
) {
  final events = <NativeScreenEventSource>[];
  final className = cls.name ?? '<unnamed>';
  for (final field in cls.fields) {
    if (!field.isStatic || !field.isConst) continue;
    final payloadType = _eventPayloadType(field.type);
    if (payloadType == null) continue;
    final fieldName = field.name ?? '<unnamed>';
    final id = field.computeConstantValue()?.getField('id')?.toStringValue();
    if (id == null || id.isEmpty) {
      issues.add(
        Issue(
          code: IssueCode.invalidEventConfiguration,
          message: 'Static event $className.$fieldName must const-evaluate '
              'to an OnboardingEvent with a non-empty String id.',
          location: '$declarationPath#$className.$fieldName',
        ),
      );
      continue;
    }
    events.add(
      NativeScreenEventSource(
        fieldName: fieldName,
        id: id,
        payloadType: payloadType,
      ),
    );
  }
  events.sort((left, right) => left.fieldName.compareTo(right.fieldName));
  return events;
}

DartType? _eventPayloadType(DartType type) {
  final alias = type.alias;
  if (alias != null &&
      alias.element.name == 'SurfaceEvent' &&
      libraryUriMatchesOrigin(
        alias.element.library.identifier,
        _restageOrigin,
      )) {
    return alias.typeArguments.singleOrNull;
  }
  if (type is! InterfaceType ||
      type.element.name != 'OnboardingEvent' ||
      !libraryUriMatchesOrigin(
        type.element.library.identifier,
        _restageOrigin,
      )) {
    return null;
  }
  return type.typeArguments.singleOrNull;
}

void _collectTypeRequirements(
  DartType type, {
  required String sourcePath,
  required List<_ImportRequirement> output,
}) {
  final alias = type.alias;
  if (alias != null) {
    output.add(
      _ImportRequirement(
        libraryUri: alias.element.library.identifier,
        symbol: alias.element.name ?? '<unnamed>',
        sourcePath: sourcePath,
      ),
    );
    for (final argument in alias.typeArguments) {
      _collectTypeRequirements(
        argument,
        sourcePath: sourcePath,
        output: output,
      );
    }
    return;
  }
  if (type is InterfaceType) {
    final name = type.element.name;
    if (name != null) {
      output.add(
        _ImportRequirement(
          libraryUri: type.element.library.identifier,
          symbol: name,
          sourcePath: sourcePath,
        ),
      );
    }
    for (final argument in type.typeArguments) {
      _collectTypeRequirements(
        argument,
        sourcePath: sourcePath,
        output: output,
      );
    }
    return;
  }
  if (type is FunctionType) {
    _collectTypeRequirements(
      type.returnType,
      sourcePath: sourcePath,
      output: output,
    );
    for (final formal in type.formalParameters) {
      _collectTypeRequirements(
        formal.type,
        sourcePath: sourcePath,
        output: output,
      );
    }
    return;
  }
  if (type is RecordType) {
    for (final field in type.positionalFields) {
      _collectTypeRequirements(
        field.type,
        sourcePath: sourcePath,
        output: output,
      );
    }
    for (final field in type.namedFields) {
      _collectTypeRequirements(
        field.type,
        sourcePath: sourcePath,
        output: output,
      );
    }
  }
}

void _collectConstRequirements(
  DartConstValue value, {
  required String sourcePath,
  required List<_ImportRequirement> output,
}) {
  switch (value) {
    case DartConstNull() || DartConstScalar():
      return;
    case DartConstReference(:final libraryUri, :final owner, :final member):
      output.add(
        _ImportRequirement(
          libraryUri: libraryUri,
          symbol: owner ?? member,
          sourcePath: sourcePath,
        ),
      );
    case DartConstInvocation(
        :final type,
        :final positional,
        :final named,
      ):
      _collectTypeIdentityRequirements(
        type,
        sourcePath: sourcePath,
        output: output,
      );
      for (final item in positional) {
        _collectConstRequirements(
          item,
          sourcePath: sourcePath,
          output: output,
        );
      }
      for (final item in named) {
        _collectConstRequirements(
          item.value,
          sourcePath: sourcePath,
          output: output,
        );
      }
    case DartConstList(:final type, :final values) ||
          DartConstSet(:final type, :final values):
      if (type != null) {
        _collectTypeIdentityRequirements(
          type,
          sourcePath: sourcePath,
          output: output,
        );
      }
      for (final item in values) {
        _collectConstRequirements(
          item,
          sourcePath: sourcePath,
          output: output,
        );
      }
    case DartConstMap(:final type, :final entries):
      if (type != null) {
        _collectTypeIdentityRequirements(
          type,
          sourcePath: sourcePath,
          output: output,
        );
      }
      for (final entry in entries) {
        _collectConstRequirements(
          entry.key,
          sourcePath: sourcePath,
          output: output,
        );
        _collectConstRequirements(
          entry.value,
          sourcePath: sourcePath,
          output: output,
        );
      }
    case DartConstRecord(:final positional, :final named):
      for (final item in positional) {
        _collectConstRequirements(
          item,
          sourcePath: sourcePath,
          output: output,
        );
      }
      for (final item in named) {
        _collectConstRequirements(
          item.value,
          sourcePath: sourcePath,
          output: output,
        );
      }
  }
}

void _collectTypeIdentityRequirements(
  DartTypeIdentity type, {
  required String sourcePath,
  required List<_ImportRequirement> output,
}) {
  switch (type) {
    case DartNamedTypeIdentity(
        :final libraryUri,
        :final symbolName,
        :final typeArguments,
      ):
      output.add(
        _ImportRequirement(
          libraryUri: libraryUri,
          symbol: symbolName,
          sourcePath: sourcePath,
        ),
      );
      for (final argument in typeArguments) {
        _collectTypeIdentityRequirements(
          argument,
          sourcePath: sourcePath,
          output: output,
        );
      }
    case DartRecordTypeIdentity(:final positional, :final named):
      for (final field in positional) {
        _collectTypeIdentityRequirements(
          field,
          sourcePath: sourcePath,
          output: output,
        );
      }
      for (final field in named) {
        _collectTypeIdentityRequirements(
          field.type,
          sourcePath: sourcePath,
          output: output,
        );
      }
  }
}

String? _resolveCanonicalImport(
  _ImportRequirement requirement, {
  required LibraryElement sourceLibrary,
  required String sourceImportUri,
  required String rootPackage,
  required Set<String> declaredDependencies,
  required List<Issue> issues,
}) {
  if (requirement.symbol.startsWith('_') || requirement.privateMember) {
    final privateIdentity = requirement.privateMemberName == null
        ? requirement.symbol
        : '${requirement.symbol}.${requirement.privateMemberName}';
    issues.add(
      Issue(
        code: IssueCode.invalidWidgetClass,
        message: '${requirement.sourcePath} requires private Dart identity '
            '${requirement.libraryUri}#$privateIdentity, which a '
            'generated native sibling library cannot name.',
        location: requirement.sourcePath,
      ),
    );
    return null;
  }
  if (requirement.libraryUri == 'dart:core') return null;
  if (requirement.libraryUri == sourceLibrary.identifier) {
    return sourceImportUri;
  }
  if (requirement.libraryUri.startsWith('dart:') ||
      requirement.libraryUri.startsWith('package:flutter/')) {
    final normalized = _normalizeSdkImport(requirement, issues);
    if (normalized == null) return null;
    return _validateCanonicalImportBoundary(
      normalized,
      requirement: requirement,
      rootPackage: rootPackage,
      declaredDependencies: declaredDependencies,
      issues: issues,
    );
  }

  final candidates = <String>{};
  for (final import in sourceLibrary.firstFragment.libraryImports) {
    final importedLibrary = import.importedLibrary;
    if (importedLibrary == null) continue;
    final prefix = import.prefix?.name;
    final lookup =
        prefix == null ? requirement.symbol : '$prefix.${requirement.symbol}';
    final provided = import.namespace.get2(lookup);
    if (!_matchesRequirement(provided, requirement)) continue;
    candidates.add(_canonicalLibraryUri(importedLibrary));
  }
  final definingPackage = _packageName(requirement.libraryUri);
  final samePackageCandidates = definingPackage == null
      ? const <String>[]
      : candidates
          .where((candidate) => _packageName(candidate) == definingPackage)
          .toList();
  final ordered = (samePackageCandidates.isEmpty
      ? candidates.toList()
      : samePackageCandidates)
    ..sort();
  if (ordered.isEmpty) {
    issues.add(
      Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: 'No exact analyzer-resolved canonical import provides '
            '${requirement.libraryUri}#${requirement.symbol} required by '
            '${requirement.sourcePath}.',
        location: requirement.sourcePath,
      ),
    );
    return null;
  }
  if (ordered.length > 1) {
    issues.add(
      Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: '${requirement.sourcePath} has ambiguous canonical imports '
            'for ${requirement.libraryUri}#${requirement.symbol}: '
            '${ordered.join(', ')}. Narrow the source import set.',
        location: requirement.sourcePath,
      ),
    );
    return null;
  }

  return _validateCanonicalImportBoundary(
    ordered.single,
    requirement: requirement,
    rootPackage: rootPackage,
    declaredDependencies: declaredDependencies,
    issues: issues,
  );
}

String? _normalizeSdkImport(
  _ImportRequirement requirement,
  List<Issue> issues,
) {
  try {
    return publicDartImportUri(requirement.libraryUri);
    // The shared normalizer deliberately throws on unknown SDK areas. Convert
    // that contract failure into the source-path-qualified build diagnostic.
    // ignore: avoid_catching_errors
  } on StateError catch (error) {
    issues.add(
      Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: '${requirement.sourcePath} has no public Dart/Flutter import '
            'for ${requirement.libraryUri}#${requirement.symbol}: $error',
        location: requirement.sourcePath,
      ),
    );
    return null;
  }
}

String? _validateCanonicalImportBoundary(
  String canonicalUri, {
  required _ImportRequirement requirement,
  required String rootPackage,
  required Set<String> declaredDependencies,
  required List<Issue> issues,
}) {
  final uri = Uri.parse(canonicalUri);
  if (uri.scheme == 'dart') return canonicalUri;
  if (uri.scheme != 'package' || uri.pathSegments.length < 2) {
    issues.add(
      Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: '${requirement.sourcePath} resolves through non-canonical '
            'Dart import $canonicalUri; generated native imports must use '
            'dart: or package: identities.',
        location: requirement.sourcePath,
      ),
    );
    return null;
  }
  final package = uri.pathSegments.first;
  if (package != rootPackage && uri.pathSegments[1] == 'src') {
    issues.add(
      Issue(
        code: IssueCode.invalidWidgetClass,
        message: '${requirement.sourcePath} requires dependency-private '
            'import $canonicalUri; generated native code may use only '
            'public dependency libraries.',
        location: requirement.sourcePath,
      ),
    );
    return null;
  }
  if (package != rootPackage && !declaredDependencies.contains(package)) {
    issues.add(
      Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: '${requirement.sourcePath} requires package:$package, which '
            'is not a declared direct dependency in dependencies: of the '
            'authoring package.',
        location: requirement.sourcePath,
      ),
    );
    return null;
  }
  return canonicalUri;
}

String? _packageName(String libraryUri) {
  final uri = Uri.tryParse(libraryUri);
  if (uri == null || uri.scheme != 'package' || uri.pathSegments.isEmpty) {
    return null;
  }
  return uri.pathSegments.first;
}

bool _matchesRequirement(Element? element, _ImportRequirement requirement) {
  if (element == null) return false;
  final declaration = element.baseElement;
  return declaration.name == requirement.symbol &&
      declaration.library?.identifier == requirement.libraryUri;
}

String _canonicalLibraryUri(LibraryElement library) {
  final uri = library.uri;
  if (uri.scheme == 'package' || uri.scheme == 'dart') return uri.toString();
  final identifier = Uri.tryParse(library.identifier);
  if (identifier != null &&
      (identifier.scheme == 'package' || identifier.scheme == 'dart')) {
    return identifier.toString();
  }
  return uri.toString();
}

String _canonicalSourceImportUri(
  LibraryElement library,
  AssetId sourceAsset,
) {
  final uri = _canonicalLibraryUri(library);
  if (uri.startsWith('package:')) return uri;
  if (sourceAsset.path.startsWith('lib/')) {
    return 'package:${sourceAsset.package}/'
        '${sourceAsset.path.substring('lib/'.length)}';
  }
  throw StateError(
    'Could not derive a canonical package import for ${sourceAsset.path}.',
  );
}

String _elementSourcePath(Element element, AssetId contextAsset) {
  final fragment = element.firstFragment.libraryFragment;
  if (fragment == null) {
    throw StateError(
      'Could not resolve a defining library fragment for '
      '${element.displayName}.',
    );
  }
  final source = fragment.source;
  final uri = source.uri;
  if (uri.scheme == 'package' || uri.scheme == 'asset') {
    final asset = AssetId.resolve(uri);
    return asset.package == contextAsset.package ? asset.path : uri.toString();
  }
  if (uri.scheme == 'file') return source.fullName;
  if (uri.hasScheme) return uri.toString();
  throw StateError(
    'Could not resolve an exact defining source for '
    '${element.displayName}.',
  );
}

Future<_PackageGraphFacts> _readPackageGraphFacts(
  BuildStep buildStep,
  List<Issue> issues,
) async {
  const graphPath = '.dart_tool/package_graph.json';
  final asset = AssetId(buildStep.inputId.package, graphPath);
  var source = Zone.current[_packageGraphZoneKey] as String?;
  if (source == null && await buildStep.canRead(asset)) {
    source = await buildStep.readAsString(asset);
  } else if (source == null) {
    final packageConfigUri = await Isolate.packageConfig;
    if (packageConfigUri?.scheme == 'file') {
      final graphFile = File.fromUri(
        packageConfigUri!.resolve('package_graph.json'),
      );
      if (graphFile.existsSync()) source = graphFile.readAsStringSync();
    }
  }
  if (source == null) {
    issues.add(
      const Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: "Cannot validate generated native imports because Pub's "
            'generated .dart_tool/package_graph.json is unavailable. Run '
            '`dart pub get` before generation.',
        location: graphPath,
      ),
    );
    return const _PackageGraphFacts(<String>{});
  }

  final Object? document;
  try {
    document = jsonDecode(source);
  } on FormatException catch (error) {
    issues.add(
      Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: "Cannot validate generated native imports because Pub's "
            'package graph is not valid JSON: ${error.message}',
        location: graphPath,
      ),
    );
    return const _PackageGraphFacts(<String>{});
  }
  if (document is! Map<String, Object?> ||
      document['packages'] is! List<Object?>) {
    issues.add(
      const Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: "Cannot validate generated native imports because Pub's "
            'package graph has no packages list.',
        location: graphPath,
      ),
    );
    return const _PackageGraphFacts(<String>{});
  }

  final packageName = buildStep.inputId.package;
  for (final package in document['packages']! as List<Object?>) {
    if (package is! Map<String, Object?> || package['name'] != packageName) {
      continue;
    }
    final dependencies = package['dependencies'];
    if (dependencies is! List<Object?> ||
        dependencies
            .any((dependency) => dependency is! String || dependency.isEmpty)) {
      issues.add(
        Issue(
          code: IssueCode.analyzerResolutionFailed,
          message: "Cannot validate generated native imports because Pub's "
              'package graph has invalid production dependencies for '
              '$packageName.',
          location: graphPath,
        ),
      );
      return const _PackageGraphFacts(<String>{});
    }
    return _PackageGraphFacts(dependencies.cast<String>().toSet());
  }

  issues.add(
    Issue(
      code: IssueCode.analyzerResolutionFailed,
      message: "Cannot validate generated native imports because Pub's "
          'package graph has no entry for authoring package $packageName.',
      location: graphPath,
    ),
  );
  return const _PackageGraphFacts(<String>{});
}

bool _isAuthoredDartAsset(AssetId asset) =>
    asset.path.endsWith('.dart') &&
    !asset.path.endsWith('.g.dart') &&
    !asset.path.endsWith('.stories.dart');

int _compareIssues(Issue left, Issue right) {
  final byLocation = left.location.compareTo(right.location);
  if (byLocation != 0) return byLocation;
  final byCode = left.code.name.compareTo(right.code.name);
  return byCode != 0 ? byCode : left.message.compareTo(right.message);
}

final class _ImportRequirement {
  const _ImportRequirement({
    required this.libraryUri,
    required this.symbol,
    required this.sourcePath,
    this.privateMember = false,
    this.privateMemberName,
  });

  final String libraryUri;
  final String symbol;
  final String sourcePath;
  final bool privateMember;
  final String? privateMemberName;
}

final class _A2uiWidgetIdentity {
  const _A2uiWidgetIdentity({
    required this.classIdentity,
    required this.declarationSourcePath,
  });

  final String classIdentity;
  final String declarationSourcePath;
}

final class _PackageGraphFacts {
  const _PackageGraphFacts(this.dependencies);

  final Set<String> dependencies;
}
