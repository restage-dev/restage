import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_outputs.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/package_resolution.dart';
import 'package:yaml/yaml.dart';

/// The directory under the generated output root a render bundle builds in.
const renderBundleProjectDirectory = 'render_bundle';

/// The dart-define carrying the dashboard origin the bundle answers.
const renderBundleParentOriginDefine = 'RESTAGE_RENDER_BUNDLE_PARENT_ORIGIN';

/// The render bundle's entrypoint, relative to its project.
const renderBundleEntrypoint = '$_supportDirectory/main.dart';

const _supportDirectory = 'restage_render_bundle';
const _fontDirectory = '$_supportDirectory/fonts';

/// Writes the scratch project a render bundle builds in.
typedef RenderBundleProjectWriter =
    Future<Directory> Function({
      required Directory projectRoot,
      required String flutterVersion,
      required Uint8List fontBytes,
      required Uint8List licenseBytes,
    });

/// Writes the Flutter project that builds [projectRoot]'s render bundle.
///
/// The project lives under the app's generated output root and stands in for
/// the app package: its `lib` links to the app's, it declares the app's
/// assets and fonts, and it pins every package the app resolved to the
/// directory it resolved to. Nothing in the app changes.
Future<Directory> writeRenderBundleProject({
  required Directory projectRoot,
  required String flutterVersion,
  required Uint8List fontBytes,
  required Uint8List licenseBytes,
}) async {
  final root = Directory(p.normalize(projectRoot.absolute.path));
  if (!File(p.join(root.path, 'lib', 'user_factories.g.dart')).existsSync()) {
    throw const RenderBundleBuildException('factories_missing');
  }
  final standIn = await _standInProject(
    root,
    directoryName: renderBundleProjectDirectory,
    kept: _kept,
    requireRenderHost: true,
  );
  final app = standIn.app;
  final directory = standIn.directory;
  await _write(
    directory,
    'pubspec.yaml',
    utf8.encode(
      _pubspec(
        app: app,
        dependencies: standIn.dependencies,
        pins: standIn.pins,
        robotoFallback: true,
      ),
    ),
  );
  await _write(
    directory,
    renderBundleEntrypoint,
    utf8.encode(_entrypoint(appName: app.name, flutterVersion: flutterVersion)),
  );
  await _write(directory, 'web/index.html', utf8.encode(_index));
  await _write(directory, 'web/flutter_bootstrap.js', utf8.encode(_bootstrap));
  await _write(directory, '$_fontDirectory/Roboto-Regular.ttf', fontBytes);
  await _write(directory, '$_fontDirectory/Roboto_LICENSE.txt', licenseBytes);
  await _linkAppPaths(directory, root, <String>['lib', ...app.paths]);
  return directory;
}

/// The directory under the generated output root surface images render in.
const surfaceCaptureProjectDirectory = 'surface_capture';

/// Writes the Flutter project that renders [projectRoot]'s surfaces to images
/// under `flutter test`, holding [files] by project-relative path.
///
/// Like the render bundle's, it stands in for the app package, with the app's
/// resolution pinned and `flutter_test` added. Earlier images and unchanged
/// tests stay, so an unchanged surface compiles and draws nothing.
Future<Directory> writeSurfaceCaptureProject({
  required Directory projectRoot,
  required Map<String, List<int>> files,
}) async {
  final root = Directory(p.normalize(projectRoot.absolute.path));
  final standIn = await _standInProject(
    root,
    directoryName: surfaceCaptureProjectDirectory,
    kept: const <String>{
      'build',
      'images',
      'images.json',
      'pubspec.lock',
      'pubspec.yaml',
      'test',
    },
    includeDev: true,
  );
  final tests = Directory(p.join(standIn.directory.path, 'test'));
  if (tests.existsSync()) {
    await for (final entity in tests.list(followLinks: false)) {
      final path = p.posix.joinAll(
        p.split(p.relative(entity.path, from: standIn.directory.path)),
      );
      if (!files.containsKey(path)) {
        await entity.delete(recursive: entity is Directory);
      }
    }
  }
  await _write(
    standIn.directory,
    'pubspec.yaml',
    utf8.encode(
      _pubspec(
        app: standIn.app,
        dependencies: <String, Object>{
          ...standIn.dependencies,
          'flutter_test': const <String, String>{'sdk': 'flutter'},
        },
        pins: standIn.pins,
        robotoFallback: false,
        command: 'restage surface push',
      ),
    ),
  );
  for (final entry in files.entries) {
    await _write(standIn.directory, entry.key, entry.value);
  }
  await _linkAppPaths(standIn.directory, root, <String>[
    'lib',
    ...standIn.app.paths,
  ]);
  return standIn.directory;
}

