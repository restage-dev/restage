import 'package:flutter/material.dart';
import 'package:restage_material/restage_material.dart';

/// On-device demo for [RestageModalSheet] — the declarative drag-to-dismiss
/// bottom sheet. Tap "See all plans" to slide the sheet up; drag it down past
/// the threshold, or tap the scrim, to dismiss it.
///
/// Demonstrates the tunable open timing/curve and the platform-adaptive
/// presentation: the host screen is passed as the sheet's `underlay`, so on
/// iOS/macOS it scales down and rounds behind the rising sheet (the iOS
/// card-sheet look) while the Material path shows it plain behind a scrim.
///
/// Run on a simulator or device with:
///   flutter run -t lib/main_modal_sheet_demo.dart
///
/// The gallery embeds [ModalSheetDemo] (the home content below) as a tile; this
/// entrypoint wraps the same widget in a [MaterialApp] for a standalone run.
void main() => runApp(const _ModalSheetDemoApp());

class _ModalSheetDemoApp extends StatelessWidget {
  const _ModalSheetDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Modal sheet demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6366F1),
        useMaterial3: true,
      ),
      home: const ModalSheetDemo(),
    );
  }
}

/// The modal-sheet capability demo surface — a host screen with a "See all
/// plans" CTA that raises a declarative [RestageModalSheet]. Mounted full-screen
/// by both the standalone entrypoint and the example gallery.
class ModalSheetDemo extends StatefulWidget {
  /// Creates the modal-sheet demo surface.
  const ModalSheetDemo({super.key});

  @override
  State<ModalSheetDemo> createState() => _ModalSheetDemoState();
}

class _ModalSheetDemoState extends State<ModalSheetDemo> {
  bool _open = false;

  void _show() => setState(() => _open = true);
  void _close() => setState(() => _open = false);

  @override
  Widget build(BuildContext context) {
    // Black behind everything, so the iOS scale-down reveals the void around
    // the receding surface card.
    return Scaffold(
      backgroundColor: Colors.black,
      body: RestageModalSheet(
        open: _open,
        showDragHandle: true,
        // The dev-tunable open feel (defaults are the framework's).
        enterDuration: const Duration(milliseconds: 320),
        enterCurve: Curves.easeOutCubic,
        // The host surface the sheet rises over — owned by the sheet so it can
        // scale down on iOS/macOS (plain on Material).
        underlay: _DemoSurface(onShow: _show),
        onSheetDismissed: _close,
        child: _PlanSheet(onContinue: _close),
      ),
    );
  }
}

class _DemoSurface extends StatelessWidget {
  const _DemoSurface({required this.onShow});

  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Pro', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Everything, unlocked.', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: onShow,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text('See all plans'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSheet extends StatelessWidget {
  const _PlanSheet({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Choose your plan', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          const _PlanRow(
            title: 'Annual',
            price: r'$59.99 / year',
            badge: 'Save 40%',
          ),
          const SizedBox(height: 12),
          const _PlanRow(title: 'Monthly', price: r'$9.99 / month'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onContinue,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Start free trial'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.title, required this.price, this.badge});

  final String title;
  final String price;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              Text(price, style: theme.textTheme.bodyMedium),
            ],
          ),
          const Spacer(),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(badge!, style: theme.textTheme.labelMedium),
            ),
        ],
      ),
    );
  }
}
