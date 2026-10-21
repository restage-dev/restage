import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';

void main() {
  test('a prefixed family without a package is split', () {
    final style = RestageDecoders.packagedFont(
      const TextStyle(
        fontFamily: 'packages/fonts/Serif',
        fontFamilyFallback: ['packages/fonts/Sans'],
      ),
    );
    expect(style.fontFamily, 'packages/fonts/Serif');
    expect(style.fontFamilyFallback, ['packages/fonts/Sans']);
    const ambient = TextStyle(fontFamily: 'Body', package: 'fonts');
    expect(ambient.merge(style).fontFamily, 'packages/fonts/Serif');
  });

  test('a style with its package or a plain family is unchanged', () {
    const packaged = TextStyle(fontFamily: 'Serif', package: 'fonts');
    expect(RestageDecoders.packagedFont(packaged), packaged);
    const plain = TextStyle(fontFamily: 'Serif');
    expect(identical(RestageDecoders.packagedFont(plain), plain), isTrue);
  });
}
