import 'package:flutter/material.dart' show Colors;
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'exact_color_constants.dart' show tinyColor, importedMaterialColor;
import 'exact_color_constants.dart' as colors;

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>';
const localColor = Color.from(alpha: .75, red: .2, green: .4, blue: .8);
const localArgbColor = Color.fromARGB(127, 12, 34, 56);
const Color subtype = Colors.red;
const Color? absent = null;
const invalid = Color.from(alpha: 1, red: double.infinity, green: 0, blue: 0);

Widget direct() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(
    currentColor: Color.from(alpha: .75, red: .2, green: .4, blue: .8),
  ),
  colorFilter: const ColorFilter.mode(
    Color.from(alpha: .75, red: .2, green: .4, blue: .8),
    BlendMode.srcIn,
  ),
);
Widget local() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: localColor),
  colorFilter: const ColorFilter.mode(localColor, BlendMode.srcIn),
);
Widget imported() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: tinyColor),
  colorFilter: const ColorFilter.mode(tinyColor, BlendMode.srcIn),
);
Widget prefixed() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: colors.hugeColor),
  colorFilter: const ColorFilter.mode(colors.hugeColor, BlendMode.srcIn),
);
Widget nested() => SvgPicture.string(
  _svg,
  theme: colors.hugeTheme,
  colorFilter: colors.hugeFilter,
);
Widget builderDirect() => LayoutBuilder(
  builder: (context, constraints) => SvgPicture.string(
    _svg,
    theme: const SvgTheme(
      currentColor: Color.from(alpha: .75, red: .2, green: .4, blue: .8),
    ),
    colorFilter: const ColorFilter.mode(colors.hugeColor, BlendMode.srcIn),
  ),
);
Widget builderAliases() => LayoutBuilder(
  builder: (context, constraints) => SvgPicture.string(
    _svg,
    theme: const SvgTheme(currentColor: tinyColor),
    colorFilter: const ColorFilter.mode(localColor, BlendMode.srcIn),
  ),
);
Widget subtypeRefused() =>
    SvgPicture.string(_svg, theme: const SvgTheme(currentColor: subtype));
Widget nullRefused() =>
    SvgPicture.string(_svg, theme: SvgTheme(currentColor: absent as dynamic));
Widget dynamicRefused(dynamic value) =>
    SvgPicture.string(_svg, theme: SvgTheme(currentColor: value));
Widget nonfiniteRefused() => SvgPicture.string(
  _svg,
  colorFilter: const ColorFilter.mode(invalid, BlendMode.srcIn),
);

Widget fractional() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: Color.fromRGBO(1, 2, 3, .1)),
  colorFilter: const ColorFilter.mode(
    colors.fractionalOpacity,
    BlendMode.srcIn,
  ),
);

Widget argbDirect() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: Color.fromARGB(127, 12, 34, 56)),
  colorFilter: const ColorFilter.mode(
    Color.fromARGB(127, 12, 34, 56),
    BlendMode.srcIn,
  ),
);

Widget argbAliases() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: localArgbColor),
  colorFilter: const ColorFilter.mode(colors.argbColor, BlendMode.srcIn),
);

Widget argbMaskedDirect() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: Color.fromARGB(-1, 256, 257, -258)),
  colorFilter: const ColorFilter.mode(
    Color.fromARGB(-1, 256, 257, -258),
    BlendMode.srcIn,
  ),
);

Widget argbMaskedAliases() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: colors.maskedArgbColor),
  colorFilter: const ColorFilter.mode(colors.maskedArgbColor, BlendMode.srcIn),
);

Widget builderArgbDirect() => LayoutBuilder(
  builder: (context, constraints) => SvgPicture.string(
    _svg,
    theme: const SvgTheme(currentColor: Color.fromARGB(127, 12, 34, 56)),
    colorFilter: const ColorFilter.mode(
      Color.fromARGB(127, 12, 34, 56),
      BlendMode.srcIn,
    ),
  ),
);

