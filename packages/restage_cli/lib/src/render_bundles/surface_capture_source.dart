import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';

/// Why one surface has no image source.
final class SurfaceCaptureSourceException implements Exception {
  const SurfaceCaptureSourceException(this.reason);

  /// A clause a reader sees after the surface's id.
  final String reason;

  @override
  String toString() => reason;
}

/// A top-level `Widget name(Widget child)` in the app's `lib/` that every
/// captured surface is drawn inside.
final class SurfaceCaptureWrapper {
  const SurfaceCaptureWrapper._(this.library, this.name);

  /// Reads `lib/<file>.dart#<name>`, checking the file declares the function.
  factory SurfaceCaptureWrapper.parse(
    String spec, {
    required Directory projectRoot,
  }) {
    final separator = spec.lastIndexOf('#');
    final library = p.posix.normalize(
      separator < 0 ? spec : spec.substring(0, separator),
    );
    final name = separator < 0 ? '' : spec.substring(separator + 1);
    if (!p.posix.isWithin('lib', library) ||
        !library.endsWith('.dart') ||
        RegExp(r'^[A-Za-z][\w$]*$').stringMatch(name) != name) {
      throw SurfaceCaptureSourceException(
        'previewWrapper in restage_config.yaml must look like '
        '`lib/preview.dart#wrapPreview`, not `$spec`',
      );
    }
    final source = _read(projectRoot, library);
    if (source == null) {
      throw SurfaceCaptureSourceException(
        'previewWrapper names $library, which does not exist',
      );
    }
    // A top-level `Widget name(Widget child)`, optionally `final`.
    final declared = RegExp(
      r'(^|\n)Widget\s+' +
          RegExp.escape(name) +
          r'\s*\(\s*(final\s+)?Widget\s+[A-Za-z_$][\w$]*\s*,?\s*\)',
    );
    if (!declared.hasMatch(source)) {
      throw SurfaceCaptureSourceException(
        'previewWrapper names `$name`, which $library does not declare as '
        '`Widget $name(Widget child)`',
      );
    }
    return SurfaceCaptureWrapper._(library, name);
  }

  /// The app-relative library, `lib/...dart`.
  final String library;

  /// The function's name.
  final String name;

  /// The `package:` URI of [library] in the app named [appName].
  String importUri(String appName) => _packageUri(library, appName);
}

/// Writes the Dart that builds one pushed surface with sample values for its
/// host data, from the build's capture [plan] for it: a flow's first screen,
/// or the authored class of a screen or paywall.
///
/// The returned library defines `main()`, which hands the builder to the
/// support library's `capture(name, builder)`.
String surfaceCaptureTestSource({
  required String appName,
  required Map<String, Object?>? plan,
  required String name,
  required Map<String, Object?> sample,
  SurfaceCaptureWrapper? wrapper,
  List<String>? placeholders,
}) {
  final wrap = wrapper == null
      ? null
      : (
          import:
              "import '${_packageUri(wrapper.library, appName)}' "
              'as restage_capture_wrap;',
          call: 'restage_capture_wrap.${wrapper.name}',
        );
  if (plan == null) {
    throw const SurfaceCaptureSourceException('its widget was not found');
  }
  if (plan case {
    'kind': 'flow',
    'importUri': final String library,
    'ref': final String ref,
  }) {
    if (ref.startsWith('_')) {
      throw const SurfaceCaptureSourceException(
        'its flow is private to its library',
      );
    }
    return _testLibrary(
      ["import '$library';", ?wrap?.import],
      name,
      'return restage_capture.flowEntry($ref);',
      wrap: wrap?.call,
    );
  }
  final widget = '${plan['name']}';
  final types = _CaptureValues();
  final call = types.construct(plan, sample, widget);
  placeholders?.addAll(types.placeholders);
  return _testLibrary(
    [...types.directives, ?wrap?.import],
    name,
    'return $call;',
    wrap: wrap?.call,
  );
}