typedef _StandIn = ({
  _App app,
  Directory directory,
  Map<String, Object> dependencies,
  Map<String, String> pins,
});

/// The package the render bundle's entrypoint runs, released in lockstep with
/// `restage`.
const renderHostPackage = 'restage_render_host';

/// Reads the app and its resolution, and clears the project directory of
/// everything but [kept] and dot entries.
Future<_StandIn> _standInProject(
  Directory root, {
  required String directoryName,
  required Set<String> kept,
  bool requireRenderHost = false,
  bool includeDev = false,
}) async {
  final app = _readApp(root);
  final String outputRoot;
  try {
    outputRoot =
        await readConfiguredRestageOutputRoot(root) ??
        defaultRestagePortableOutputRoot;
  } on PublicationException {
    throw const RenderBundleBuildException('output_root');
  }
  final PackageResolution resolution;
  final Set<String> closure;
  final List<String> direct;
  try {
    resolution = await PackageResolution.read(root, appName: app.name);
    closure = resolution.closure(app.name, includeDev: includeDev);
    direct = resolution.dependenciesOf(app.name);
  } on PackageResolutionException {
    throw const RenderBundleBuildException('dependencies_unresolved');
  }
  final pins = <String, String>{};
  for (final name in closure.toList()..sort()) {
    if (name == app.name || resolution.isSdkPackage(name)) continue;
    pins[name] =
        resolution.rootOf(name) ??
        (throw const RenderBundleBuildException('dependencies_unresolved'));
  }
  Object? renderHost;
  if (requireRenderHost) {
    renderHost = _renderHostDependency(
      restageRoot: closure.contains('restage') ? pins['restage'] : null,
      pins: pins,
    );
  }

  final directory = Directory(
    p.joinAll([
      root.path,
      ...p.posix.join(outputRoot, directoryName).split('/'),
    ]),
  );
  await directory.create(recursive: true);
  // Links and anything an earlier run left are rebuilt; the caches and the
  // kept files stay, so an unchanged project skips `pub get`.
  await for (final entity in directory.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name.startsWith('.') || kept.contains(name)) continue;
    await entity.delete(recursive: entity is Directory);
  }
  return (
    app: app,
    directory: directory,
    dependencies: <String, Object>{
      for (final name in direct)
        name: resolution.isSdkPackage(name)
            ? const <String, String>{'sdk': 'flutter'}
            : 'any',
      renderHostPackage: ?renderHost,
    },
    pins: pins,
  );
}

/// How the render bundle depends on the render host, given the directory
/// `restage` resolved to.
///
/// The app's own resolution wins. A `restage` with the render host beside it,
/// as in a path or git checkout of the Restage repository, pins that copy into
/// [pins]. Otherwise the hosted release with `restage`'s major and minor.
Object _renderHostDependency({
  required String? restageRoot,
  required Map<String, String> pins,
}) {
  if (restageRoot == null) {
    throw const RenderBundleBuildException('render_host_missing');
  }
  if (pins.containsKey(renderHostPackage)) return 'any';
  final sibling = p.join(p.dirname(restageRoot), renderHostPackage);
  if (_packageName(sibling) == renderHostPackage) {
    pins[renderHostPackage] = sibling;
    return 'any';
  }
  final version = _packageVersion(restageRoot);
  if (version == null) {
    throw const RenderBundleBuildException('render_host_missing');
  }
  final (major, minor) = version;
  return '>=$major.$minor.0 <$major.${minor + 1}.0';
}

String? _packageName(String root) {
  final document = _loadPubspec(root);
  final name = document is YamlMap ? document['name'] : null;
  return name is String ? name : null;
}

(int, int)? _packageVersion(String root) {
  final document = _loadPubspec(root);
  final version = document is YamlMap ? document['version'] : null;
  final match = version is String
      ? RegExp(r'^(\d+)\.(\d+)\.\d+').firstMatch(version)
      : null;
  if (match == null) return null;
  return (int.parse(match[1]!), int.parse(match[2]!));
}

Object? _loadPubspec(String root) {
  final file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  try {
    return loadYaml(file.readAsStringSync());
  } on Object {
    return null;
  }
}

