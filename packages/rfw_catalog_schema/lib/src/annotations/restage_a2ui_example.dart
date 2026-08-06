import 'package:meta/meta.dart';
import 'package:meta/meta_meta.dart';

/// Associates an exact, developer-authored GenUI component graph with a
/// customer `@RestageWidget`.
///
/// The [asset] is a package-relative JSON sidecar under `lib/`. Multiple
/// examples may annotate the same widget class; [name] must be unique within
/// that widget's catalog item.
@immutable
@Target({TargetKind.classType})
final class RestageA2uiExample {
  /// Creates a canonical A2UI example reference.
  const RestageA2uiExample({required this.name, required this.asset});

  /// Developer-authored display name for this example.
  final String name;

  /// Package-relative `lib/` path to the exact JSON component array.
  final String asset;
}
