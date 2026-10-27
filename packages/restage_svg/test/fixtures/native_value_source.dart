import 'dart:collection';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/services.dart' as services;
import 'package:flutter/widgets.dart' as f;
import 'package:flutter_svg/flutter_svg.dart' as svg;
import 'package:http/http.dart' as http;
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage_shared/restage_shared.dart' as s;

part 'native_value_source.g.dart';

const markup =
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><path fill="#ff0000" d="M0 0h10v10H0z"/></svg>';

f.Widget constantImage(f.BuildContext context, f.Widget child) => child;
f.Widget constantError(
  f.BuildContext context,
  Object error,
  StackTrace stack,
) => const f.SizedBox();
const constantTheme = svg.SvgTheme(fontSize: 19);
const constantFilter = f.ColorFilter.mode(
  f.Color(0xff336699),
  f.BlendMode.srcIn,
);

class Recorder {
  final events = <String>[];
  final contexts = <f.BuildContext>[];
  final children = <f.Widget>[];
  final errors = <Object>[];
  final stacks = <StackTrace>[];
  final loaders = <RecordingLoader>[];
  final headers = <Map<String, String>>[];
  final mappers = <svg.ColorMapper>[];
  final themes = <svg.SvgTheme>[];
  final byteBuffers = <Uint8List>[];

  f.Widget image(f.BuildContext context, f.Widget child) {
    events.add('image');
    contexts.add(context);
    children.add(child);
    return child;
  }

  f.Widget error(f.BuildContext context, Object error, StackTrace stack) {
    events.add('error');
    contexts.add(context);
    errors.add(error);
    stacks.add(stack);
    return const f.SizedBox(key: f.ValueKey('native-error'));
  }

  List<int> bytes() {
    events.add('bytes');
    return markup.codeUnits;
  }
}

class RecordingLoader extends svg.BytesLoader {
  RecordingLoader(this.recorder, this.bundle) {
    recorder.events.add('loader');
    recorder.loaders.add(this);
  }
  final Recorder recorder;
  final services.AssetBundle bundle;
  @override
  Future<ByteData> loadBytes(f.BuildContext? context) =>
      svg.SvgAssetLoader('tiny.svg', assetBundle: bundle).loadBytes(context);
}

class RecordingHeaders extends MapBase<String, String> {
  RecordingHeaders(this.recorder) {
    recorder.events.add('headers');
    recorder.headers.add(this);
  }
  final Recorder recorder;
  final _values = <String, String>{'X-Svg': 'staged'};
  @override
  String? operator [](Object? key) => _values[key];
  @override
  void operator []=(String key, String value) {
    _values[key] = value;
  }

  @override
  void clear() => _values.clear();
  @override
  Iterable<String> get keys {
    recorder.events.add('headers:keys');
    return _values.keys;
  }

  @override
  int get length {
    recorder.events.add('headers:length');
    return _values.length;
  }

  @override
  String? remove(Object? key) => _values.remove(key);
}

class RecordingMapper extends svg.ColorMapper {
  RecordingMapper(Recorder recorder) {
    recorder.events.add('mapper');
    recorder.mappers.add(this);
  }
  @override
  f.Color substitute(
    String? id,
    String element,
    String attribute,
    f.Color color,
  ) => const f.Color(0xff00ff00);
}

class RecordingTheme extends svg.SvgTheme {
  RecordingTheme(Recorder recorder) : super(fontSize: 19) {
    recorder.events.add('theme');
    recorder.themes.add(this);
  }
}

class ValueSource extends f.StatelessWidget {
  const ValueSource({
    super.key,
    required this.recorder,
    required this.bundle,
    required this.client,
    required this.loader,
    required this.file,
  });
  final Recorder recorder;
  final services.AssetBundle bundle;
  final http.Client client;
  final svg.BytesLoader loader;
  final io.File file;
  @override
  f.Widget build(f.BuildContext context) => const f.SizedBox();

  f.Widget fresh(f.BuildContext context) => svg.SvgPicture.asset(
    'tiny.svg',
    bundle: bundle,
    imageBuilder: (inner, child) => recorder.image(inner, child),
    errorBuilder: (inner, error, stack) => recorder.error(inner, error, stack),
  );

