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
    final PlanNote note = PlanNote.cancel();
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 1, 2, 3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisAlignment: wide
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Upgrade',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
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
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
