import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';

/// A2UI-specific configuration for a customer widget catalog entry.
///
/// Use the unnamed constructor to set multiple values together, or compose
/// named constructors when each value is clearer as a separate annotation.
@immutable
@Target({TargetKind.classType, TargetKind.field})
final class Config {
  /// Creates an A2UI configuration overlay.
  const Config({
    this.enabled,
    this.usage,
    this.writeBackValues,
    this.writeBackValue,
  });

  /// Controls whether the annotated customer widget participates in A2UI emit.
  // ignore: avoid_positional_boolean_parameters
  const Config.enabled(bool enabled) : this(enabled: enabled);

  /// Configures producer-facing usage guidance for the annotated widget.
  const Config.usage(String usage) : this(usage: usage);

  /// Configures callback-to-value write-back pairings for a widget.
  const Config.writeBackValues(Map<String, String> writeBackValues)
      : this(writeBackValues: writeBackValues);

  /// Configures the value property paired with an annotated callback field.
  const Config.writeBackValue(String writeBackValue)
      : this(writeBackValue: writeBackValue);

  /// Whether this customer widget participates in A2UI emit.
  ///
  /// `null` keeps the default enabled behavior. This key is valid only on an
  /// `@RestageWidget` class.
  final bool? enabled;

  /// Producer-facing guidance describing when to use the widget.
  final String? usage;

  /// Callback property name to value property name pairings.
  final Map<String, String>? writeBackValues;

  /// Value property paired with an annotated callback field.
  final String? writeBackValue;
}
