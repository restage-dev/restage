import 'package:meta/meta.dart';

/// Names an editor-side preview builder for a property's value.
///
/// Used when a customer wants to render a richer preview for a custom
/// property type (e.g. an `AcmeColor` value that combines a hex string
/// with a tonal-step indicator). The [builder] string identifies a
/// registered preview builder in the editor runtime.
///
/// ```dart
/// @RestagePropertyPreview(builder: 'acmeColorPreviewBuilder')
/// @RestageProperty(description: 'Brand color value.')
/// final Color color;
/// ```
@immutable
final class RestagePropertyPreview {
  /// Const constructor.
  const RestagePropertyPreview({required this.builder});

  /// Identifier for a preview builder registered in the editor runtime.
  final String builder;
}
