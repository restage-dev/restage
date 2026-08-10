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

  /// The resolved catalog name.
  ///
  /// This defaults to the annotated Dart class name and reflects an explicit
  /// catalog-name override when one is supplied.
  final String name;

  /// Builder invoked to materialize the widget at render time.
  final LocalWidgetBuilder builder;
}
