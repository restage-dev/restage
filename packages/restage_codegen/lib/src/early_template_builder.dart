import 'dart:io' show Directory, Platform;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/surface_publication/surface_list_builder.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show PlacementKeyV1;
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Where the Android build reads the startup request template.
const String kEarlyTemplateAndroidPath =
    'android/app/src/main/assets/restage_early.json';

/// Where the iOS build reads the startup request template.
const String kEarlyTemplateIosPath = 'ios/Runner/restage_early.json';

/// Writes the startup request templates the platform sends at app launch.
///
/// The request is computed from the generated code: the declared placements,
/// their host contracts and the widgets, icons and libraries the app installs.
/// Options `base_url` and `api_key` (or the environment variables
/// `RESTAGE_BASE_URL` and `RESTAGE_API_KEY`) name the service and the
/// publishable key; `channel` names the delivery channel the app configures.
final class RestageEarlyTemplateBuilder implements Builder {
  RestageEarlyTemplateBuilder(BuilderOptions options)
    : _baseUrl = _option(options, 'base_url', 'RESTAGE_BASE_URL'),
      _apiKey = _option(options, 'api_key', 'RESTAGE_API_KEY'),
      _channel = options.config['channel'] as String?,
      _enabled = options.config['early_request'] != false;

  final String? _baseUrl;
  final String? _apiKey;
  final String? _channel;
  final bool _enabled;

  /// Only an explicit RESTAGE_EARLY_REQUEST=false builds without the settings.
  static bool get _unattended =>
      Platform.environment['RESTAGE_EARLY_REQUEST'] == 'false';

  static String? _option(BuilderOptions options, String key, String env) {
    final value = options.config[key];
    if (value is String && value.isNotEmpty) return value;
    final fromEnv = Platform.environment[env];
    return fromEnv == null || fromEnv.isEmpty ? null : fromEnv;
  }

  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': [kEarlyTemplateAndroidPath, kEarlyTemplateIosPath],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final baseUrl = _baseUrl;
    final apiKey = _apiKey;
    final listId = AssetId(package, kRestageSurfaceListPath);
    final factoriesId = AssetId(package, 'lib/user_factories.g.dart');
    if (!await buildStep.canRead(listId)) return;
    if (!_enabled) return;
    if (baseUrl == null || apiKey == null) {
      // A script that opts out through the environment builds without.
      if (_unattended) {
        log.info('restage_early_template: no settings, so no startup request.');
        return;
      }
      log.severe(
        _missingConfigMessage(
          missing: [
            if (baseUrl == null) 'base_url',
            if (apiKey == null) 'api_key',
          ],
        ),
      );
      return;
    }
    final hasFactories = await buildStep.canRead(factoriesId);
    final factories = hasFactories
        ? await buildStep.readAsString(factoriesId)
        : '';
    // Without app widgets the app installs the whole catalog through
    // Restage.configure; with them, the generated registration says which.
    final wholeCatalog =
        !hasFactories || factories.contains('RestageWidgetLibraries.builtIn(');
    if (hasFactories &&
        !wholeCatalog &&
        !factories.contains('kRestageAppVocabulary.addToInstalled')) {
      return;
    }

    final declared = await _declaredDefinitions(buildStep, listId);
    if (declared.isEmpty) return;
    final vocabulary = _Vocabulary();
    if (hasFactories) vocabulary.scan(factories);
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
      builtInIconCodePoints().forEach((family, points) {
        (vocabulary.iconCodePoints[family] ??= <int>{}).addAll(points);
      });
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
          if (_channel != null) 'channel': _channel,
          'deviceClass': 'phone',
          'language': 'en',
          'osVersion': 1,
          'platform': platform,
          'sdkApiLevel': kAssignmentSdkApiLevel,
        },
      );
      final template = startupTemplateJson(
        Uri.parse('$baseUrl/sdk/v1/placements/resolve'),
        apiKey,
        request,
        identityTokens: true,
      );
      if (template == null) continue;
      await buildStep.writeAsString(AssetId(package, path), template);
    }
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
                  return _literal(arg.argumentExpression);
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
          if (_literal(map) case final Map<String, Object?> entries) {
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
              final key = _literal(family.key);
              final icons = family.value;
              if (key is String && icons is SetOrMapLiteral) {
                (iconCodePoints[key] ??= <int>{}).addAll([
                  for (final icon
                      in icons.elements.whereType<MapLiteralEntry>())
                    if (_literal(icon.key) case final int code) code,
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
      final value = _literal(
        library.argumentList.arguments.first.argumentExpression,
      );
      if (value is String) namespace = value;
    }
    if (namespace == null) return;
    int? number(String key) {
      final value = named(key);
      return value == null ? null : _literal(value) as int?;
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

/// The JSON value a generated literal spells, or null when it is not one.
Object? _literal(Expression? node) => switch (node) {
  null => null,
  NullLiteral() => null,
  BooleanLiteral(:final value) => value,
  IntegerLiteral(:final value) => value,
  DoubleLiteral(:final value) => value,
  SimpleStringLiteral(:final value) => value,
  AdjacentStrings(:final strings) =>
    strings.map((s) => _literal(s) as String).join(),
  PrefixExpression(operator: final op, :final operand) when op.lexeme == '-' =>
    -(_literal(operand)! as num),
  ListLiteral(:final elements) => [
    for (final e in elements) _literal(e as Expression),
  ],
  SetOrMapLiteral(:final elements) => {
    for (final e in elements.whereType<MapLiteralEntry>())
      _literal(e.key)! as String: _literal(e.value),
  },
  ParenthesizedExpression(:final expression) => _literal(expression),
  _ => null,
};

/// What a developer reads when the startup request settings are missing.
String _missingConfigMessage({required List<String> missing}) =>
    '''
Restage needs the service URL and publishable key at build time to build the
startup request into your app. Missing in build.yaml: ${missing.join(', ')}.

Add these lines to build.yaml (use the same baseUrl and apiKey you pass to
Restage.configure):

targets:
  \$default:
    builders:
      restage_codegen:restage_early_template:
        options:
          base_url: https://api.restage.dev
          api_key: rs_pk_your_publishable_key

`restage init --sdk-key rs_pk_...` writes them for you. To build without the
startup request, set `early_request: false` under options instead, or set RESTAGE_EARLY_REQUEST=false in
the environment for one run.''';