/// Whether [schema] declares a value the app's generated widget computes.
bool hostDataHasAppValues(SurfaceScreenHostDataSchema schema) =>
    schema.inputs.entries.any((input) => _appValue(input.key, input.value));

bool _appValue(String name, SurfaceScreenHostDataShape shape) =>
    _appValueKey.hasMatch(name) || _holdsAppValue(shape);

bool _holdsAppValue(SurfaceScreenHostDataShape shape) => switch (shape) {
  SurfaceScreenHostDataNativeBindingShapeV1() => true,
  SurfaceScreenHostDataNullableShapeV1(:final value) => _holdsAppValue(value),
  SurfaceScreenHostDataListShapeV1(:final items) => _holdsAppValue(items),
  SurfaceScreenHostDataMapShapeV1(:final values) => _holdsAppValue(values),
  SurfaceScreenHostDataObjectShapeV1(:final fields) => fields.entries.any(
    (field) => _appValue(field.key, field.value),
  ),
  _ => false,
};

/// Samples ordinary host data and refuses native values requiring an installed host.
Map<String, Object?> sampleSurfaceCaptureContext(
  SurfaceScreenHostDataSchema? schema,
) {
  if (schema == null) return const {};
  if (schema.inputs.values.any(_holdsNativeBinding)) {
    throw const SurfaceCaptureSourceException(
      'its native bindings require an installed host and cannot be captured as JSON',
    );
  }
  return sampleHostContext(schema);
}

bool _holdsNativeBinding(SurfaceScreenHostDataShape shape) => switch (shape) {
  SurfaceScreenHostDataNativeBindingShapeV1() => true,
  SurfaceScreenHostDataNullableShapeV1(:final value) => _holdsNativeBinding(
    value,
  ),
  SurfaceScreenHostDataListShapeV1(:final items) => _holdsNativeBinding(items),
  SurfaceScreenHostDataMapShapeV1(:final values) => _holdsNativeBinding(values),
  SurfaceScreenHostDataObjectShapeV1(:final fields) => fields.values.any(
    _holdsNativeBinding,
  ),
  _ => false,
};

final _appValueKey = RegExp(r'^_h[0-9a-f]{10}$');

/// The expressions [schema]'s app-computed values come from, sorted.
List<String> hostDataAppValueLabels(SurfaceScreenHostDataSchema schema) {
  final labels = <String>{};
  void visit(String name, SurfaceScreenHostDataShape shape) {
    if (_appValueKey.hasMatch(name) ||
        shape is SurfaceScreenHostDataNativeBindingShapeV1) {
      labels.add(shape.label ?? name);
    }
    switch (shape) {
      case SurfaceScreenHostDataNullableShapeV1(:final value):
        visit('', value);
      case SurfaceScreenHostDataListShapeV1(:final items):
        visit('', items);
      case SurfaceScreenHostDataMapShapeV1(:final values):
        visit('', values);
      case SurfaceScreenHostDataObjectShapeV1(:final fields):
        fields.forEach(visit);
      case _:
    }
  }

  schema.inputs.forEach(visit);
  return labels.toList()..sort();
}

/// Writes the Dart that records the render context a surface's generated
/// widget builds with sample inputs, in light and dark, or null when the
/// surface has no values the app computes.
String? surfaceContextTestSource({
  required String appName,
  required SurfacePublicationManifestEntry entry,
  required Map<String, Object?>? plan,
  required String name,
  required Map<String, Object?> sample,
  SurfaceCaptureWrapper? wrapper,
}) {
  final publication = entry.publication;
  final schema = publication.hostDataContract;
  if (schema == null || !hostDataHasAppValues(schema)) return null;
  sampleSurfaceCaptureContext(schema);
  if (plan == null || plan['kind'] != 'object') return null;
  final widget = '${plan['name']}';
  final mount = publication.mountName ?? '${widget}Surface';
  final types = _CaptureValues();
  final call = types.construct(plan, sample, widget);
  final open = call.indexOf('.$widget(');
  if (open < 0) return null;
  final mountCall = call.replaceRange(
    open + 1,
    open + 1 + widget.length,
    mount,
  );
  return _testLibrary(
    [
      ...types.directives,
      if (wrapper != null)
        "import '${_packageUri(wrapper.library, appName)}' "
            'as restage_capture_wrap;',
    ],
    name,
    'return $mountCall;',
    wrap: wrapper == null ? null : 'restage_capture_wrap.${wrapper.name}',
    capture: 'captureContext',
  );
}

