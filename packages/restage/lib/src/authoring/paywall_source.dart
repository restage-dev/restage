import 'package:meta/meta.dart';

/// Marks a class as a paywall source for `restage_codegen` to consume.
///
/// Authored classes extend `StatelessWidget` and use `paywallEvent` /
/// `paywallPurchase` / `paywallPriceFor` helpers in their `build()` method.
/// The codegen walks annotated classes at build time and emits matching
/// `.rfwtxt` + `.rfw` artifacts.
///
/// Example:
/// ```dart
/// @PaywallSource(id: 'pro_upgrade')
/// class ProUpgradePaywall extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) => Scaffold(
///     body: Center(child: ElevatedButton(
///       onPressed: paywallPurchase(slot: 'primary'),
///       child: Text('Subscribe'),
///     )),
///   );
/// }
/// ```
@immutable
final class PaywallSource {
  /// Marks the annotated class as a paywall source authored in Dart.
  const PaywallSource({required this.id});

  /// Server-side paywall identifier. Matches `RestagePaywall(id:)`.
  final String id;
}