/// Whether [project] was resolved against the pubspec it holds now by the
/// Flutter SDK at [flutterRoot], so `pub get` has nothing to do.
bool isRenderBundleProjectResolved(
  Directory project, {
  required Directory flutterRoot,
}) {
  final stamp = File(p.join(project.path, _resolvedStamp));
  final pubspec = File(p.join(project.path, 'pubspec.yaml'));
  return File(
        p.join(project.path, '.dart_tool', 'package_config.json'),
      ).existsSync() &&
      stamp.existsSync() &&
      pubspec.existsSync() &&
      _sameBytes(
        stamp.readAsBytesSync(),
        _stampBytes(pubspec.readAsBytesSync(), flutterRoot),
      );
}

/// Records that [project] resolved against the pubspec it holds now, with the
/// Flutter SDK at [flutterRoot].
Future<void> markRenderBundleProjectResolved(
  Directory project, {
  required Directory flutterRoot,
}) async {
  final stamp = File(p.join(project.path, _resolvedStamp));
  await stamp.parent.create(recursive: true);
  final pubspec = await File(
    p.join(project.path, 'pubspec.yaml'),
  ).readAsBytes();
  await stamp.writeAsBytes(_stampBytes(pubspec, flutterRoot));
}

/// The pubspec, headed by the SDK it resolved with: another SDK re-resolves.
Uint8List _stampBytes(List<int> pubspec, Directory flutterRoot) =>
    Uint8List.fromList(<int>[
      ...utf8.encode(
        '# flutter: ${jsonEncode(p.normalize(flutterRoot.absolute.path))}\n',
      ),
      ...pubspec,
    ]);

const _resolvedStamp = '.dart_tool/restage_resolved_pubspec.yaml';

const _kept = <String>{
  'build',
  'pubspec.lock',
  'pubspec.yaml',
  'web',
  _supportDirectory,
};

typedef _App = ({
  String name,
  Object? environment,
  List<Object?> assets,
  List<Object?> fonts,
  List<Object?> shaders,
  List<Object?> licenses,
  String? defaultFlavor,
  List<String> paths,
});

/// The app's name, SDK constraint, and the files its `flutter` section
/// bundles: assets, fonts, shaders and licenses.
/// The app's package name, from its pubspec.
String renderBundleAppName(Directory projectRoot) => _readApp(projectRoot).name;

_App _readApp(Directory projectRoot) {
  final Object? document;
  try {
    document = loadYaml(
      File(p.join(projectRoot.path, 'pubspec.yaml')).readAsStringSync(),
    );
  } on Object {
    throw const RenderBundleBuildException('project_identity');
  }
  final name = document is YamlMap ? document['name'] : null;
  if (name is! String || !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(name)) {
    throw const RenderBundleBuildException('project_identity');
  }
  final flutter = (document as YamlMap)['flutter'];
  List<Object?> listOf(String key) =>
      switch (flutter is YamlMap ? _plain(flutter[key]) : null) {
        final List<Object?> list => list,
        _ => const <Object?>[],
      };
  final assets = listOf('assets');
  final fonts = listOf('fonts');
  final shaders = listOf('shaders');
  final licenses = listOf('licenses');
  final defaultFlavor = flutter is YamlMap ? flutter['default-flavor'] : null;
  final paths = <String>[
    for (final asset in [...assets, ...shaders, ...licenses])
      if (asset is String)
        asset
      else if (asset is Map && asset['path'] is String)
        asset['path'] as String,
    for (final family in fonts)
      if (family is Map && family['fonts'] is List)
        for (final font in family['fonts'] as List)
          if (font is Map && font['asset'] is String) font['asset'] as String,
  ];
  return (
    name: name,
    environment: _plain(document['environment']),
    assets: assets,
    fonts: fonts,
    shaders: shaders,
    licenses: licenses,
    defaultFlavor: defaultFlavor is String ? defaultFlavor : null,
    paths: paths,
  );
}

Object? _plain(Object? value) => value == null
    ? null
    : jsonDecode(jsonEncode(value, toEncodable: (object) => '$object'));

