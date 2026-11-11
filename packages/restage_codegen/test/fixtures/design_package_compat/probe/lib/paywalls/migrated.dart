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
            onPressed: context.surfaceEvent(_Events.go),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

abstract final class _Events {
  static const go = SurfaceEvent<void>('go');
}
