import 'package:restage_shared/src/capability/builtin_icon_code_points.g.dart';

/// The code points of the built-in icon families, per font family.
///
/// Both families by default; each can be left out, as in
/// `Restage.configure(includeMaterial:, includeCupertino:)`.
Map<String, Set<int>> builtInIconCodePoints({
  bool includeMaterial = true,
  bool includeCupertino = true,
}) =>
    {
      for (final entry in kBuiltInIconCodePointRuns.entries)
        if (entry.key == 'MaterialIcons' ? includeMaterial : includeCupertino)
          entry.key: {
            for (var i = 0; i < entry.value.length; i += 2)
              for (var n = 0; n < entry.value[i + 1]; n++) entry.value[i] + n,
          },
    };
