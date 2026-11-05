import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/guarded_features.restage.g.dart';

/// An offer whose features the paywall lists.
final class GuardedOffer {
  /// Creates an offer.
  const GuardedOffer(this.features);

  /// The features to list.
  final List<String> features;
}

/// A paywall that lists an optional offer's features and a title's parts,
/// each only when present.
@Paywall(id: 'guarded_features')
final class GuardedFeatures extends StatelessWidget {
  /// Creates the paywall.
  const GuardedFeatures({super.key, this.offer, this.title});

  /// The offer, when there is one.
  final GuardedOffer? offer;

  /// A comma-separated title, when there is one.
  final String? title;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Features'),
        if (offer != null)
          for (final feature in offer!.features) Text(feature)
        else
          const Text('No offer'),
        if (title != null)
          for (final part in title!.split(',')) Text(part)
        else
          const Text('No title'),
      ]);
}
