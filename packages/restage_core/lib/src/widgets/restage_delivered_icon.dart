import 'package:flutter/widgets.dart';

/// An icon drawn from a delivered font by code point, laid out and themed the
/// way [Icon] draws one.
///
/// It never builds an icon value from the code point, so an app keeps icon
/// tree shaking.
class RestageDeliveredIcon extends StatelessWidget {
  /// Draws [codePoint] from the font loaded as [fontFamily].
  const RestageDeliveredIcon({
    required this.codePoint,
    required this.fontFamily,
    this.matchTextDirection = false,
    this.size,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.color,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
    this.applyTextScaling,
    this.blendMode,
    this.fontWeight,
    super.key,
  });

  /// The glyph's code point in the loaded font.
  final int codePoint;

  /// The family name the font was loaded under.
  final String fontFamily;

  /// Whether the glyph flips horizontally in a right-to-left context.
  final bool matchTextDirection;

  /// See [Icon.size].
  final double? size;

  /// See [Icon.fill].
  final double? fill;

  /// See [Icon.weight].
  final double? weight;

  /// See [Icon.grade].
  final double? grade;

  /// See [Icon.opticalSize].
  final double? opticalSize;

  /// See [Icon.color].
  final Color? color;

  /// See [Icon.shadows].
  final List<Shadow>? shadows;

  /// See [Icon.semanticLabel].
  final String? semanticLabel;

  /// See [Icon.textDirection].
  final TextDirection? textDirection;

  /// See [Icon.applyTextScaling].
  final bool? applyTextScaling;

  /// See [Icon.blendMode].
  final BlendMode? blendMode;

  /// See [Icon.fontWeight].
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    assert(textDirection != null || debugCheckHasDirectionality(context));
    final direction = textDirection ?? Directionality.of(context);
    final iconTheme = IconTheme.of(context);
    final scaling = applyTextScaling ?? iconTheme.applyTextScaling ?? false;
    final tentativeSize = size ?? iconTheme.size ?? kDefaultFontSize;
    final iconSize = scaling
        ? MediaQuery.textScalerOf(context).scale(tentativeSize)
        : tentativeSize;
    final iconFill = fill ?? iconTheme.fill;
    final iconWeight = weight ?? iconTheme.weight;
    final iconGrade = grade ?? iconTheme.grade;
    final iconOpticalSize = opticalSize ?? iconTheme.opticalSize;
    final iconShadows = shadows ?? iconTheme.shadows;

    final iconOpacity = iconTheme.opacity ?? 1.0;
    Color? iconColor = color ?? iconTheme.color!;
    Paint? foreground;
    if (iconOpacity != 1.0) {
      iconColor = iconColor.withValues(alpha: iconColor.a * iconOpacity);
    }
    if (blendMode != null) {
      foreground = Paint()
        ..blendMode = blendMode!
        ..color = iconColor;
      // A text style takes a color or a foreground, not both.
      iconColor = null;
    }

    final style = TextStyle(
      fontVariations: <FontVariation>[
        if (iconFill != null) FontVariation('FILL', iconFill),
        if (iconWeight != null) FontVariation('wght', iconWeight),
        if (iconGrade != null) FontVariation('GRAD', iconGrade),
        if (iconOpticalSize != null) FontVariation('opsz', iconOpticalSize),
      ],
      inherit: false,
      color: iconColor,
      fontSize: iconSize,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      shadows: iconShadows,
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
      foreground: foreground,
    );

    Widget glyph = RichText(
      overflow: TextOverflow.visible,
      textDirection: direction,
      text: TextSpan(text: String.fromCharCode(codePoint), style: style),
    );

    if (matchTextDirection && direction == TextDirection.rtl) {
      glyph = Transform(
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        alignment: Alignment.center,
        transformHitTests: false,
        child: glyph,
      );
    }

    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox(
          width: iconSize,
          height: iconSize,
          child: Center(child: glyph),
        ),
      ),
    );
  }
}
