import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:restage_preview_harness/src/render_bundle_view_binding.dart';

void main() {
  group('render-bundle view configuration', () {
    test('identity scale preserves the browser view configuration', () {
      const base = ViewConfiguration(
        physicalConstraints: BoxConstraints.tightFor(
          width: 780,
          height: 1688,
        ),
        logicalConstraints: BoxConstraints.tightFor(
          width: 390,
          height: 844,
        ),
        devicePixelRatio: 2,
      );

      expect(renderBundleViewConfiguration(base, zoom: 1), base);
    });

    test('explicit frame replaces a stale zero browser configuration', () {
      const stale = ViewConfiguration(
        physicalConstraints: BoxConstraints.tightFor(),
        logicalConstraints: BoxConstraints.tightFor(),
        devicePixelRatio: 1,
      );

      final configured = renderBundleViewConfiguration(
        stale,
        zoom: 1,
        frame: const Size(390, 844),
      );

      expect(configured.devicePixelRatio, 1);
      expect(
        configured.physicalConstraints,
        const BoxConstraints.tightFor(width: 390, height: 844),
      );
      expect(
        configured.logicalConstraints,
        const BoxConstraints.tightFor(width: 390, height: 844),
      );
    });

    test('explicit frame multiplies browser DPR by committed zoom', () {
      const stale = ViewConfiguration(
        physicalConstraints: BoxConstraints.tightFor(),
        logicalConstraints: BoxConstraints.tightFor(),
        devicePixelRatio: 2,
      );

      final configured = renderBundleViewConfiguration(
        stale,
        zoom: 2,
        frame: const Size(390, 844),
      );

      expect(configured.devicePixelRatio, 4);
      expect(
        configured.physicalConstraints,
        const BoxConstraints.tightFor(width: 1560, height: 3376),
      );
      expect(
        configured.logicalConstraints,
        const BoxConstraints.tightFor(width: 390, height: 844),
      );
    });

    test('2x scale doubles effective DPR and preserves logical frame', () {
      const base = ViewConfiguration(
        physicalConstraints: BoxConstraints.tightFor(
          width: 1560,
          height: 3376,
        ),
        logicalConstraints: BoxConstraints.tightFor(
          width: 780,
          height: 1688,
        ),
        devicePixelRatio: 2,
      );

      final scaled = renderBundleViewConfiguration(base, zoom: 2);

      expect(scaled.devicePixelRatio, 4);
      expect(
        scaled.physicalConstraints,
        const BoxConstraints.tightFor(width: 1560, height: 3376),
      );
      expect(
        scaled.logicalConstraints,
        const BoxConstraints.tightFor(width: 390, height: 844),
      );
    });

    test('fractional scale derives logical constraints mechanically', () {
      const base = ViewConfiguration(
        physicalConstraints: BoxConstraints.tightFor(
          width: 975,
          height: 2110,
        ),
        logicalConstraints: BoxConstraints.tightFor(
          width: 780,
          height: 1688,
        ),
        devicePixelRatio: 1.25,
      );

      final scaled = renderBundleViewConfiguration(base, zoom: 2);

      expect(scaled.devicePixelRatio, 2.5);
      expect(scaled.logicalConstraints.maxWidth, 390);
      expect(scaled.logicalConstraints.maxHeight, 844);
    });

    test('metrics gate completes only the latest matching target', () async {
      final gate = RenderBundleViewportGate();
      final first = gate.begin(
        frame: const Size(390, 844),
        zoom: 2,
        browserDevicePixelRatio: 1,
      );
      final second = gate.begin(
        frame: const Size(320, 640),
        zoom: 1.5,
        browserDevicePixelRatio: 1,
      );

      await expectLater(first, completion(isFalse));
      expect(
        gate.accepts(
          const ViewConfiguration(
            physicalConstraints: BoxConstraints.tightFor(
              width: 780,
              height: 1688,
            ),
            logicalConstraints: BoxConstraints.tightFor(
              width: 390,
              height: 844,
            ),
            devicePixelRatio: 2,
          ),
        ),
        isFalse,
      );
      expect(
        gate.accepts(
          const ViewConfiguration(
            physicalConstraints: BoxConstraints.tightFor(
              width: 480,
              height: 960,
            ),
            logicalConstraints: BoxConstraints.tightFor(
              width: 320,
              height: 640,
            ),
            devicePixelRatio: 1.5,
          ),
        ),
        isTrue,
      );
      await expectLater(second, completion(isTrue));
    });

    test(
      'metrics gate accepts fractional recomputation in the same physical '
      'pixels',
      () async {
        final gate = RenderBundleViewportGate();
        const frame = Size(393, 667.2);
        final target = gate.begin(
          frame: frame,
          zoom: 1.5,
          browserDevicePixelRatio: 1.75,
        );
        const effectiveDevicePixelRatio = 2.625;
        final physical = BoxConstraints.tightFor(
          width: (frame.width * effectiveDevicePixelRatio).roundToDouble(),
          height: (frame.height * effectiveDevicePixelRatio).roundToDouble(),
        );

        final configuration = ViewConfiguration(
          physicalConstraints: physical,
          logicalConstraints: physical / effectiveDevicePixelRatio,
          devicePixelRatio: effectiveDevicePixelRatio,
        );

        expect(configuration.logicalConstraints.maxWidth, isNot(frame.width));
        expect(configuration.logicalConstraints.maxHeight, isNot(frame.height));
        expect(gate.accepts(configuration), isTrue);
        await expectLater(target, completion(isTrue));
      },
    );

    test('metrics gate rejects a different rounded physical height', () {
      final gate = RenderBundleViewportGate();
      const frame = Size(393, 667.2);
      gate.begin(
        frame: frame,
        zoom: 1.5,
        browserDevicePixelRatio: 1.75,
      );
      const effectiveDevicePixelRatio = 2.625;
      final wrongPhysical = BoxConstraints.tightFor(
        width: (frame.width * effectiveDevicePixelRatio).roundToDouble(),
        height: (frame.height * effectiveDevicePixelRatio).roundToDouble() + 1,
      );

      expect(
        gate.accepts(
          ViewConfiguration(
            physicalConstraints: wrongPhysical,
            logicalConstraints: wrongPhysical / effectiveDevicePixelRatio,
            devicePixelRatio: effectiveDevicePixelRatio,
          ),
        ),
        isFalse,
      );
      gate.cancel();
    });

    test(
      'metrics gate rejects a prior zoom with the same logical frame',
      () async {
        final gate = RenderBundleViewportGate();
        const frame = Size(390, 844);
        const browserDevicePixelRatio = 1.25;
        const requestedZoom = 1.5;
        final target = gate.begin(
          frame: frame,
          zoom: requestedZoom,
          browserDevicePixelRatio: browserDevicePixelRatio,
        );

        expect(
          gate.accepts(
            ViewConfiguration(
              physicalConstraints: BoxConstraints.tightFor(
                width: frame.width * browserDevicePixelRatio,
                height: frame.height * browserDevicePixelRatio,
              ),
              logicalConstraints: BoxConstraints.tightFor(
                width: frame.width,
                height: frame.height,
              ),
              devicePixelRatio: browserDevicePixelRatio,
            ),
          ),
          isFalse,
        );

        const requestedDevicePixelRatio =
            browserDevicePixelRatio * requestedZoom;
        final requestedPhysical = BoxConstraints.tightFor(
          width: (frame.width * requestedDevicePixelRatio).roundToDouble(),
          height: (frame.height * requestedDevicePixelRatio).roundToDouble(),
        );
        expect(
          gate.accepts(
            ViewConfiguration(
              physicalConstraints: requestedPhysical,
              logicalConstraints: requestedPhysical / requestedDevicePixelRatio,
              devicePixelRatio: requestedDevicePixelRatio,
            ),
          ),
          isTrue,
        );
        await expectLater(target, completion(isTrue));
      },
    );

    test('invalid zoom is rejected before a configuration is produced', () {
      const base = ViewConfiguration();

      for (final zoom in <double>[0, -1, double.infinity, double.nan]) {
        expect(
          () => renderBundleViewConfiguration(base, zoom: zoom),
          throwsArgumentError,
        );
      }
    });

    testWidgets(
      'bundle metric application does not redispatch global metric observers',
      (tester) async {
        await tester.pumpWidget(const SizedBox.expand());
        final observer = _CountingMetricsObserver();
        tester.binding.addObserver(observer);
        addTearDown(() => tester.binding.removeObserver(observer));
        var scheduledFrames = 0;
        final renderView = tester.binding.renderViews.single;

        applyRenderBundleViewConfigurations(
          renderViews: <RenderView>[renderView],
          configurationFor: (_) => renderView.configuration,
          scheduleForcedFrame: () => scheduledFrames += 1,
          cancelPending: () => fail('successful application must not cancel'),
        );

        expect(observer.calls, 0);
        expect(scheduledFrames, 1);
      },
    );

    testWidgets(
      'failed bundle metric application cancels the pending target',
      (tester) async {
        await tester.pumpWidget(const SizedBox.expand());
        final gate = RenderBundleViewportGate();
        final target = gate.begin(
          frame: const Size(390, 844),
          zoom: 1,
          browserDevicePixelRatio: 1,
        );

        expect(
          () => applyRenderBundleViewConfigurations(
            renderViews: <RenderView>[tester.binding.renderViews.single],
            configurationFor: (_) => throw StateError('synthetic failure'),
            scheduleForcedFrame: () =>
                fail('a failed application must not schedule'),
            cancelPending: gate.cancel,
          ),
          throwsStateError,
        );
        await expectLater(target, completion(isFalse));
      },
    );
  });
}

final class _CountingMetricsObserver with WidgetsBindingObserver {
  int calls = 0;

  @override
  void didChangeMetrics() {
    calls += 1;
  }
}
