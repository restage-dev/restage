import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

void main() {
  testWidgets(
      'legacy image alignment and numeric gradients use actual RFW values',
      (tester) async {
    final runtime = Runtime();
    addTearDown(runtime.dispose);
    final images = <DecorationImage>[];
    final oldGradients = <Gradient>[];
    final gradients = <Gradient>[];
    runtime.update(
        const LibraryName(['probe']),
        LocalWidgetLibrary({
          'Image': (context, source) {
            images
                .add(RestageDecoders.decorationImage(source, const ['value'])!);
            return const SizedBox();
          },
          'Gradient': (context, source) {
            oldGradients
                .add(ArgumentDecoders.gradient(source, const ['value'])!);
            gradients.add(RestageDecoders.gradient(source, const ['value'])!);
            return const SizedBox();
          },
        }));
    const cases = [
      'Image(value: {image:{kind:"asset",src:"a.png"},alignment:{x:1,y:0}})',
      'Image(value: {image:{kind:"asset",src:"a.png"},alignment:{start:1.0,y:0.0}})',
      'Image(value: {image:{kind:"asset",src:"a.png"},alignment:{start:1,x:1,y:0}})',
      'Gradient(value: {type:"radial",radius:1,focalRadius:1,colors:[4278190080,4294967295]})',
      'Gradient(value: {type:"sweep",startAngle:1,endAngle:2,colors:[4278190080,4294967295]})',
      'Gradient(value: {type:"linear",begin:{start:1.0,y:0.0},colors:[4278190080,4294967295]})',
    ];
    for (final source in cases) {
      runtime.update(const LibraryName(['screen']),
          parseLibraryFile('import probe; widget Root = $source;'));
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.rtl,
          child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(
                  LibraryName(['screen']), 'Root'))));
      expect(tester.takeException(), isNull);
    }
    expect(images.map((image) => image.alignment), [
      const DecorationImage(
              image: AssetImage('a.png'), alignment: Alignment(1, 0))
          .alignment,
      const DecorationImage(
              image: AssetImage('a.png'), alignment: AlignmentDirectional(1, 0))
          .alignment,
      const Alignment(1, 0),
    ]);
    const colors = [Color(0xFF000000), Color(0xFFFFFFFF)];
    expect((oldGradients[0] as RadialGradient).radius, 0.5);
    expect((oldGradients[0] as RadialGradient).focalRadius, 0.0);
    expect(gradients[0],
        const RadialGradient(radius: 1, focalRadius: 1, colors: colors));
    expect((oldGradients[1] as SweepGradient).startAngle, 0.0);
    expect((oldGradients[1] as SweepGradient).endAngle, isNot(2.0));
    expect(gradients[1],
        const SweepGradient(startAngle: 1, endAngle: 2, colors: colors));
    expect(gradients[2], oldGradients[2]);
    expect((gradients[2] as LinearGradient).begin,
        const AlignmentDirectional(1, 0));
  });
}
