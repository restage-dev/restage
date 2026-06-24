import 'package:flutter/material.dart';
import 'package:restage_material/restage_material.dart';

/// On-device demo for [RestageDraggableSheet] — the declarative, persistent,
/// non-closeable detent sheet — exercised on its canonical use case: a
/// Maps-style "nearby places" sheet that lives over a map the whole time.
///
/// Unlike a modal sheet, this sheet is always on screen. It rests at a peek
/// (search field + result summary), drags up to a mid detent (a few cards over
/// the visible map) and up again to a full detent (the whole scrollable list),
/// and bottoms out at the peek — it never dismisses. A header button drives the
/// same expand/collapse declaratively via the [RestageDraggableSheet.expanded]
/// channel, so both expand paths (manual drag and the flag) are demoed.
///
/// What this demo proves, that a modal sheet cannot:
///   1. draggable detents (peek <-> mid <-> full) with snap physics;
///   2. a non-closeable floor (always shows the peek, never dismisses);
///   3. inner-scroll <-> sheet-drag coordination (the long body scrolls once
///      the sheet is at full, and drags the sheet when scrolled back to top);
///   4. the declarative `expanded` state channel driven by a tap control, in
///      addition to drag.
///
/// Honoring the widget's child contract, the body is ORDINARY (non-scrollable)
/// content — a tall [Column] of place rows. [RestageDraggableSheet] wraps it in
/// the single, controller-bound scroll view that delivers (3); we never hand it
/// a [ListView] (that would nest viewports and break the controller thread).
///
/// Run on iOS and Android to confirm the drag/scroll feel both ways — the
/// platform scroll physics adapt automatically (bouncy on iOS, clamping on
/// Android); the widget itself is platform-neutral:
///   flutter run -t lib/main_draggable_sheet_demo.dart
///
/// The gallery embeds [DraggableSheetDemo] (the home content below) as a tile;
/// this entrypoint wraps the same widget in a [MaterialApp] for a standalone run.
void main() => runApp(const _DraggableSheetDemoApp());

class _DraggableSheetDemoApp extends StatelessWidget {
  const _DraggableSheetDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Draggable sheet demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A73E8),
        useMaterial3: true,
      ),
      home: const DraggableSheetDemo(),
    );
  }
}

/// The draggable-sheet capability demo surface — a persistent, non-closeable
/// detent [RestageDraggableSheet] over a stylized map. Mounted full-screen by
/// both the standalone entrypoint and the example gallery.
class DraggableSheetDemo extends StatefulWidget {
  /// Creates the draggable-sheet demo surface.
  const DraggableSheetDemo({super.key});

  @override
  State<DraggableSheetDemo> createState() => _DraggableSheetDemoState();
}

class _DraggableSheetDemoState extends State<DraggableSheetDemo> {
  // The peek/mid/full detents, as fractions of the available height. The peek
  // equals the floor (the sheet never drops below it — non-closeable); mid is a
  // snap stop revealing the map + a few cards; full reveals the whole list.
  static const double _peek = 0.12;
  static const double _mid = 0.5;
  static const double _full = 0.92;

  // The declarative state channel: the header button flips this and the sheet
  // animates to/from its expanded detent. A manual drag is independent of it.
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          // The persistent surface beneath the sheet: a stylized map.
          const _MapBackdrop(),
          // The persistent sheet. It bottoms out at the peek (minChildSize ==
          // initialChildSize) and never dismisses; snaps between peek, mid, and
          // full; and animates to full / back to peek when [expanded] flips.
          // The child is ordinary content — the widget owns the scroll view.
          RestageDraggableSheet(
            expanded: _expanded,
            initialChildSize: _peek,
            minChildSize: _peek,
            maxChildSize: _full,
            snap: true,
            snapSizes: const <double>[_mid],
            expandCurve: Curves.easeOutCubic,
            expandDuration: const Duration(milliseconds: 320),
            child: _NearbyPlacesBody(expanded: _expanded, onToggle: _toggle),
          ),
        ],
      ),
    );
  }
}

