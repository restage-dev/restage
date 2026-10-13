// #docregion minimal-catalog-widget
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A card registered with only `@RestageWidget()`.
@RestageWidget()
class BareCatalogCard extends StatelessWidget {
  /// Creates the card.
  const BareCatalogCard({super.key, this.label = 'Bare catalog card'});

  /// Visible card label.
  final String label;

  @override
  Widget build(BuildContext context) => Card(child: Text(label));
}

// #enddocregion minimal-catalog-widget
