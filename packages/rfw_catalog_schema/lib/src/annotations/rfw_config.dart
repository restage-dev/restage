import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';

/// RFW-specific configuration for a customer widget catalog entry.
///
/// The carrier remains available for future target-local configuration. Event
/// callbacks require no configuration: Restage derives them from the resolved
/// constructor signature and uses the Dart property name as their identity.
@immutable
@Target({TargetKind.classType})
final class Config {
  /// Creates an RFW configuration overlay.
  const Config();
}