/// A stylized "map" beneath the sheet — the screen the sheet sits over for its
/// whole lifetime (it is never covered by a scrim or closed away).
class _MapBackdrop extends StatelessWidget {
  const _MapBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFE8F0E8), Color(0xFFDCE7F0)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            // A couple of "roads".
            Positioned(
              top: 140,
              left: -40,
              right: -40,
              child: Transform.rotate(
                angle: -0.18,
                child: Container(height: 14, color: const Color(0xFFFFFFFF)),
              ),
            ),
            Positioned(
              top: 320,
              left: -40,
              right: -40,
              child: Transform.rotate(
                angle: 0.12,
                child: Container(height: 10, color: const Color(0xFFFFFFFF)),
              ),
            ),
            // A "you are here" pin near the top.
            const Positioned(
              top: 92,
              left: 0,
              right: 0,
              child: Icon(
                Icons.location_on,
                size: 44,
                color: Color(0xFF1A73E8),
              ),
            ),
            // A few place markers scattered over the map.
            const Positioned(
              top: 200,
              left: 60,
              child: _MapMarker(),
            ),
            const Positioned(
              top: 256,
              right: 72,
              child: _MapMarker(),
            ),
            const Positioned(
              top: 360,
              left: 110,
              child: _MapMarker(),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFFEA4335),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFFFFFF), width: 2.5),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// The sheet body — its own surface (rounded top, grab handle, shadow), since
/// [RestageDraggableSheet] draws nothing of its own. This is ORDINARY
/// (non-scrollable) content: a header (handle, title, search field, summary,
/// and the declarative expand/collapse button) followed by a tall [Column] of
/// place rows. The widget wraps the whole thing in the controller-bound scroll
/// view, so it is draggable everywhere and the rows scroll once at the full
/// detent — never a nested [ListView].
class _NearbyPlacesBody extends StatelessWidget {
  const _NearbyPlacesBody({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  static const List<_Place> _places = <_Place>[
    _Place('Roastery Coffee Bar', 'Cafe · open now', 0.2, Icons.local_cafe),
    _Place('Riverside Park', 'Park · open 24h', 0.4, Icons.park),
    _Place('Central Station', 'Transit · 3 lines', 0.5, Icons.train),
    _Place('The Corner Bakery', 'Bakery · open now', 0.6, Icons.bakery_dining),
    _Place('Greenleaf Grocer', 'Grocery · open now', 0.7,
        Icons.local_grocery_store),
    _Place('City Library', 'Library · open until 9', 0.9, Icons.local_library),
    _Place('Harbor Bistro', 'Restaurant · \$\$', 1.1, Icons.restaurant),
    _Place('Sunset Pharmacy', 'Pharmacy · open now', 1.2, Icons.local_pharmacy),
    _Place('Maple Street Gym', 'Gym · open 24h', 1.4, Icons.fitness_center),
    _Place('Old Town Cinema', 'Cinema · 4 screens', 1.6, Icons.local_movies),
    _Place('Bayview Hotel', 'Hotel · 4.5 stars', 1.8, Icons.hotel),
    _Place(
        'Quick Fuel Station', 'Gas · open now', 2.0, Icons.local_gas_station),
    _Place('Lakeside Pizzeria', 'Restaurant · \$', 2.2, Icons.local_pizza),
    _Place(
        'Northgate Mall', 'Shopping · open until 8', 2.5, Icons.shopping_bag),
    _Place(
        'Community Hospital', 'Hospital · 24h ER', 2.9, Icons.local_hospital),
    _Place('Airport Express', 'Transit · shuttle', 3.4, Icons.directions_bus),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 18,
            spreadRadius: -2,
            offset: Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ---- Header (always visible at the peek) ----
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'Nearby',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    // The declarative expand/collapse control. Tapping it flips
                    // the [expanded] flag, which animates the sheet to the full
                    // detent (or back to the peek) via the controller — the
                    // programmatic expand path, distinct from a manual drag.
                    TextButton.icon(
                      onPressed: onToggle,
                      icon: Icon(expanded ? Icons.map : Icons.list),
                      label:
                          Text(expanded ? 'Back to map' : 'Show all results'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // A non-interactive search affordance (the persistent peek
                // content that stays on screen even at the floor).
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.search,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Text(
                        'Search this area',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_places.length} places nearby',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          // ---- The long, scroll-on-expand list of places ----
          // Ordinary content (a Column of rows), NOT a ListView: the widget's
          // own controller-bound scroll view scrolls this once the sheet is at
          // the full detent, and drags the sheet when scrolled back to the top.
          for (final place in _places) _PlaceRow(place: place),
          // A footer so the smoke can confirm the inner list scrolled to its
          // end (bouncy on iOS, clamping on Android) without the sheet shrinking.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'End of results',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Place {
  const _Place(this.name, this.subtitle, this.distanceKm, this.icon);

  final String name;
  final String subtitle;
  final double distanceKm;
  final IconData icon;
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place});

  final _Place place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(place.icon, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  place.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(place.subtitle, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${place.distanceKm.toStringAsFixed(1)} km',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
