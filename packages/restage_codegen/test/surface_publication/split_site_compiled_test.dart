import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:test/test.dart';

void main() {
  test('an island site carries its compiled arguments through JSON', () {
    const site = SplitSite(
      surface: 'lib/a.dart#A',
      mount: 'ASurface',
      name: 'app.islands:A_Caption_0',
      widget: 'Caption',
      location: 'lib/a.dart:3:5',
      kind: SplitSiteKind.island,
      reasonCode: 'unknownWidget',
      compiled: [
        (name: 'style', reason: 'notLiteral', message: 'it reads `s`.'),
      ],
    );
    final json = site.toJson();
    expect(json['compiled'], [
      {'name': 'style', 'reason': 'notLiteral', 'message': 'it reads `s`.'},
    ]);
    expect(SplitSite.fromJson(json).reasonCode, 'unknownWidget');
    expect(SplitSite.fromJson(json).compiled, site.compiled);
    expect(
      SplitSite.fromJson({...json}..remove('compiled')).compiled,
      isEmpty,
    );
    expect(
      () => SplitSite.fromJson({...json, 'compiled': 'style'}),
      throwsFormatException,
    );
  });
}