/// Links each app path into [directory], shortest first, so a directory
/// entry covers the entries inside it.
Future<void> _linkAppPaths(
  Directory directory,
  Directory projectRoot,
  List<String> paths,
) async {
  final ordered = <String>{
    for (final path in paths)
      if (_isPackageRelative(path))
        path.endsWith('/') ? path.substring(0, path.length - 1) : path,
  }.toList()..sort((left, right) => left.length.compareTo(right.length));
  for (final path in ordered) {
    final target = p.joinAll([projectRoot.path, ...path.split('/')]);
    if (FileSystemEntity.typeSync(target) == FileSystemEntityType.notFound) {
      continue;
    }
    final link = p.joinAll([directory.path, ...path.split('/')]);
    if (FileSystemEntity.typeSync(link) != FileSystemEntityType.notFound) {
      continue;
    }
    await Directory(p.dirname(link)).create(recursive: true);
    await Link(link).create(p.relative(target, from: p.dirname(link)));
  }
}

bool _isPackageRelative(String path) {
  if (path.isEmpty || path.startsWith('/') || path.contains(r'\')) {
    return false;
  }
  final segments = path.split('/');
  if (segments.last.isEmpty) segments.removeLast();
  return segments.isNotEmpty &&
      segments.every(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      );
}

String _pubspec({
  required _App app,
  required Map<String, Object> dependencies,
  required Map<String, String> pins,
  required bool robotoFallback,
  String command = 'restage build push',
}) {
  final buffer = StringBuffer()
    ..writeln('# Generated by `$command`. Rewritten on every run.')
    ..writeln('name: ${app.name}')
    ..writeln('publish_to: none')
    ..writeln()
    ..writeln(
      'environment: ${jsonEncode(app.environment ?? const {'sdk': '^3.5.0'})}',
    )
    ..writeln()
    ..writeln('dependencies:');
  for (final entry in dependencies.entries) {
    buffer.writeln('  ${entry.key}: ${jsonEncode(entry.value)}');
  }
  buffer
    ..writeln()
    ..writeln('dependency_overrides:');
  for (final name in pins.keys.toList()..sort()) {
    buffer.writeln('  $name: ${jsonEncode({'path': pins[name]})}');
  }
  buffer
    ..writeln()
    ..writeln('flutter:')
    ..writeln('  uses-material-design: true');
  if (robotoFallback || app.assets.isNotEmpty) buffer.writeln('  assets:');
  if (robotoFallback) {
    buffer.writeln('    - $_fontDirectory/Roboto_LICENSE.txt');
  }
  for (final asset in app.assets) {
    buffer.writeln('    - ${jsonEncode(asset)}');
  }
  if (robotoFallback || app.fonts.isNotEmpty) buffer.writeln('  fonts:');
  if (robotoFallback) {
    buffer
      ..writeln('    - family: Roboto')
      ..writeln('      fonts:')
      ..writeln('        - asset: $_fontDirectory/Roboto-Regular.ttf');
  }
  for (final font in app.fonts) {
    buffer.writeln('    - ${jsonEncode(font)}');
  }
  for (final (key, entries) in [
    ('shaders', app.shaders),
    ('licenses', app.licenses),
  ]) {
    if (entries.isEmpty) continue;
    buffer.writeln('  $key:');
    for (final entry in entries) {
      buffer.writeln('    - ${jsonEncode(entry)}');
    }
  }
  if (app.defaultFlavor case final flavor?) {
    buffer.writeln('  default-flavor: ${jsonEncode(flavor)}');
  }
  return buffer.toString();
}

String _entrypoint({required String appName, required String flutterVersion}) =>
    '''
// Generated by `restage build push`. Rewritten on every build.
import 'package:$appName/user_factories.g.dart';
import 'package:restage_render_host/restage_render_host.dart';

Future<void> main() => runRestageRenderBundle(
  registerWidgets: registerRestageWidgets,
  parentOrigin: const String.fromEnvironment('$renderBundleParentOriginDefine'),
  flutterVersion: ${jsonEncode(flutterVersion)},
);
''';

const _index = '''
<!DOCTYPE html>
<html>
<head>
  <base href="\$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <title>Render bundle</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

// No renderer is named, so a browser without Skwasm takes the CanvasKit
// fallback build.
const _bootstrap = '''
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
    fontFallbackBaseUrl: 'assets/fonts/fallback/',
  },
});
''';

/// Writes [bytes] to [path] under [directory] unless it already holds them.
Future<void> _write(Directory directory, String path, List<int> bytes) async {
  final file = File(p.joinAll([directory.path, ...path.split('/')]));
  if (file.existsSync() && _sameBytes(await file.readAsBytes(), bytes)) return;
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
