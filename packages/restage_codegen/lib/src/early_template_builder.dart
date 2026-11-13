import 'dart:io' show Directory, File;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/build_delivery.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/measurement/measurement_configuration.dart';
import 'package:restage_codegen/src/restage_source_prefilter.dart';
import 'package:restage_codegen/src/surface_publication/placement_self_fit.dart';
import 'package:restage_codegen/src/surface_publication/surface_list_builder.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show PlacementKeyV1;
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:yaml/yaml.dart';

/// Where the Android build reads the startup request template.
const String kEarlyTemplateAndroidPath =
    'android/app/src/main/assets/restage_early.json';

/// Where the iOS build reads the startup request template.
const String kEarlyTemplateIosPath = 'ios/Runner/restage_early.json';

/// Writes the startup request templates the platform sends at app launch.
///
/// The request is computed from the generated code: the declared placements,
/// their host contracts and the widgets, icons and libraries the app installs.
/// The service URL, publishable key and channel are the ones the generated
/// registration carries from build.yaml; without them no template is written.
final class RestageEarlyTemplateBuilder implements Builder {
  /// Notes which of [options] moved to the user_factories builder.
  RestageEarlyTemplateBuilder(BuilderOptions options)
    : _movedOptions = [
        for (final key in const ['api_key', 'base_url', 'channel'])
          if (options.config.containsKey(key)) key,
      ];