/// A capture test: [imports], then `main()` capturing [body] as [name],
/// drawn inside [wrap] when given.
String _testLibrary(
  List<String> imports,
  String name,
  String body, {
  String? wrap,
  String capture = 'capture',
}) =>
    '''
// Generated by `restage surface push`. Rewritten on every push.
// ignore_for_file: type=lint
import 'package:flutter/widgets.dart' as restage_capture_widgets;
import 'restage_capture.dart' as restage_capture;
${imports.join('\n')}

void main() => restage_capture.$capture(${_string(name)}, (
  restage_capture_widgets.BuildContext context,
) {
  $body
}${wrap == null ? '' : ', wrap: $wrap'});
''';

String? _read(Directory projectRoot, String path) {
  final file = File(p.joinAll([projectRoot.path, ...path.split('/')]));
  return file.existsSync() ? file.readAsStringSync() : null;
}

String _packageUri(String packagePath, String appName) {
  if (!packagePath.startsWith('lib/')) {
    throw const SurfaceCaptureSourceException('its library is outside lib/');
  }
  return 'package:$appName/${packagePath.substring(4)}';
}

String _json(Object? value) => switch (value) {
  null => 'null',
  final String text => _string(text),
  final num number => '$number',
  final bool flag => '$flag',
  final List<Object?> items => '[${items.map(_json).join(', ')}]',
  final Map<Object?, Object?> map =>
    '<String, Object?>{${[for (final MapEntry(:key, :value) in map.entries) '${_string('$key')}: ${_json(value)}'].join(', ')}}',
  _ => _string('$value'),
};

String _string(String value) =>
    "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}'";

/// Dart values for the types a capture plan names, with the libraries that
/// declare them imported under their own prefixes.
final class _CaptureValues {
  final Map<String, String> _prefixes = <String, String>{};

  /// The host data fields drawn with a neutral value, as `Widget.field`.
  final List<String> placeholders = <String>[];

  List<String> get directives => [
    for (final MapEntry(key: uri, value: prefix) in _prefixes.entries)
      "import '$uri' as $prefix;",
  ];

  String _prefix(Object? library) => _prefixes.putIfAbsent(
    '$library',
    () => 'restage_capture_type${_prefixes.length}',
  );

  /// A constructor call of the planned class [plan] holding [fields].
  String construct(
    Map<String, Object?> plan,
    Map<Object?, Object?> fields,
    String at,
  ) {
    final name = '${plan['name']}';
    switch (plan['kind']) {
      case 'object':
        break;
      case 'recursive':
        throw _unbuildable(at, name);
      case 'private':
        throw SurfaceCaptureSourceException(
          '${at == name ? 'its widget' : 'its host data type'} `$name` is '
          'private to its library',
        );
      default:
        throw SurfaceCaptureSourceException(
          '${at == name ? 'its widget' : 'its host data type'} $name has no '
          'constructor this can call',
        );
    }
    final prefix = _prefix(plan['importUri']);
    final positional = <String?>[];
    final named = <String>[];
    for (final parameter
        in (plan['parameters']! as List).cast<Map<String, Object?>>()) {
      // A parameter no field holds is drawn without its sample.
      final key = parameter['sampleKey'] as String?;
      final label = '$at.${key ?? parameter['name']}';
      final type = (parameter['type']! as Map).cast<String, Object?>();
      final value = key == null ? null : fields[key];
      final optional = parameter['required'] != true;
      String? argument;
      if (value != null) {
        argument = _literal(type, value, label);
      } else if (optional &&
          (parameter['hasDefault'] == true || type['nullable'] == true)) {
        argument = null;
      } else {
        argument = _literal(type, null, label);
      }
      if (key == null && !placeholders.contains(label)) placeholders.add(label);
      if (parameter['named'] == true) {
        if (argument != null) named.add('${parameter['name']}: $argument');
      } else {
        positional.add(argument);
      }
    }
    // Only trailing optional positionals can be left out.
    while (positional.isNotEmpty && positional.last == null) {
      positional.removeLast();
    }
    if (positional.contains(null)) throw _unbuildable(at, name);
    return '$prefix.$name('
        '${[...positional, ...named].join(', ')})';
  }

