import 'dart:io';

import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _color = '{a: 0.75, r: 0.2, g: 0.4, b: 0.8, colorSpace: "displayP3"}';
void main() {
  final core = decodeCatalog(
      File('../restage_core/lib/src/widget_catalog/catalog.json')
          .readAsStringSync());
  final svg = decodeCatalog(
      File('../restage_svg/lib/src/widget_catalog/catalog.json')
          .readAsStringSync());
  final catalog = Catalog(
      schemaVersion: core.schemaVersion,
      generatedAt: core.generatedAt,
      libraries: {...core.libraries, ...svg.libraries},
      widgets: [...core.widgets, ...svg.widgets],
      structuredTypes: [...core.structuredTypes, ...svg.structuredTypes],
      unions: [...core.unions, ...svg.unions]);
  SurfaceCapabilityDerivation derive(String root) => deriveSurfaceCapability(
      rfw.parseLibraryFile(
          'import restage.core; import restage.svg; widget Root = $root;'),
      catalog);
  test('local scoped SVG colors retain opaque decoder paths and selectors', () {
    for (final (body, payload, kind, expected) in [
      (
        'SvgPictureString(string:"<svg/>",theme:args.payload)',
        '{currentColor:args.color}',
        'mode',
        19
      ),
      (
        'SvgPictureString(string:"<svg/>",colorFilter:args.payload)',
        '{kind:args.kind,type:"mode",color:args.color,blendMode:"srcIn"}',
        'mode',
        19
      ),
      (
        'SvgPictureString(string:"<svg/>",colorFilter:args.payload)',
        '{kind:args.kind,type:"mode",color:args.color,blendMode:"srcIn"}',
        'srgbToLinearGamma',
        1
      ),
      (
        'SvgPicture(bytesLoader:args.payload)',
        '{kind:args.kind,theme:{currentColor:args.color}}',
        'SvgAssetLoader',
        19
      ),
      (
        'SvgPicture(bytesLoader:args.payload)',
        '{kind:args.kind,theme:{currentColor:args.color}}',
        'Unknown',
        1
      ),
    ]) {
      for (final color in [_color, '4278190080']) {
        final result = deriveSurfaceCapability(rfw.parseLibraryFile('''
          import restage.svg;
          widget Leaf = $body;
          widget Forward = Leaf(payload:args.payload);
          widget Bind = Forward(payload:$payload);
          widget Root = Bind(color:$color,kind:"$kind");
        '''), catalog);
        expect(result.builtInFloor, color == _color ? expected : 1,
            reason: '$body / $kind / $color');
      }
    }
  });
  test('finite recursive SVG forwarding retains typed exact color floors', () {
    for (final (body, legacy, exact) in [
      (
        'SvgPictureString(string:"<svg/>",theme:args.value)',
        '{currentColor:0}',
        '{currentColor:$_color}'
      ),
      (
        'SvgPictureString(string:"<svg/>",colorFilter:args.value)',
        '{kind:"mode",color:0}',
        '{kind:"mode",color:$_color}'
      ),
      (
        'SvgPicture(bytesLoader:args.value)',
        '{kind:"SvgAssetLoader",theme:{currentColor:0}}',
        '{kind:"SvgAssetLoader",theme:{currentColor:$_color}}'
      ),
    ]) {
      final result = deriveSurfaceCapability(rfw.parseLibraryFile('''
        import restage.svg;
        widget Link = switch args.more {
          false: $body,
          default: Link(more:args.next.more,value:args.next.value,next:args.next.next)
        };
        widget Root = Link(more:true,value:$legacy,next:{more:false,value:$exact});
      '''), catalog);
      expect(result.builtInFloor, 19, reason: body);
      expect(result.requiredLibraries.single.namespace, 'restage.svg');
      expect(result.requiredLibraries.single.minGenerated, 3);
    }
  });
  test('common Paint native color filters retain the type discriminator', () {
    expect(
        derive('TextRich(textSpan:{text:"x"},foreground:{colorFilter:{type:"mode",kind:"srgbToLinearGamma",color:$_color}})')
            .builtInFloor,
        19);
    expect(
        derive('TextRich(textSpan:{text:"x"},foreground:{colorFilter:{type:"srgbToLinearGamma",kind:"mode",color:$_color}})')
            .builtInFloor,
        1);
  });
  test(
      'actual optional native color paths require SDK19 without Intl inflation',
      () {
    for (final root in [
      'SvgPictureString(string:"<svg/>",theme:{currentColor:$_color})',
      'SvgPictureString(string:"<svg/>",colorFilter:{kind:"mode",color:$_color,blendMode:"srcIn"})',
      for (final kind in [
        'SvgStringLoader',
        'SvgBytesLoader',
        'SvgAssetLoader',
        'SvgNetworkLoader'
      ])
        'SvgPicture(bytesLoader:{kind:"$kind",theme:{currentColor:$_color}})',
    ]) {
      final result = derive(root);
      expect(result.builtInFloor, 19, reason: root);
      expect(result.requiredLibraries.single.namespace, 'restage.svg');
      expect(result.requiredLibraries.single.minGenerated, 3);
      expect(
          BlobRenderCapabilityGate.evaluate(
              required: CapabilityManifest(
                  builtInFloor: result.builtInFloor,
                  requiredLibraries: result.requiredLibraries),
              installed: InstalledCapability(
                  builtInCatalogVersion: 18,
                  installedLibraries: [
                    InstalledLibrary(
                        namespace: 'restage.svg', version: 1, generated: 3)
                  ])).accepted,
          isFalse);
    }
  });
  test(
      'legacy optional values unrelated fields and core-only use keep prior requirements',
      () {
    for (final root in [
      'SvgPictureString(string:"<svg/>",theme:{currentColor:4278190080})',
      'SvgPictureString(string:"<svg/>",theme:{unused:$_color})',
      'SvgPictureString(string:"<svg/>",colorFilter:{kind:"srgbToLinearGamma",color:$_color})',
      'SvgPictureString(string:"<svg/>",colorFilter:{type:"mode",kind:"srgbToLinearGamma",color:$_color})',
      'SvgPicture(bytesLoader:{kind:"Unknown",theme:{currentColor:$_color}})',
      'SvgPicture(bytesLoader:{kind:"SvgAssetLoader",unused:{currentColor:$_color}})',
    ]) {
      expect(derive(root).builtInFloor, 1, reason: root);
    }
    expect(derive('SizedBox(width:1.0)').requiredLibraries, isEmpty);
  });
}
