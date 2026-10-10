// @dart=3.13
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import '../widgets/plan_badge.dart';

part 'restage.generated/premium.restage.g.dart';

@Paywall()
final class PremiumPaywall extends StatefulWidget {
  const PremiumPaywall({super.key});

  @override
  State<PremiumPaywall> createState() => _PremiumPaywallState();
}

final class _PremiumPaywallState extends State<PremiumPaywall> {
  bool wide = false;

  @override
  Widget build(BuildContext context) {
    final PlanNote note = .cancel();
    return Container(
      alignment: .center,
      padding: const .all(4),
      margin: .symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const .fromARGB(255, 1, 2, 3),
        borderRadius: .circular(4),
      ),
      child: Column(
        mainAxisAlignment: wide ? .start : .center,
        crossAxisAlignment: .stretch,
        children: [
          Text(
            'Upgrade',
            textAlign: .center,
            style: TextStyle(fontWeight: .bold),
          ),
          PlanBadge(label: 'Plus'),
          const PlanBadge(label: 'Max'),
          note,
        ],
      ),
    );
  }
}

@RestageWidget(
  name: 'PlanNote',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A plan note.',
)
final class PlanNote extends StatelessWidget {
  const PlanNote({super.key, required this.text});

  /// The note text.
  final String text;

  static PlanNote cancel() => const PlanNote(text: 'Cancel anytime');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .symmetric(horizontal: 6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black),
          borderRadius: const .all(.circular(8)),
        ),
        child: Text(
          text,
          textAlign: .center,
          style: TextStyle(fontWeight: .w600),
        ),
      ),
    );
  }
}
