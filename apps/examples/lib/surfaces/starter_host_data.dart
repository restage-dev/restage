import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/starter_host_data.restage.g.dart';

/// One row the app owns.
///
/// A plain data class: public final fields, a const constructor, no behavior.
/// That is what lets the build encode it for the delivered surface and lower
/// reads like `item.title` inside the loop below.
final class ChecklistItem {
  /// Creates a row.
  const ChecklistItem({
    required this.id,
    required this.title,
    required this.status,
  });

  /// Stable identity, carried by the tap event.
  final String id;

  /// What the row says.
  final String title;

  /// Shown as-is. The app decides the wording.
  final String status;
}

/// A checklist whose rows come from the app.
///
/// `owner` and `items` are host data. The generated `StarterChecklistSurface`
/// takes them as ordinary constructor arguments and the delivered surface reads
/// them under `data.context.*`. The `for` becomes a loop in the artifact, so
/// the row count is decided on the device from whatever the app passes.
@Screen(id: 'starter_checklist', surface: Surface.general)
final class StarterChecklist extends StatelessWidget {
  /// Creates the screen with the rows to show.
  const StarterChecklist({
    required this.owner,
    required this.items,
    super.key,
  });

  /// Whose list this is.
  final String owner;

  /// The rows, in display order.
  final List<ChecklistItem> items;

  /// A row was tapped. Carries the row's [ChecklistItem.id].
  static const toggle = SurfaceEvent<String>('toggle');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface, elevation: 0),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "$owner's checklist",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'These rows come from the app. Tap one and the app changes it.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: surfaceEvent(toggle, item.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 16,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          Text(
                            item.status,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ],
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
