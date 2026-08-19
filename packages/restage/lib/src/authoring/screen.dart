import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show Surface, kBaselineCatalogVersion;

/// Marks a Flutter widget class as a Restage screen.
///
/// A screen without [surface] is reusable inside a flow and inherits the
/// flow's category. A categorized screen is independently published.
@immutable
final class Screen {
  /// Creates a screen annotation.
  const Screen({
    this.id,
    this.surface,
    this.version = 1,
    this.minClient = kBaselineCatalogVersion,
  });

  /// Optional stable source identity.
  final String? id;

  /// Product category for an independently published screen.
  final Surface? surface;

  /// App-pinned screen contract version.
  final int version;

  /// Minimum catalog version required to render the screen.
  final int minClient;
}
