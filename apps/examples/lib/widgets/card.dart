import 'package:flutter/widgets.dart';

/// The app's own card: a heading over its child.
///
/// It shares its name with Flutter's Material `Card` and is a different class.
class Card extends StatelessWidget {
  /// Creates a card.
  const Card({super.key, required this.heading, required this.child});

  /// The heading.
  final String heading;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [Text(heading), child]),
      );
}
