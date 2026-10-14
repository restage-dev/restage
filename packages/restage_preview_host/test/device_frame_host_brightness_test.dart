import 'package:device_preview/device_preview.dart' as dp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_preview_host/restage_preview_host.dart';

Widget _host(Brightness? brightness) => MediaQuery(
      data: const MediaQueryData(platformBrightness: Brightness.light),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DeviceFrameHost(
          device: DeviceInfo.iPhone16ProMax,
          brightness: brightness,
          child: const SizedBox.expand(),
        ),
      ),
    );

Brightness? _frameBrightness(WidgetTester tester) => tester
    .widget<dp.DevicePreviewFrame>(find.byType(dp.DevicePreviewFrame))
    .simulation
    .value
    ?.platformBrightness;

void main() {
  testWidgets('the frame follows the given brightness', (tester) async {
    await tester.pumpWidget(_host(Brightness.dark));
    expect(_frameBrightness(tester), Brightness.dark);
    await tester.pumpWidget(_host(Brightness.light));
    expect(_frameBrightness(tester), Brightness.light);
    await tester.pumpWidget(_host(Brightness.dark));
    expect(_frameBrightness(tester), Brightness.dark);
  });

  testWidgets('without a brightness the frame uses the ambient one',
      (tester) async {
    await tester.pumpWidget(_host(null));
    expect(_frameBrightness(tester), Brightness.light);
  });
}
