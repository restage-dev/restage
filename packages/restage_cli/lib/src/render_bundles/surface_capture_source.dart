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

const _unrecognized = SurfaceCaptureSourceException(
  'its generated widget was not recognized',
);
const _unfillable = SurfaceCaptureSourceException(
  'its host data has a type this cannot fill',
);

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
}

/// Writes the Dart that builds one pushed surface with sample values for its
/// host data: a flow's first screen, or the authored class of a screen or
/// paywall.
///
/// The returned library defines `main()`, which hands the builder to the
/// support library's `capture(name, builder)`.
String surfaceCaptureTestSource({
  required Directory projectRoot,
  required String appName,
  required SurfacePublicationManifestEntry entry,
  required String name,
  required Map<String, Object?> sample,
  SurfaceCaptureWrapper? wrapper,
}) {
  final wrap = wrapper == null
      ? null
      : (
          import:
              "import '${_packageUri(wrapper.library, appName)}' "
              'as restage_capture_wrap;',
          call: 'restage_capture_wrap.${wrapper.name}',
        );
  final publication = entry.publication;
  final sources = _libSources(projectRoot, entry.sources);
  if (publication.mountName case final mount?) {
    final flow = _flowRef(projectRoot, sources, mount);
    if (flow != null) {
      if (flow.ref.startsWith('_')) {
        throw const SurfaceCaptureSourceException(
          'its flow is private to its library',
        );
      }
      return _testLibrary(
        ["import '${_packageUri(flow.library, appName)}';", ?wrap?.import],
        name,
        'return restage_capture.flowEntry(${flow.ref});',
        wrap: wrap?.call,
      );
    }
  }
  final widget = _authoredClass(
    sources,
    publication.slug,
    paywall: publication.surface == Surface.paywall,
  );
  if (widget == null) {
    throw const SurfaceCaptureSourceException('its widget was not found');
  }
  final types = _TypeImports(projectRoot, appName);
  final call = types.construct(widget, sample, widget);
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
  SurfaceScreenHostDataNullableShapeV1(:final value) => _holdsAppValue(value),
  SurfaceScreenHostDataListShapeV1(:final items) => _holdsAppValue(items),
  SurfaceScreenHostDataMapShapeV1(:final values) => _holdsAppValue(values),
  SurfaceScreenHostDataObjectShapeV1(:final fields) => fields.entries.any(
    (field) => _appValue(field.key, field.value),
  ),
  _ => false,
};

final _appValueKey = RegExp(r'^_h[0-9a-f]{10}$');

