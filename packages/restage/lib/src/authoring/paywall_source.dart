import 'package:meta/meta.dart';

/// Marks a Flutter widget class as a specialized paywall source.
///
/// A paywall is independently published under [Surface.paywall] and may also
/// appear inside a flow of any supported category. Its specialized runtime
/// behavior is selected by source kind, not by the containing flow's category.
@immutable
final class Paywall {
  /// Creates a paywall annotation.
  const Paywall({this.id});

  /// Optional stable source identity.
  final String? id;
}

/// Legacy source annotation for a specialized paywall.
///
/// New source should use [Paywall]. This annotation retains its legacy
/// required-ID shape while the generator continues to support it.
@Deprecated('Use @Paywall(...) instead.')
@immutable
final class PaywallSource {
  /// Creates a legacy paywall source annotation.
  const PaywallSource({required this.id});

  /// Stable paywall identifier.
  final String id;
}