  // Options this builder no longer reads; user_factories holds them now.
  final List<String> _movedOptions;

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': [kEarlyTemplateAndroidPath, kEarlyTemplateIosPath],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    if (_movedOptions.isNotEmpty) {
      log.warning(
        'build.yaml sets ${_movedOptions.join(', ')} under '
        'restage_codegen:restage_early_template, which the build no longer '
        'reads. Try moving them to the restage_codegen:user_factories '
        'options, or run `restage init`.',
      );
    }
    final templates = await _templates(buildStep);
    if (templates[kEarlyTemplateAndroidPath] case final android?) {
      await buildStep.writeAsString(
        AssetId(package, kEarlyTemplateAndroidPath),
        android,
      );
    }
    if (!_hasPlatformDirectory(kEarlyTemplateIosPath)) return;
    final listed = await _listsIosAsset(buildStep);
    final ios = templates[kEarlyTemplateIosPath];
    if (ios != null && !listed) {
      log.warning(
        'iOS sends the first-launch request only when pubspec.yaml lists '
        '`$kEarlyTemplateIosPath` under `flutter: assets:`. Try '
        '`restage init`, or add that line.',
      );
    }
    // A listed asset must exist, so an app with no request gets an empty one.
    if (ios != null || listed) {
      await buildStep.writeAsString(
        AssetId(package, kEarlyTemplateIosPath),
        ios ?? '{}\n',
      );
    }
  }

  // The templates to write, by path; empty when the build has none.
  Future<Map<String, String>> _templates(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final listId = AssetId(package, kRestageSurfaceListPath);
    final factoriesId = AssetId(package, 'lib/user_factories.g.dart');
    if (!await buildStep.canRead(listId)) return const {};
    if (!await buildStep.canRead(factoriesId)) return const {};
    final factories = await buildStep.readAsString(factoriesId);
    // The generated registration owns the build's key, URL and channel; the
    // user_factories build reports when they are missing.
    final delivery = _buildDelivery(factories);
    if (delivery == null) return const {};
    final (:apiKey, :baseUrl, :channel, :analytics) = delivery;
    final measurement = await _measurementEnabled(buildStep);
    // The generated registration says which catalog the app installs.
    final wholeCatalog = factories.contains('RestageWidgetLibraries.builtIn(');
    if (!wholeCatalog &&
        !factories.contains('kRestageAppVocabulary.addToInstalled')) {
      return const {};
    }

    final declared = await _declaredDefinitions(buildStep, listId);
    if (declared.isEmpty) return const {};
    final vocabulary = _Vocabulary()..scan(factories);
    await for (final id in buildStep.findAssets(
      Glob('lib/**.restage.g.dart'),
    )) {
      vocabulary.scan(await buildStep.readAsString(id));
    }
    final catalog = await loadMergedCatalog(buildStep);
    final builtInVersion = _builtInCatalogVersion(catalog);
    if (wholeCatalog) {
      for (final widget in catalog.widgets) {
        final library = widget.library;
        if (library == WidgetLibrary.core ||
            library == WidgetLibrary.material ||
            library == WidgetLibrary.cupertino) {
          vocabulary.widgetNames.add(
            WidgetVocabulary.qualifiedName(library.namespace, widget.name),
          );
        }
      }
      vocabulary.widgetNames.add(
        WidgetVocabulary.qualifiedName(
          WidgetLibrary.core.namespace,
          kBuilderContinuationWidgetName,
        ),
      );
      // The whole catalog installs widgets only; icons come from the app's
      // and the surfaces' vocabulary, as at runtime.
    }

    final capability = computeInstalledCapability(
      builtInCatalogVersion: builtInVersion,
      installedLibraries: vocabulary.libraries.values,
      widgetNames: vocabulary.widgetNames,
      iconCodePoints: vocabulary.iconCodePoints,
    );
    final mounts = <PlacementMountRequestV1>[];
    final contracts = <String, SurfaceHostContractV1>{};
    for (final definition in declared) {
      final locator = DeliverySurfaceLocatorV1.fromJson(definition.locator);
      final host = SurfaceHostContractV1.fromJson(definition.host);
      final mount = PlacementMountRequestV1(
        key: PlacementKeyV1.generatedDefault(
          surfaceType: locator.surfaceType,
          slug: locator.slug,
        ),
        hostContractHash: host.contentHash,
        defaultSurface: locator,
      );
      if (mounts.contains(mount)) continue;
      mounts.add(mount);
      contracts[host.contentHash] = host;
    }

    final templates = <String, String>{};
    for (final (platform, path) in [
      ('android', kEarlyTemplateAndroidPath),
      ('ios', kEarlyTemplateIosPath),
    ]) {
      // Skip a platform the app does not have.
      if (!_hasPlatformDirectory(path)) continue;
      final request = startupRequestFor(
        platform: platform,
        mounts: mounts,
        contractsByHash: contracts,
        capability: capability,
        buildOrdinal: 1,
        builtIns: {
          'appBuildOrdinal': 1,
          'country': 'us',
          'daysSinceInstall': 0,
          'channel': ?channel,
          'deviceClass': 'phone',
          'language': 'en',
          'osVersion': 1,
          'platform': platform,
          'sdkApiLevel': kAssignmentSdkApiLevel,
        },
      );
      final template = startupTemplateJson(
        placementResolveUrl(baseUrl),
        apiKey,
        request,
        identityTokens: true,
        analytics: analytics,
        measurement: measurement,
      );
      if (template != null) templates[path] = template;
    }
    return templates;
  }

  // Whether pubspec.yaml lists the iOS template as a Flutter asset. A target
  // whose `sources:` leave pubspec.yaml out is read from the package root.
  static Future<bool> _listsIosAsset(BuildStep buildStep) async {
    final pubspec = AssetId(buildStep.inputId.package, 'pubspec.yaml');
    final file = File('pubspec.yaml');
    final String text;
    if (await buildStep.canRead(pubspec)) {
      text = await buildStep.readAsString(pubspec);
    } else if (file.existsSync()) {
      text = file.readAsStringSync();
    } else {
      return false;
    }
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException {
      return false;
    }
    if (doc is! YamlMap) return false;
    final flutter = doc['flutter'];
    final assets = flutter is YamlMap ? flutter['assets'] : null;
    if (assets is! YamlList) return false;
    return assets.any(
      (entry) =>
          entry == kEarlyTemplateIosPath ||
          (entry is YamlMap && entry['path'] == kEarlyTemplateIosPath),
    );
  }

  // The app's `measurementEnabled`; an unresolved one, which the surface
  // compiler reports, registers nothing.
  static Future<bool> _measurementEnabled(BuildStep buildStep) async {
    final result = await resolveMeasurementConfiguration(
      buildStep,
      candidates: await selectRestageMeasurementConfigurationCandidates(
        buildStep,
      ),
    );
    return result.isValid && result.enabled;
  }

  static bool _hasPlatformDirectory(String path) => Directory(
    path.startsWith('ios') ? 'ios/Runner' : 'android/app',
  ).existsSync();

  static int _builtInCatalogVersion(Catalog catalog) {
    final builtIn = {
      WidgetLibrary.core,
      WidgetLibrary.material,
      WidgetLibrary.cupertino,
    };
    final version = contentVersionOf(
      catalog.widgets.where((w) => builtIn.contains(w.library)),
    );
    return version >= kFormattingExpressionClientFloor
        ? version
        : kFormattingExpressionClientFloor;
  }
}

