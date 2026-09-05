/// Material bar heights, mirrored at build time so the toolchain can size a
/// bar slot before the bar itself lays out.
library;

/// The height an app bar occupies when it states none of its own.
const double kRestageToolbarHeight = 56;

/// The height one tab occupies.
const double kRestageTabHeight = 46;

/// The height one tab occupies when it carries both an icon and a label.
const double kRestageTabWithIconHeight = 72;

/// The thickness a tab bar adds below its tabs for the selection indicator.
const double kRestageTabIndicatorWeight = 2;
