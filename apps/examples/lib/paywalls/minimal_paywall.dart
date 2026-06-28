import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// The smallest real plan-select paywall — a copy-me starter.
///
/// A `@PaywallSource` is just a `StatefulWidget` written in ordinary Flutter.
/// The selected plan lives in plain `State` (`annualSelected`); tapping a row
/// calls `setState`; the CTA buys whatever is selected via
/// `paywallPurchase(slot:)`. Prices come from the host app's configured
/// products via `paywallPriceFor(slot:)`.
///
/// It reads the ambient `ColorScheme` (no hard-coded palette), so it repaints
/// with the app theme — flip the gallery's light/dark toggle to see it.
///
/// The build-time codegen lowers this to a render blob, and the `setState`
/// selection lowers to a state switch *inside* the blob — so the same file
/// drives both the local authoring preview and the delivered, over-the-air
/// surface, with no host code on the selection.
///
/// To tailor it: rename it, restyle the rows, and point the two slots
/// (`annual` / `monthly`) at your own products in `Restage.configure(products:)`.
@PaywallSource(id: 'minimal_paywall')
class MinimalPaywall extends StatefulWidget {
  /// Const constructor.
  const MinimalPaywall({super.key});

  @override
  State<MinimalPaywall> createState() => _MinimalPaywallState();
}

class _MinimalPaywallState extends State<MinimalPaywall> {
  /// Plan selection: the annual plan is the default; tapping Monthly flips it.
  bool annualSelected = true;

  void selectAnnual() => setState(() => annualSelected = true);
  void selectMonthly() => setState(() => annualSelected = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Close affordance, top-left. The host listens for `close` and
              // pops the paywall back to where it was shown.
              Row(
                children: [
                  GestureDetector(
                    onTap: paywallEvent('close'),
                    child: Icon(
                      Icons.close_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'Go Pro',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Everything, unlocked.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // Annual plan row (default selected). The border tracks selection.
              GestureDetector(
                onTap: selectAnnual,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: annualSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Annual',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        paywallPriceFor(slot: 'annual'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Monthly plan row.
              GestureDetector(
                onTap: selectMonthly,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: annualSelected
                          ? Theme.of(context).colorScheme.outlineVariant
                          : Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Monthly',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        paywallPriceFor(slot: 'monthly'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Purchase CTA — buys the selected plan's slot.
              GestureDetector(
                onTap: paywallPurchase(
                    slot: annualSelected ? 'annual' : 'monthly'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