/// The key, service URL and channel the generated registration's constants
/// spell.
BuildDelivery? _buildDelivery(String factories) {
  const names = {
    kBuildApiKeyName,
    kBuildBaseUrlName,
    kBuildChannelName,
    kBuildAnalyticsName,
  };
  final values = <String, Object>{};
  parseString(content: factories, throwIfDiagnostics: false).unit.accept(
    _Visitor(
      onVariable: (node) {
        final name = node.name.lexeme;
        if (!names.contains(name)) return;
        if (generatedLiteralValue(node.initializer) case final Object value) {
          values[name] = value;
        }
      },
    ),
  );
  if (values[kBuildApiKeyName] case final String apiKey) {
    if (values[kBuildBaseUrlName] case final String baseUrl) {
      return (
        apiKey: apiKey,
        baseUrl: baseUrl,
        channel: values[kBuildChannelName] as String?,
        analytics: values[kBuildAnalyticsName] != false,
      );
    }
  }
  return null;
}

/// A placement the app declares at startup, from its generated literals.
final class _Definition {
  _Definition(this.locator, this.host);
  final Map<String, Object?> locator;
  final Map<String, Object?> host;
}

Future<List<_Definition>> _declaredDefinitions(
  BuildStep buildStep,
  AssetId listId,
) async {
  final list = parseString(
    content: await buildStep.readAsString(listId),
    throwIfDiagnostics: false,
  ).unit;
  final aliases = <String, Uri>{
    for (final directive in list.directives.whereType<ImportDirective>())
      if (directive.prefix case final prefix?)
        prefix.name: Uri.parse(directive.uri.stringValue ?? ''),
  };
  final calls = <(String, String)>[];
  list.accept(
    _Visitor(
      onInvocation: (node) {
        final target = node.target;
        if (target is SimpleIdentifier &&
            aliases.containsKey(target.name) &&
            node.methodName.name.endsWith('PlacementDefinition')) {
          calls.add((target.name, node.methodName.name));
        }
      },
    ),
  );
  final result = <_Definition>[];
  for (final (alias, provider) in calls) {
    final libraryId = AssetId.resolve(aliases[alias]!, from: listId);
    final texts = [await buildStep.readAsString(libraryId)];
    final library = parseString(
      content: texts.first,
      throwIfDiagnostics: false,
    );
    for (final part in library.unit.directives.whereType<PartDirective>()) {
      final uri = part.uri.stringValue;
      if (uri == null) continue;
      texts.add(
        await buildStep.readAsString(
          AssetId.resolve(Uri.parse(uri), from: libraryId),
        ),
      );
    }
    final variable = '_${provider}Value';
    for (final text in texts) {
      final unit = parseString(content: text, throwIfDiagnostics: false).unit;
      unit.accept(
        _Visitor(
          onVariable: (node) {
            if (node.name.lexeme != variable) return;
            final init = node.initializer;
            if (init is! MethodInvocation ||
                init.methodName.name != 'generatedPlacementDefinition') {
              return;
            }
            Object? named(String name) {
              for (final arg in init.argumentList.arguments) {
                if (arg is NamedArgument && arg.name.lexeme == name) {
                  return generatedLiteralValue(arg.argumentExpression);
                }
              }
              return null;
            }

            final locator = named('defaultSurfaceLocatorJson');
            final host = named('hostContractJson');
            if (locator is Map<String, Object?> &&
                host is Map<String, Object?>) {
              result.add(_Definition(locator, host));
            }
          },
        ),
      );
    }
  }
  return result;
}

