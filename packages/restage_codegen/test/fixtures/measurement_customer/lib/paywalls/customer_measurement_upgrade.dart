import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/customer_measurement_upgrade.restage.g.dart';

@Paywall(id: 'customer_measurement_upgrade')
final class CustomerMeasurementUpgrade extends StatelessWidget {
  const CustomerMeasurementUpgrade({super.key});

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: paywallPurchase(slot: 'primary'),
        child: const Text('Upgrade'),
      );
}
