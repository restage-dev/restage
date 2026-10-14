import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/flutter_toolchain.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_project.dart';
import 'package:restage_cli/src/render_bundles/surface_capture_source.dart';
import 'package:restage_shared/restage_shared.dart';

/// The logical frame a surface image is drawn at, one pixel per point: the
/// dashboard's gallery frame, its default device's screen.
const surfaceCaptureWidth = 440.0;

/// See [surfaceCaptureWidth].
const surfaceCaptureHeight = 956.0;

/// The name a surface's image and capture test go by.
String surfaceImageName({required String surfaceType, required String slug}) =>
    '$surfaceType.$slug';

/// What a capture run produced: an image or a reason for each surface, by
/// [surfaceImageName], or one reason for all of them.
final class SurfaceCaptureResult {
  const SurfaceCaptureResult({
    this.images = const <String, Uint8List>{},
    this.skipped = const <String, String>{},
    this.failure,
  });

  /// Validated PNGs by image name.
  final Map<String, Uint8List> images;

  /// Why a surface has no image, by image name.
  final Map<String, String> skipped;

  /// Why no surface has an image.
  final String? failure;
}

/// Renders pushed surfaces to images with the app's own code. Completing
/// [cancel] stops a render in progress.
typedef SurfaceImageCapturer =
    Future<SurfaceCaptureResult> Function({
      required Directory projectRoot,
      required List<SurfacePublicationManifestEntry> entries,
      String? flagRoot,
      String? configRoot,
      Duration timeout,
      Future<void>? cancel,
    });

/// Starts a process whose output the caller drains.
typedef SurfaceCaptureProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// How long a capture may take, across resolving and rendering.
const surfaceCaptureTimeout = Duration(minutes: 4);