/// The widgets, icons and libraries the generated code installs.
final class _Vocabulary {
  final widgetNames = <String>{};
  final iconCodePoints = <String, Set<int>>{};
  final libraries = <String, InstalledLibrary>{};

  void scan(String source) {
    parseString(content: source, throwIfDiagnostics: false).unit.accept(
      _Visitor(onInvocation: _visit, onCreation: _visitCreation),
    );
  }

  void _visitCreation(InstanceCreationExpression node) => _dispatch(
    node.constructorName.toString(),
    node.argumentList,
  );

  void _visit(MethodInvocation node) => _dispatch(
    '${node.target == null ? '' : '${node.target}.'}${node.methodName.name}',
    node.argumentList,
  );

  void _dispatch(String name, ArgumentList args) {
    Expression? named(String key) {
      for (final arg in args.arguments) {
        if (arg is NamedArgument && arg.name.lexeme == key) {
          return arg.argumentExpression;
        }
      }
      return null;
    }

    switch (name) {
      case 'RestageWidgetLibraries.fromVocabulary':
        for (final family in ['core', 'material', 'cupertino']) {
          final map = named(family);
          if (generatedLiteralValue(map)
              case final Map<String, Object?> entries) {
            for (final widget in entries.keys) {
              widgetNames.add(
                WidgetVocabulary.qualifiedName('restage.$family', widget),
              );
            }
          }
        }
      case 'RestageIconTable.fromFamilies':
        for (final table in ['families', 'mirrored']) {
          final map = named(table);
          if (map is SetOrMapLiteral) {
            for (final family in map.elements.whereType<MapLiteralEntry>()) {
              final key = generatedLiteralValue(family.key);
              final icons = family.value;
              if (key is String && icons is SetOrMapLiteral) {
                (iconCodePoints[key] ??= <int>{}).addAll([
                  for (final icon
                      in icons.elements.whereType<MapLiteralEntry>())
                    if (generatedLiteralValue(icon.key) case final int code)
                      code,
                ]);
              }
            }
          }
        }
      case 'RestageWidgetLibraryRegistration.constant':
        _library(named('library'), args, named);
      case 'Restage.registerWidgetLibrary':
        _library(args.arguments.first.argumentExpression, args, named);
    }
  }

  void _library(
    Expression? library,
    ArgumentList args,
    Expression? Function(String) named,
  ) {
    String? namespace;
    if (library is MethodInvocation && library.methodName.name == 'custom') {
      final value = generatedLiteralValue(
        library.argumentList.arguments.first.argumentExpression,
      );
      if (value is String) namespace = value;
    }
    if (namespace == null) return;
    int? number(String key) {
      final value = named(key);
      return value == null ? null : generatedLiteralValue(value) as int?;
    }

    libraries[namespace] = InstalledLibrary(
      namespace: namespace,
      version: number('capabilityVersion'),
      compatibleSince: number('compatibleSince'),
      generated: number('generatedVersion'),
    );
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor({this.onInvocation, this.onCreation, this.onVariable});
  final void Function(MethodInvocation)? onInvocation;
  final void Function(InstanceCreationExpression)? onCreation;
  final void Function(VariableDeclaration)? onVariable;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    onInvocation?.call(node);
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    onCreation?.call(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    onVariable?.call(node);
    super.visitVariableDeclaration(node);
  }
}