/// The expressions [schema]'s app-computed values come from, sorted.
List<String> hostDataAppValueLabels(SurfaceScreenHostDataSchema schema) {
  final labels = <String>{};
  void visit(String name, SurfaceScreenHostDataShape shape) {
    if (_appValueKey.hasMatch(name)) labels.add(shape.label ?? name);
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
  required Directory projectRoot,
  required String appName,
  required SurfacePublicationManifestEntry entry,
  required String name,
  required Map<String, Object?> sample,
  SurfaceCaptureWrapper? wrapper,
}) {
  final publication = entry.publication;
  final schema = publication.hostDataContract;
  if (schema == null || !hostDataHasAppValues(schema)) return null;
  final sources = _libSources(projectRoot, entry.sources);
  final widget = _authoredClass(
    sources,
    publication.slug,
    paywall: publication.surface == Surface.paywall,
  );
  if (widget == null) return null;
  final mount = publication.mountName ?? '${widget}Surface';
  final types = _TypeImports(projectRoot, appName);
  final call = types.construct(widget, sample, widget);
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

typedef _Source = ({String path, String text});

/// The app's own Dart files among [sources].
List<_Source> _libSources(Directory projectRoot, List<String> sources) => [
  for (final source in sources)
    if (source.startsWith('lib/') && source.endsWith('.dart'))
      if (_read(projectRoot, source) case final text?)
        (path: source, text: text),
];

String? _read(Directory projectRoot, String path) {
  final file = File(p.joinAll([projectRoot.path, ...path.split('/')]));
  return file.existsSync() ? file.readAsStringSync() : null;
}

/// The flow ref the generated flow widget [mount] is built on, and the
/// library whose generated part declares it, or null when [mount] is not a
/// flow.
({String library, String ref})? _flowRef(
  Directory projectRoot,
  List<_Source> sources,
  String mount,
) {
  final declaration = RegExp(
    r'\bclass\s+' + RegExp.escape(mount) + r'\b[^{]*\bRestageFlowGraph\b',
  );
  for (final source in sources) {
    for (final match in _partDirective.allMatches(source.text)) {
      final uri = match.group(2)!;
      if (!uri.endsWith('.restage.g.dart')) continue;
      final part = _read(
        projectRoot,
        p.posix.normalize(p.posix.join(p.posix.dirname(source.path), uri)),
      );
      final header = part == null ? null : declaration.firstMatch(part);
      if (header == null) continue;
      final flow = RegExp(
        r'\bsuper\s*\(\s*flow:\s*([A-Za-z_$][\w$]*)',
      ).firstMatch(part!.substring(header.end));
      if (flow == null) throw _unrecognized;
      return (library: source.path, ref: flow.group(1)!);
    }
  }
  return null;
}

/// The class annotated as the surface [slug]: by its id, or, with no id, by
/// the file named after it. A paywall is annotated `@Paywall` or
/// `@PaywallSource`; any other surface is a `@Screen`.
String? _authoredClass(
  List<_Source> sources,
  String slug, {
  required bool paywall,
}) {
  final byId = RegExp(r'''\bid:\s*(['"])''' + RegExp.escape(slug) + r'\1');
  final annotated = paywall ? _annotatedPaywall : _annotatedScreen;
  for (final source in sources) {
    final named = p.posix.basenameWithoutExtension(source.path) == slug;
    for (final match in annotated.allMatches(source.text)) {
      final arguments = match.group(1) ?? '';
      final implicit = !arguments.contains(RegExp(r'\bid:'));
      if (byId.hasMatch(arguments) || (named && implicit)) {
        return match.group(2);
      }
    }
  }
  return null;
}

/// A surface annotation of [kinds], then the public class it annotates.
RegExp _annotation(String kinds) => RegExp(
  '@(?:$kinds)'
  r'\b(\([^;{]*?\))?\s*'
  r'(?:///[^\n]*\n\s*)*(?:(?:final|base)\s+)*class\s+([A-Z][\w$]*)',
);

final _annotatedPaywall = _annotation('Paywall|PaywallSource');
final _annotatedScreen = _annotation('Screen');

final _partDirective = RegExp(r'''\bpart\s+(['"])([^'"]+)\1\s*;''');

String _packageUri(String packagePath, String appName) {
  if (!packagePath.startsWith('lib/')) {
    throw const SurfaceCaptureSourceException('its library is outside lib/');
  }
  return 'package:$appName/${packagePath.substring(4)}';
}

const _opening = {'(': ')', '[': ']', '{': '}'};

/// The index of the first character of [stop] at the nesting depth of
/// [start], past strings, comments and bracketed groups, or -1.
int _scan(String source, int start, Set<String> stop) {
  var index = start;
  while (index < source.length) {
    final skipped = _skipLiteral(source, index);
    if (skipped != index) {
      index = skipped;
      continue;
    }
    final char = source[index];
    if (stop.contains(char)) return index;
    if (_opening[char] case final closing?) {
      final end = _scan(source, index + 1, {closing});
      if (end < 0) return -1;
      index = end + 1;
      continue;
    }
    index++;
  }
  return -1;
}

/// The index of the bracket closing the one at [open].
int _close(String source, int open) {
  final end = _scan(source, open + 1, {_opening[source[open]]!});
  if (end < 0) throw _unrecognized;
  return end;
}

/// [source] split at its top-level commas, type arguments counted as
/// nesting.
List<String> _split(String source) {
  final parts = <String>[];
  var start = 0;
  var index = 0;
  var depth = 0;
  while (true) {
    final next = _scan(source, index, const {',', '<', '>'});
    if (next < 0) return parts..add(source.substring(start));
    switch (source[next]) {
      case '<':
        depth++;
      case '>':
        depth--;
      case _ when depth == 0:
        parts.add(source.substring(start, next));
        start = next + 1;
    }
    index = next + 1;
  }
}

/// Past the string or comment starting at [index], or [index] itself.
int _skipLiteral(String source, int index) {
  if (source.startsWith('//', index)) {
    final end = source.indexOf('\n', index);
    return end < 0 ? source.length : end + 1;
  }
  if (source.startsWith('/*', index)) {
    final end = source.indexOf('*/', index + 2);
    return end < 0 ? source.length : end + 2;
  }
  var start = index;
  final raw =
      source[index] == 'r' &&
      index + 1 < source.length &&
      (source[index + 1] == "'" || source[index + 1] == '"') &&
      (index == 0 || !RegExp(r'[\w$]').hasMatch(source[index - 1]));
  if (raw) start++;
  final quote = source[start];
  if (quote != "'" && quote != '"') return index;
  final triple = source.startsWith('$quote$quote$quote', start);
  final delimiter = triple ? '$quote$quote$quote' : quote;
  var cursor = start + delimiter.length;
  while (cursor < source.length) {
    if (!raw && source[cursor] == r'\') {
      cursor += 2;
      continue;
    }
    if (!raw && source.startsWith(r'${', cursor)) {
      cursor = _close(source, cursor + 1) + 1;
      continue;
    }
    if (source.startsWith(delimiter, cursor)) return cursor + delimiter.length;
    cursor++;
  }
  return source.length;
}

/// A parsed type annotation: `prefix.Name<Arguments>?`.
final class _DartType {
  _DartType(this.name, this.arguments, {required this.nullable});

  final String name;
  final List<_DartType> arguments;
  final bool nullable;

  /// The name without an import prefix.
  String get baseName => name.split('.').last;

  static _DartType parse(String source) {
    final parser = _TypeParser(source.replaceAll(RegExp(r'\s+'), ''));
    final type = parser.type();
    if (parser.index != parser.source.length) {
      throw _unfillable;
    }
    return type;
  }
}

final class _TypeParser {
  _TypeParser(this.source);

  final String source;
  int index = 0;

  _DartType type() {
    final name = RegExp(
      r'[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)?',
    ).matchAsPrefix(source, index);
    if (name == null) {
      throw _unfillable;
    }
    index = name.end;
    final arguments = <_DartType>[];
    if (index < source.length && source[index] == '<') {
      index++;
      arguments.add(type());
      while (index < source.length && source[index] == ',') {
        index++;
        arguments.add(type());
      }
      if (index >= source.length || source[index] != '>') throw _unfillable;
      index++;
    }
    final nullable = index < source.length && source[index] == '?';
    if (nullable) index++;
    return _DartType(name.group(0)!, arguments, nullable: nullable);
  }
}

/// A Dart expression of [type] holding [value].
String _literal(_DartType type, Object? value, _TypeImports types, String at) {
  if (value == null) {
    if (type.nullable || type.name == 'dynamic') return 'null';
    throw SurfaceCaptureSourceException('its host data `$at` has no sample');
  }
  switch (type.name) {
    case 'String':
      return _string('$value');
    case 'int':
      if (value is num) return '${value.round()}';
    case 'double':
      if (value is num) return '${value.toDouble()}';
    case 'num':
      if (value is num) return '$value';
    case 'bool':
      if (value is bool) return '$value';
    case 'Object' || 'dynamic':
      return _json(value);
    case 'List':
      if (value is List) {
        final element = type.arguments.isEmpty ? null : type.arguments.single;
        return '[${[for (final item in value) element == null ? _json(item) : _literal(element, item, types, '$at[]')].join(', ')}]';
      }
    case 'Map':
      if (value is Map) {
        final element = type.arguments.length == 2 ? type.arguments[1] : null;
        return '{${[for (final MapEntry(:key, value: item) in value.entries) '${_string('$key')}: ${element == null ? _json(item) : _literal(element, item, types, '$at.$key')}'].join(', ')}}';
      }
    default:
      if (value is Map) return types.construct(type.baseName, value, at);
  }
  throw SurfaceCaptureSourceException(
    'its host data `$at` does not match its sample',
  );
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

/// Plain data classes named by host data, found in the app's `lib` and
/// imported under their own prefixes.
final class _TypeImports {
  _TypeImports(this.projectRoot, this.appName);

  final Directory projectRoot;
  final String appName;
  final Map<String, String> _prefixes = <String, String>{};
  List<({String path, String source})>? _files;

  List<String> get directives => [
    for (final MapEntry(key: uri, value: prefix) in _prefixes.entries)
      "import '$uri' as $prefix;",
  ];

  /// A constructor call of the plain class [name] holding [fields].
  String construct(String name, Map<Object?, Object?> fields, String at) {
    final subject = at == name
        ? 'its widget $name'
        : 'its host data type $name';
    final declared = _declaration(name);
    if (declared == null) {
      throw SurfaceCaptureSourceException('$subject is not declared in lib/');
    }
    final prefix = _prefixes.putIfAbsent(
      _packageUri(declared.library, appName),
      () => 'restage_capture_type${_prefixes.length}',
    );
    final body = declared.body;
    final constructor = RegExp(
      r'(?<![\w$.])' + RegExp.escape(name) + r'\s*\(',
    ).firstMatch(body);
    if (constructor == null) {
      throw SurfaceCaptureSourceException(
        '$subject has no constructor this can call',
      );
    }
    final open = constructor.end - 1;
    final parameters = body.substring(open + 1, _close(body, open));
    final positional = <String>[];
    final named = <String>[];
    // Required positional parameters, then an optional `[...]` or `{...}`.
    final optional = _scan(parameters, 0, const {'[', '{'});
    final groups = [
      (
        parameters: optional < 0
            ? parameters
            : parameters.substring(0, optional),
        named: false,
      ),
      if (optional >= 0)
        (
          parameters: parameters.substring(
            optional + 1,
            _close(parameters, optional),
          ),
          named: parameters[optional] == '{',
        ),
    ];
    for (final group in groups) {
      for (var raw in _split(group.parameters)) {
        raw = raw.trim();
        if (raw.isEmpty || raw.startsWith('super.')) continue;
        final formal = RegExp(r'\bthis\.([A-Za-z_$][\w$]*)').firstMatch(raw);
        if (formal == null) {
          throw SurfaceCaptureSourceException(
            '$subject has no constructor this can call',
          );
        }
        final field = formal.group(1)!;
        final type = RegExp(
          r'\bfinal\s+([^;=]+?)\s+' + RegExp.escape(field) + r'\s*;',
        ).firstMatch(body)?.group(1);
        if (type == null) {
          throw SurfaceCaptureSourceException(
            '$subject has no constructor this can call',
          );
        }
        if (!fields.containsKey(field) && raw.contains('=')) continue;
        final value = _literal(
          _DartType.parse(type),
          fields[field],
          this,
          '$at.$field',
        );
        if (group.named) {
          named.add('$field: $value');
        } else {
          positional.add(value);
        }
      }
    }
    return '$prefix.$name(${[...positional, ...named].join(', ')})';
  }

  /// The library declaring [name] and the class body, or null.
  ({String library, String body})? _declaration(String name) {
    final files = _files ??= _libFiles();
    final pattern = RegExp(r'\bclass\s+' + RegExp.escape(name) + r'\b');
    for (final file in files) {
      final match = pattern.firstMatch(file.source);
      if (match == null) continue;
      final open = file.source.indexOf('{', match.end);
      if (open < 0) continue;
      final partOf = RegExp(
        r'''\bpart\s+of\s+(['"])([^'"]+)\1''',
      ).firstMatch(file.source);
      final library = partOf == null
          ? file.path
          : p.posix.normalize(
              p.posix.join(p.posix.dirname(file.path), partOf.group(2)),
            );
      return (
        library: library,
        body: file.source.substring(open, _close(file.source, open) + 1),
      );
    }
    return null;
  }

  List<({String path, String source})> _libFiles() {
    final lib = Directory(p.join(projectRoot.path, 'lib'));
    if (!lib.existsSync()) return const [];
    return [
      for (final entity in lib.listSync(recursive: true, followLinks: false))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart'))
          (
            path: p.posix.joinAll(
              p.split(p.relative(entity.path, from: projectRoot.path)),
            ),
            source: entity.readAsStringSync(),
          ),
    ]..sort((left, right) => left.path.compareTo(right.path));
  }
}

/// The support library every capture test imports.
String surfaceCaptureSupportSource({
  required double width,
  required double height,
  required Map<String, List<String>> fontFiles,
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
import 'package:restage/restage.dart'
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
      contexts[brightness.name] =
          (surface as dynamic).context ?? const <String, Object?>{};
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