/// Renders every entry with a generated widget in one `flutter test` run.
///
/// A surface whose inputs are unchanged since its last capture reuses that
/// image. An entry the run cannot draw is reported in
/// [SurfaceCaptureResult.skipped]. The whole run shares one [timeout]; a
/// process still running when it passes, or when [cancel] completes, is
/// killed.
Future<SurfaceCaptureResult> captureSurfaceImages({
  required Directory projectRoot,
  required List<SurfacePublicationManifestEntry> entries,
  String? flagRoot,
  String? configRoot,
  Duration timeout = surfaceCaptureTimeout,
  Future<void>? cancel,
  RenderBundleProcessRunner? processRunner,
  SurfaceCaptureProcessStarter? processStarter,
}) async {
  if (entries.isEmpty) return const SurfaceCaptureResult();
  final deadline = DateTime.now().add(timeout);
  final root = Directory(p.normalize(projectRoot.absolute.path));
  final run = processRunner ?? runRenderBundleProcess;
  final start = processStarter ?? _startProcess;
  try {
    final appName = renderBundleAppName(root);

    // Sources come first: a project with nothing to draw starts no process.
    final skipped = <String, String>{};
    final sources = <String, String>{};
    final entryJson = <String, String>{};
    for (final entry in entries) {
      final publication = entry.publication;
      final name = surfaceImageName(
        surfaceType: publication.surface.wireName,
        slug: publication.slug,
      );
      if (publication.mountName == null &&
          publication.surface != Surface.paywall) {
        skipped[name] = 'it has no generated widget to draw';
        continue;
      }
      final schema = publication.hostDataContract;
      try {
        sources[name] = surfaceCaptureTestSource(
          projectRoot: root,
          appName: appName,
          entry: entry,
          name: name,
          sample: schema == null
              ? const <String, Object?>{}
              : sampleHostContext(schema),
        );
        entryJson[name] = jsonEncode(entry.toJson());
      } on SurfaceCaptureSourceException catch (error) {
        skipped[name] = error.reason;
      }
    }
    if (sources.isEmpty) return SurfaceCaptureResult(skipped: skipped);

    final FlutterToolchain toolchain;
    try {
      toolchain = await resolveBuildFlutterToolchain(
        projectRoot: root,
        flagRoot: flagRoot,
        configRoot: configRoot,
        processRunner: run,
      );
    } on FlutterToolchainException catch (error) {
      return SurfaceCaptureResult(failure: error.message, skipped: skipped);
    }
    final fontFiles = _fontFiles(toolchain);
    if (fontFiles == null) {
      return SurfaceCaptureResult(
        failure: "Flutter's fonts are not downloaded; run `flutter precache`",
        skipped: skipped,
      );
    }

    final support = surfaceCaptureSupportSource(
      width: surfaceCaptureWidth,
      height: surfaceCaptureHeight,
      fontFiles: fontFiles,
    );
    final project = await writeSurfaceCaptureProject(
      projectRoot: root,
      files: <String, List<int>>{
        'test/restage_capture.dart': utf8.encode(support),
        for (final MapEntry(key: name, value: source) in sources.entries)
          _testPath(name): utf8.encode(source),
      },
    );
    final images = Directory(p.join(project.path, _imagesDirectory));
    await images.create(recursive: true);

    // A surface is drawn again only when something it renders from changed.
    final shared = _digest([
      toolchain.root,
      toolchain.version,
      support,
      File(p.join(project.path, 'pubspec.yaml')).readAsStringSync(),
    ]);
    final app = _appDigest(root);
    final record = _CaptureRecord.read(project);
    final captured = <String, Uint8List>{};
    final stale = <String, String>{};
    for (final MapEntry(key: name, value: source) in sources.entries) {
      final fingerprint = _digest([shared, entryJson[name]!, source, app]);
      final image = File(p.join(images.path, '$name.png'));
      if (record.fingerprints[name] == fingerprint && image.existsSync()) {
        captured[name] = image.readAsBytesSync();
      } else {
        stale[name] = fingerprint;
        record.fingerprints.remove(name);
        if (image.existsSync()) image.deleteSync();
      }
    }
    if (stale.isEmpty) {
      return SurfaceCaptureResult(images: captured, skipped: skipped);
    }

    final flutterSdk = Directory(toolchain.root);
    if (!isRenderBundleProjectResolved(project, flutterRoot: flutterSdk)) {
      final resolved = await _runUntil(
        start,
        toolchain.executable,
        const <String>['pub', 'get'],
        workingDirectory: project.path,
        deadline: deadline,
        cancel: cancel,
      );
      if (resolved != 0) {
        return SurfaceCaptureResult(
          failure:
              'its dependencies did not resolve in '
              '${p.relative(project.path, from: root.path)}',
          skipped: skipped,
        );
      }
      await markRenderBundleProjectResolved(project, flutterRoot: flutterSdk);
    }
    await _runUntil(
      start,
      toolchain.executable,
      <String>[
        'test',
        '--no-pub',
        for (final name in stale.keys) _testPath(name),
      ],
      workingDirectory: project.path,
      deadline: deadline,
      cancel: cancel,
    );

    for (final MapEntry(key: name, value: fingerprint) in stale.entries) {
      final file = File(p.join(images.path, '$name.png'));
      if (!file.existsSync()) {
        skipped[name] = _testFailure(name, root, project);
        continue;
      }
      final bytes = file.readAsBytesSync();
      try {
        validateRenderBundleSnapshotPng(bytes);
        captured[name] = bytes;
        record.fingerprints[name] = fingerprint;
      } on FormatException {
        skipped[name] = 'its image is not one the dashboard accepts';
      }
    }
    record.write(project);
    return SurfaceCaptureResult(images: captured, skipped: skipped);
  } on TimeoutException {
    return const SurfaceCaptureResult(failure: 'rendering took too long');
  } on _CaptureCancelled {
    return const SurfaceCaptureResult(failure: 'the push stopped first');
  } on RenderBundleBuildException catch (error) {
    return SurfaceCaptureResult(failure: _buildFailure(error.reason));
  } on FileSystemException catch (error) {
    return SurfaceCaptureResult(failure: 'could not write ${error.path}');
  } on ProcessException {
    return const SurfaceCaptureResult(failure: 'Flutter could not be started');
  }
}

Future<Process> _startProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) => Process.start(executable, arguments, workingDirectory: workingDirectory);

final class _CaptureCancelled implements Exception {
  const _CaptureCancelled();
}

