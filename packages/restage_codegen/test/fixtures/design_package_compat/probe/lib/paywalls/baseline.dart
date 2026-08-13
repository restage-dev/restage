import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall()
class BaselinePaywall extends StatelessWidget {
  const BaselinePaywall({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: Column(
        children: <Widget>[
          const Text('Go Premium'),
          FilledButton(
            onPressed: paywallEvent('go'),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