  /// A Dart expression of [type] holding [value], or a neutral value of it
  /// when [value] is null.
  String _literal(Map<String, Object?> type, Object? value, String at) {
    if (value == null) {
      if (type['nullable'] == true) return 'null';
      final placeholder = _placeholder(type, at);
      placeholders.add(at);
      return placeholder;
    }
    switch (type['kind']) {
      case 'string':
        return _string('$value');
      case 'int':
        if (value is num) return '${value.round()}';
      case 'double':
        if (value is num) return '${value.toDouble()}';
      case 'num':
        if (value is num) return '$value';
      case 'bool':
        if (value is bool) return '$value';
      case 'json':
        return _json(value);
      case 'list' || 'set':
        if (value is List) {
          final item = (type['item']! as Map).cast<String, Object?>();
          final items = [
            for (final element in value) _literal(item, element, '$at[]'),
          ].join(', ');
          return type['kind'] == 'list' ? '[$items]' : '{$items}';
        }
      case 'map':
        if (value is Map) {
          final entry = (type['value']! as Map).cast<String, Object?>();
          return '{${[for (final MapEntry(:key, value: item) in value.entries) '${_string('$key')}: ${_literal(entry, item, '$at.$key')}'].join(', ')}}';
        }
      case 'enum':
        if (value is String) {
          final values = (type['values']! as List).cast<String>();
          return '${_prefix(type['importUri'])}.${type['name']}.'
              '${values.contains(value) ? value : values.first}';
        }
      case 'object':
        if (value is Map) return construct(type, value, at);
      case 'private':
        return construct(type, const <String, Object?>{}, at);
    }
    throw SurfaceCaptureSourceException(
      'its host data `$at` does not match its sample',
    );
  }

  /// A value of [type] for an input with no sample: an enum's first value, a
  /// class built from its defaults (two of them in a list), the epoch, a zero
  /// duration, black, or empty.
  String _placeholder(Map<String, Object?> type, String at) {
    switch (type['kind']) {
      case 'string':
        return "''";
      case 'int' || 'num':
        return '0';
      case 'double':
        return '0.0';
      case 'bool':
        return 'false';
      case 'list':
        final item = (type['item']! as Map).cast<String, Object?>();
        if (item['nullable'] != true &&
            const {'object', 'enum'}.contains(item['kind'])) {
          try {
            final sample = _placeholder(item, '$at[]');
            return '[$sample, $sample]';
          } on SurfaceCaptureSourceException {
            // An item this cannot build leaves the list empty.
          }
        }
        return 'const []';
      case 'map' || 'set':
        return 'const {}';
      case 'enum':
        final values = (type['values']! as List).cast<String>();
        if (values.isNotEmpty) {
          return '${_prefix(type['importUri'])}.${type['name']}.${values.first}';
        }
      case 'value':
        switch (type['name']) {
          case 'DateTime':
            return 'DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)';
          case 'Duration':
            return 'Duration.zero';
          case 'Color':
            return 'const restage_capture_widgets.Color(0xFF000000)';
        }
      case 'object' || 'unconstructible' || 'private':
        return construct(type, const <String, Object?>{}, at);
      case 'json':
        throw _unbuildable(at, 'Object');
    }
    throw _unbuildable(at, '${type['display'] ?? type['name']}');
  }

