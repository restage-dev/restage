/// The full Material icon table, in two halves: the glyphs that mirror in a
/// right-to-left locale and the rest.
///
/// The tables themselves are generated — see `lib/icon_table_curation.dart`
/// for the class their entries come from. Pass both to
/// `RestageIconTable.fromFamilies` under the `MaterialIcons` family to install
/// them.
library;

export 'src/compact_icon_table.g.dart'
    show createMaterialIconTable, createMirroredMaterialIconTable;
export 'src/icon_table.g.dart'
    show kMaterialIconTable, kMirroredMaterialIconTable;
