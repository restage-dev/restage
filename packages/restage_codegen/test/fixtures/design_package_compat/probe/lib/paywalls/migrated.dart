import 'package:material_ui/material_ui.dart';
import 'package:restage/restage.dart';

@Paywall()
class MigratedPaywall extends StatelessWidget {
  const MigratedPaywall({super.key});

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
