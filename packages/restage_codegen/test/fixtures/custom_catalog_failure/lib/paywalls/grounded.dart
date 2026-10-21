import 'package:apps_examples/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/grounded.restage.g.dart';

@Paywall()
class Grounded extends StatelessWidget {
  const Grounded({super.key});

  @override
  Widget build(BuildContext context) => AppGround(
        child: TextButton(
          onPressed: paywallEvent('close'),
          child: const Text('Not now'),
        ),
      );
}
