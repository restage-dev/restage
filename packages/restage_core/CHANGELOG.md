# Changelog

## Unreleased

- Add `RestageBuilderBinding.data`, the shape the app supplies for each app value
  a delivered builder body reads.
- Add `RestageBuilderBinding.color`, which projects an app color as a delivered
  body reads it.
- Fix: a `w100`–`w900` font weight decodes in release builds. Release builds strip `FontWeight.toString`.
- `GestureDetector` takes every gesture callback and `Semantics` its action callbacks, typed as Flutter declares them, at capability 26. Add `RestageDecoders.nativeCallback`, which reads a callback only the app's own closure can fill.
- **Breaking:** Remove `resolveInstalledIcon`, `InstalledIconTable.hasSelection` and the `explicitSelection` parameter of `InstalledIconTable.add`. Look an icon up with `InstalledIconTable.current.lookUp(fontFamily, codePoint)`, which returns null for a missing icon instead of throwing.
- **Breaking:** Remove `resolveThemeBinding`. Generated builders now pass null for a theme-resolved default, and the Flutter widget resolves its theme itself.
- Builders give an omitted argument Flutter's own default; they no longer substitute catalog values such as button padding. `TransformRotate.alignment` (capability 25) separates an explicit null from an omitted argument. `DefaultTextStyle` and `AnimatedDefaultTextStyle` keep the widget's `overflow` apart from the style's new `styleOverflow` (capability 25).
- Add `RestageIslandStage`, which marks a version of a published surface as shown or staged. While a version is staged, `RestageDecoders.nativeKey` returns null for a global key. A global key is never built in two versions at once.
- Add `RestageIslandStage.host`, which identifies the widget that shows a version.

- Add native Directionality, explicit textDirection, direction-preserving geometry,
  exact scoped TextScaler values, and native responsive/grid factories.
- Add native ClipPath and ShapeBorderClipper factories, including ClipPath.shape.
- Own recognized TextSpan gesture resources with native pending-gesture behavior,
  and evaluate supported native intl values through the shared typed value mechanism.

- Register `AbsorbPointer`, `IgnorePointer` and `GestureDetector.behavior` at
  catalog capability 16. Build surfaces with the `restage_codegen` release
  that matches this one: an older `restage_codegen` does not raise the
  capability floor of a surface that sets `behavior`.
- Add `RestageDecoders.string`, which reads a string or joins a list of parts,
  and `RestageDecoders.integerList` and `RestageDecoders.realList`.
- Add `RestageDecoders.widgetList` for conditional widget groups in runtime loops.
  Core catalog capability 10 includes the updated Column and Row factories.
- Shapes accept a radius per corner as well as one radius for all corners.

## 2.0.0

- Add `RestageDecoders.preferredSize` / `optionalPreferredSize`, which adapt a
  rendered slot value to a `PreferredSizeWidget` argument at the height carried
  beside it.
- Breaking: the registry and catalog use catalog schema v5 from
  `rfw_catalog_schema` 2.0.0. The closed event-name list is gone; a callback's
  constructor property name is its event identity, and a 1.x runtime or
  toolchain does not read this catalog.
- Regenerate the catalog as schema v5 with callback property names serving as
  open event identities.

## 1.0.2

- Documentation and build-configuration refresh.

## 1.0.1

- Add a usage example and shorten the package description.

## 1.0.0

- Initial release of the `restage.core` RFW catalog: 54 cross-platform widget
  primitives with per-widget metadata and the committed catalog JSON, plus the
  compiled-in motion (`RestageMotion`/`RestageFadeIn`/`RestagePulse`/
  `RestageStagger`/`RestageSpring`) and number/price formatter widgets.
