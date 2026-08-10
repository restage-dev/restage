// #docregion minimal-catalog-widget
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A root-level customer card using only the ordinary Restage marker.
@RestageWidget()
class BareCatalogCard extends StatelessWidget {
  /// Creates a root-level customer catalog card.
  const BareCatalogCard({super.key, this.label = 'Bare catalog card'});

  /// Visible card label.
  final String label;

  @override
  Widget build(BuildContext context) => Card(child: Text(label));
}

// #enddocregion minimal-catalog-widget
