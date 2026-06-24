/// The closed set of `Text`-surface properties the number/currency formatting
/// widgets (`RestagePrice` / `RestageFormattedNumber`) reproduce faithfully.
///
/// Single source of truth shared by two surfaces: the formatting widgets
/// themselves (which expose exactly these `Text` props — `style`, decomposed
/// through the shared text-style recipe; `textAlign`; and `maxLines`) and the
/// build-time recognizer that auto-substitutes a
/// `Text(NumberFormat(...).format(x), ...)` idiom to one of those widgets. The
/// recognizer carries a recognized `Text`'s properties only when **every** set
/// property is named here; any property outside this set blocks the
/// substitution (a clean defer), so a styled `Text` is never silently reduced
/// to an unstyled one.
///
/// The two directions are pinned by tests on both sides: a name here the
/// widget does not expose would be a silent drop on substitution, and a widget
/// property missing here would be a spurious defer. Visual overflow rides
/// inside `style` (`TextStyle.overflow`), the same way every catalogued `Text`
/// reaches it. The order is not significant.
const List<String> kRestageFormattedTextProps = <String>[
  'style',
  'textAlign',
  'maxLines',
];