/// Runs a process to completion, killing it if [deadline] passes or [cancel]
/// completes first.
Future<int> _runUntil(
  SurfaceCaptureProcessStarter start,
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required DateTime deadline,
  Future<void>? cancel,
}) async {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) throw TimeoutException(null);
  final process = await start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  // The output is not read, but a full pipe would stall the process.
  final drained = Future.wait([
    process.stdout.drain<void>(),
    process.stderr.drain<void>(),
  ]);
  final stopped = Completer<Exception>();
  final timer = Timer(remaining, () {
    if (!stopped.isCompleted) stopped.complete(TimeoutException(null));
  });
  unawaited(
    cancel?.then((_) {
      if (!stopped.isCompleted) stopped.complete(const _CaptureCancelled());
    }),
  );
  try {
    final outcome = await Future.any<Object>([
      process.exitCode,
      stopped.future,
    ]);
    if (outcome is Exception) {
      process.kill();
      // A tool that ignores the polite signal is stopped outright.
      await process.exitCode.timeout(
        _killGrace,
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      throw outcome;
    }
    await drained;
    return outcome as int;
  } finally {
    timer.cancel();
  }
}

const _killGrace = Duration(seconds: 5);

/// The directory in the capture project that holds the latest images.
const _imagesDirectory = 'images';

String _testPath(String name) => 'test/${name}_test.dart';

/// The fingerprints of the images in the capture project, by image name.
final class _CaptureRecord {
  _CaptureRecord(this.fingerprints);

  factory _CaptureRecord.read(Directory project) {
    try {
      final decoded = jsonDecode(
        File(p.join(project.path, _recordFile)).readAsStringSync(),
      );
      if (decoded is Map<String, Object?>) {
        return _CaptureRecord({
          for (final MapEntry(:key, :value) in decoded.entries)
            if (value is String) key: value,
        });
      }
    } on Object {
      // A missing or unreadable record draws everything again.
    }
    return _CaptureRecord(<String, String>{});
  }

  final Map<String, String> fingerprints;

  void write(Directory project) => File(
    p.join(project.path, _recordFile),
  ).writeAsStringSync(jsonEncode(fingerprints));
}

const _recordFile = 'images.json';

String _digest(List<String> parts) =>
    crypto.sha256.convert(utf8.encode(jsonEncode(parts))).toString();

/// A digest of the app's Dart sources and resolved packages: any change to
/// them draws every surface again.
String _appDigest(Directory root) {
  final lib = Directory(p.join(root.path, 'lib'));
  final files = lib.existsSync()
      ? [
          for (final entity in lib.listSync(recursive: true))
            if (entity is File && entity.path.endsWith('.dart')) entity,
        ]
      : <File>[];
  final lock = File(p.join(root.path, 'pubspec.lock'));
  return _digest([
    for (final file in files..sort((a, b) => a.path.compareTo(b.path)))
      '${p.relative(file.path, from: root.path)}:${_digest([file.readAsStringSync()])}',
    if (lock.existsSync()) lock.readAsStringSync(),
  ]);
}

/// The SDK's own fonts, by family, so text and icons draw as on a device, or
/// null when the SDK has not downloaded them.
Map<String, List<String>>? _fontFiles(FlutterToolchain toolchain) {
  final fonts = Directory(
    p.join(toolchain.root, 'bin', 'cache', 'artifacts', 'material_fonts'),
  );
  if (!fonts.existsSync()) return null;
  final roboto = [
    for (final entity in fonts.listSync())
      if (entity is File &&
          p.basename(entity.path).startsWith('Roboto-') &&
          entity.path.endsWith('.ttf'))
        entity.path,
  ]..sort();
  if (roboto.isEmpty) return null;
  final icons = p.join(fonts.path, 'MaterialIcons-Regular.otf');
  return <String, List<String>>{
    'Roboto': roboto,
    'CupertinoSystemText': roboto,
    'CupertinoSystemDisplay': roboto,
    if (File(icons).existsSync()) 'MaterialIcons': [icons],
  };
}

/// Why a surface whose test wrote no image has none.
String _testFailure(String name, Directory root, Directory project) =>
    'it did not render; run `flutter test ${_testPath(name)}` in '
    '${p.relative(project.path, from: root.path)} to see why';

String _buildFailure(String reason) => switch (reason) {
  'project_identity' => 'pubspec.yaml does not name the app',
  'output_root' =>
    'restage_config.yaml names an output root that is not usable',
  'dependencies_unresolved' =>
    "the app's dependencies are not resolved; run `flutter pub get`",
  _ => 'the image project could not be written',
};
