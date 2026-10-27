# restage_svg

An optional native SVG catalog for Restage. Add `restage_svg` to an app's
dependencies and author ordinary `SvgPicture.asset`, `.network`, `.string`,
`.memory`, `.file`, or `SvgPicture` with a supported native SVG loader. Generated
registrations install the `restage.svg` library with capability version 2.

```dart
import 'package:flutter_svg/flutter_svg.dart';

SvgPicture.string(
  '<svg viewBox="0 0 10 10"><path d="M0 0h10v10H0z"/></svg>',
  width: 24,
  matchTextDirection: true,
);
```

The catalog preserves native loading, caching, layout, semantics, SVG themes,
color filters, headers, and byte data. Asset paths and package names retain
Flutter asset resolution. Network sources use the native package loader. Byte
constructors accept bounded lists of integers from 0 through 255.

`SvgTheme.currentColor` and `ColorFilter.mode` support canonical Material colors
such as `Colors.red` and `Colors.redAccent`. Constructor-supplied `Color`,
`MaterialColor`, and `MaterialAccentColor` values retain their native identity,
components, color space, and swatch behavior. Custom swatches can also be created
in supported callback or helper initializers, retaining their original map.

Pass existing `AssetBundle`, `http.Client`, `ColorMapper`, `File`, and `BytesLoader`
objects through final constructor fields to use them in supported SVG arguments.
This includes custom implementations supplied as those native types. Generated
bindings retain the actual objects; their implementation stays compiled into the
app, and their caller retains ownership and responsibility for disposal. File
constructors use an existing `File` on platforms supported by `flutter_svg`;
surface payload paths do not construct files.

`placeholderBuilder` uses the shared widget builder contract. `errorBuilder` and
`imageBuilder` accept typed constructor-supplied callbacks and supported ordinary
closures compiled into the app. They receive the actual native callback context
and original error, stack trace, or child widget. Supported closures can retain
locals from an enclosing builder invocation.

Fresh values with observable construction effects require a supported callback
or helper initializer. Effectful root arguments whose evaluation order cannot
be preserved receive authoring diagnostics. Capturing the source screen's build
context or reconstructing its `State` lifecycle is unsupported. Native callback
contexts belong to the generated Surface tree; the original source screen is
not retained as an ancestor.

Regenerate and ship matching SVG and app factories before publishing content
that uses these features. Native bindings require SDK capability 24; SVG library
capability 2 is a separate requirement. Apps without this optional package have
no SVG capability requirement.