  f.Widget constants(f.BuildContext context) => svg.SvgPicture.string(
    markup,
    theme: constantTheme,
    colorFilter: constantFilter,
    imageBuilder: constantImage,
    errorBuilder: constantError,
  );

  f.Widget failing(f.BuildContext context) => svg.SvgPicture(
    loader,
    imageBuilder: (inner, child) => recorder.image(inner, child),
    errorBuilder: (inner, error, stack) => recorder.error(inner, error, stack),
  );

  f.Widget staged(f.BuildContext context) => f.LayoutBuilder(
    builder: (inner, constraints) {
      final pictureLoader = RecordingLoader(recorder, bundle);
      final ignoredTheme = RecordingTheme(recorder);
      return svg.SvgPicture(
        pictureLoader,
        theme: ignoredTheme,
        cacheColorFilter: true,
        imageBuilder: (local, child) => recorder.image(local, child),
        errorBuilder: (local, error, stack) =>
            recorder.error(local, error, stack),
      );
    },
  );

  f.Widget stagedHeaders(f.BuildContext context) => f.LayoutBuilder(
    builder: (inner, constraints) {
      final headers = RecordingHeaders(recorder);
      return svg.SvgPicture.network(
        'https://svg.test/picture.svg',
        headers: headers,
        httpClient: client,
        imageBuilder: (local, child) => recorder.image(local, child),
      );
    },
  );

  f.Widget stagedHeaderLiteral(f.BuildContext context) => f.LayoutBuilder(
    builder: (inner, constraints) {
      final headers = <String, String>{'X-Svg': 'literal'};
      final alias = headers;
      return svg.SvgPicture.network(
        'https://svg.test/picture.svg',
        headers: alias,
        httpClient: client,
        imageBuilder: (local, child) {
          recorder.headers.add(headers);
          return recorder.image(local, child);
        },
      );
    },
  );

  f.Widget stagedFile(f.BuildContext context) => f.LayoutBuilder(
    builder: (inner, constraints) {
      final fileLoader = svg.SvgFileLoader(file);
      return svg.SvgPicture(
        fileLoader,
        imageBuilder: (local, child) => recorder.image(local, child),
      );
    },
  );

  f.Widget stagedCallbacks(f.BuildContext context) => f.LayoutBuilder(
    builder: (inner, constraints) {
      var count = 0;
      final svg.SvgImageWidgetBuilder image = (local, child) {
        recorder.events.add('count:$count');
        count++;
        return recorder.image(local, child);
      };
      return svg.SvgPicture.asset(
        'tiny.svg',
        bundle: bundle,
        imageBuilder: image,
      );
    },
  );

  f.Widget stagedValues(f.BuildContext context) => f.LayoutBuilder(
    builder: (inner, constraints) {
      final mapper = RecordingMapper(recorder);
      final theme = RecordingTheme(recorder);
      final bytes = Uint8List.fromList(recorder.bytes());
      return svg.SvgPicture.memory(
        bytes,
        colorMapper: mapper,
        theme: theme,
        imageBuilder: (local, child) {
          recorder.byteBuffers.add(bytes);
          return recorder.image(local, child);
        },
      );
    },
  );

  f.Widget refused(f.BuildContext context) =>
      svg.SvgPicture(RecordingLoader(recorder, bundle));

  f.Widget refusedFileConstruction(f.BuildContext context) => f.LayoutBuilder(
    builder: (inner, constraints) {
      final pathFile = io.File('uninstalled.svg');
      return svg.SvgPicture.file(pathFile);
    },
  );

  f.Widget refusedMapper(f.BuildContext context) =>
      svg.SvgPicture.string(markup, colorMapper: RecordingMapper(recorder));

  f.Widget refusedHeaders(f.BuildContext context) => svg.SvgPicture.network(
    'https://svg.test/picture.svg',
    headers: RecordingHeaders(recorder),
  );

  svg.SvgImageWidgetBuilder get dynamicImage {
    recorder.events.add('getter');
    return (context, child) => recorder.image(context, child);
  }

  f.Widget refusedGetter(f.BuildContext context) =>
      svg.SvgPicture.string(markup, imageBuilder: dynamicImage);
}
