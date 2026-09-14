/// Curation file for this package's icon table — it names the class whose
/// icon constants the generated table enumerates, and the font those
/// constants belong to.
///
/// The catalog generator reads [kIconTableSource] and emits
/// `lib/src/icon_table.g.dart`, one `const` entry per Cupertino icon code
/// point. Re-run build_runner after a `cupertino_icons` upgrade to pick up
/// icons the new version adds.
library;

import 'package:flutter/cupertino.dart' show CupertinoIcons;

/// The class whose `static const IconData` constants make up the generated
/// Cupertino icon table.
const Type kIconTableSource = CupertinoIcons;

/// The icon font family the generated table covers.
const String kIconTableFontFamily = 'CupertinoIcons';

/// The package the Cupertino icon font ships in.
const String kIconTableFontPackage = 'cupertino_icons';
