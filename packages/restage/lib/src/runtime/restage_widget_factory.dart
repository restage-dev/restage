import 'package:meta/meta.dart';
import 'package:rfw/rfw.dart' show LocalWidgetBuilder;

/// Factory entry for a single widget contributed to a registered library.
///
/// Passed in lists to [Restage.registerWidgetLibrary]. Generated automatically
/// from `@RestageWidget`-annotated classes; hand-written entries are also
/// supported.
@immutable
final class RestageWidgetFactory {
  /// Const constructor.
  const RestageWidgetFactory({required this.name, required this.builder});

  /// The widget's catalog name (matches the `@RestageWidget(name:)` value).
  final String name;

  /// Builder invoked to materialize the widget at render time.
  final LocalWidgetBuilder builder;
}
