// #docregion minimal-catalog-widget
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A card registered with only the bare Restage marker.
@RestageWidget()
class BareCatalogCard extends StatelessWidget {
  /// Creates a root-level custom-widget catalog card.
  const BareCatalogCard({super.key, this.label = 'Bare catalog card'});

  /// Visible card label.
  final String label;

  @override
  Widget build(BuildContext context) => Card(child: Text(label));
}

// #enddocregion minimal-catalog-widget