Widget builderArgbAliases() => LayoutBuilder(
  builder: (context, constraints) => SvgPicture.string(
    _svg,
    theme: const SvgTheme(currentColor: localArgbColor),
    colorFilter: const ColorFilter.mode(colors.argbColor, BlendMode.srcIn),
  ),
);

Widget builderArgbMaskedDirect() => LayoutBuilder(
  builder: (context, constraints) => SvgPicture.string(
    _svg,
    theme: const SvgTheme(currentColor: Color.fromARGB(511, -1, 512, 258)),
    colorFilter: const ColorFilter.mode(
      Color.fromARGB(511, -1, 512, 258),
      BlendMode.srcIn,
    ),
  ),
);

Widget builderArgbMaskedAliases() => LayoutBuilder(
  builder: (context, constraints) => SvgPicture.string(
    _svg,
    theme: const SvgTheme(currentColor: colors.overflowArgbColor),
    colorFilter: const ColorFilter.mode(
      colors.overflowArgbColor,
      BlendMode.srcIn,
    ),
  ),
);

Color argbDivisionFirst(int denominator) =>
    Color.fromARGB(1 ~/ denominator, denominator.clamp(2, 1).toInt(), 0, 0);
Color argbClampFirst(int denominator) =>
    Color.fromARGB(denominator.clamp(2, 1).toInt(), 1 ~/ denominator, 0, 0);
Color rgboDivisionFirst(int denominator) =>
    Color.fromRGBO(1 ~/ denominator, 0, 0, denominator.clamp(2, 1).toDouble());
Color rgboClampFirst(int denominator) => Color.fromRGBO(
  denominator.clamp(2, 1).toInt(),
  0,
  0,
  (1 ~/ denominator).toDouble(),
);

Widget materialDirect() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: Colors.red),
  colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn),
);

Widget materialAliasFixture() =>
    SvgPicture.string(_svg, theme: const SvgTheme(currentColor: subtype));

Widget materialPrefixed() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: material.Colors.blueAccent),
);

Widget materialImported() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: importedMaterialColor),
);

Widget materialNested() =>
    SvgPicture.string(_svg, theme: colors.importedMaterialTheme);

Widget accentBuilder() => LayoutBuilder(
  builder: (context, constraints) {
    final Color selected = constraints.maxWidth > 0
        ? Colors.redAccent
        : const Color(0xff010203);
    return SvgPicture.string(
      _svg,
      theme: SvgTheme(currentColor: selected),
      colorFilter: ColorFilter.mode(selected, BlendMode.srcIn),
    );
  },
);

Widget baseBuilder() => LayoutBuilder(
  builder: (context, constraints) {
    final Color selected = constraints.maxWidth < 0
        ? Colors.redAccent
        : const Color(0xff010203);
    return SvgPicture.string(
      _svg,
      theme: SvgTheme(currentColor: selected),
      colorFilter: ColorFilter.mode(selected, BlendMode.srcIn),
    );
  },
);

Widget nestedMaterialBuilder() => LayoutBuilder(
  builder: (context, constraints) {
    final Color selected = constraints.maxWidth > 0
        ? Colors.purple
        : const Color(0xff010203);
    return LayoutBuilder(
      builder: (context, inner) => SvgPicture.string(
        _svg,
        theme: SvgTheme(currentColor: selected),
        colorFilter: ColorFilter.mode(selected, BlendMode.srcIn),
      ),
    );
  },
);

Widget materialShade() =>
    SvgPicture.string(_svg, theme: SvgTheme(currentColor: Colors.red.shade500));

class MaterialColor extends Color {
  const MaterialColor(super.value);
}

const unprovenSubtype = MaterialColor(0xff123456);
Widget unprovenSubtypeRefused() => SvgPicture.string(
  _svg,
  theme: const SvgTheme(currentColor: unprovenSubtype),
);