  SurfaceCaptureSourceException _unbuildable(String at, String type) =>
      SurfaceCaptureSourceException(
        "its host data `$at` has a type the preview can't build a sample of "
        '(`$type`). Give the parameter a default value to draw the image',
      );
}

/// The support library every capture test imports.
String surfaceCaptureSupportSource({
  required double width,
  required double height,
  required Map<String, List<String>> fontFiles,
  required bool readsPaywallContext,
}) =>
    '''
// Generated by `restage surface push`. Rewritten on every push.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
${readsPaywallContext ? "import 'package:restage/render_support.dart' show paywallHostContext;\n" : ''}import 'package:restage/restage.dart'
    show RestagePaywall, RestageScreen, SurfaceFlowRef;
import 'package:restage_shared/restage_shared.dart' show ScreenFlowState;

const _fontFiles = <String, List<String>>${jsonEncode(fontFiles)};

/// Renders [builder] headless, inside [wrap] when given, and writes its PNG
/// as image [name], or the error that stopped it beside where it would be.
void capture(
  String name,
  WidgetBuilder builder, {
  Widget Function(Widget child)? wrap,
}) {
  setUpAll(_loadFonts);
  testWidgets(name, (tester) async {
    try {
      await _capture(tester, name, builder, wrap);
    } catch (error) {
      File('images/\$name.error.txt').writeAsStringSync('\$error');
      rethrow;
    }
  });
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  WidgetBuilder builder,
  Widget Function(Widget child)? wrap,
) async {
  tester.view
    ..physicalSize = const Size($width, $height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final boundary = GlobalKey();
  final surface = Builder(builder: builder);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: wrap == null ? surface : wrap(surface),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 500));
  final error = tester.takeException();
  if (error != null) throw error;
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final png = await tester.runAsync(() async {
    final image = await render.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  });
  File('images/\$name.png').writeAsBytesSync(png!);
}

/// Records the render context the generated widget [builder] returns builds,
/// in light and in dark, as [name]'s context file.
void captureContext(
  String name,
  WidgetBuilder builder, {
  Widget Function(Widget child)? wrap,
}) {
  testWidgets('\$name context', (tester) async {
    final contexts = <String, Object?>{};
    for (final brightness in Brightness.values) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      final mount = Builder(builder: builder);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(),
          darkTheme: ThemeData(brightness: Brightness.dark),
          home: wrap == null ? mount : wrap(mount),
        ),
      );
      // The surface may fail to resolve here; only its context is read.
      tester.takeException();
      final surface = tester
          .widgetList(
            find.byWidgetPredicate(
              (widget) => widget is RestageScreen || widget is RestagePaywall,
            ),
          )
          .first;
      contexts[brightness.name] = (surface is RestagePaywall
              ? ${readsPaywallContext ? 'paywallHostContext(surface)' : 'null'}
              : (surface as RestageScreen).context) ??
          const <String, Object?>{};
    }
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    File('images/\$name.context.json').writeAsStringSync(jsonEncode(contexts));
  });
}

/// The first screen of [flow], as its compiled graph builds it.
Widget flowEntry(SurfaceFlowRef<Object?> flow) {
  final compiled = flow.compiled;
  if (compiled == null) throw StateError('The flow has no compiled graph.');
  final document = compiled.document;
  final initial = document.states[document.initial];
  if (initial is! ScreenFlowState) {
    throw StateError('The flow does not start on a screen.');
  }
  return compiled.screens[initial.screen]!();
}

Future<void> _loadFonts() async {
  final manifest = jsonDecode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<Object?>;
  for (final family in manifest.cast<Map<String, Object?>>()) {
    final loader = FontLoader(family['family']! as String);
    for (final font in (family['fonts']! as List<Object?>)
        .cast<Map<String, Object?>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await loader.load();
  }
  for (final MapEntry(key: family, value: files) in _fontFiles.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }
}
''';
