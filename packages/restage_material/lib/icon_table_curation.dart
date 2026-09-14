/// Curation file for this package's icon table — it names the class whose
/// icon constants the generated table enumerates.
///
/// The catalog generator reads [kIconTableSource] and emits
/// `lib/src/icon_table.g.dart`, one `const` entry per Material icon code
/// point. Re-run build_runner after a Flutter SDK upgrade to pick up icons
/// the new SDK adds.
library;

import 'package:flutter/material.dart' show Icons;

/// The class whose `static const IconData` constants make up the generated
/// Material icon table.
const Type kIconTableSource = Icons;

/// Older Material Icon blobs carry only a code point and never mirror. Keep
/// those forms as const compatibility entries beside Flutter's original icons.
const bool kIconTableIncludeLegacyNonMirroring = true;
