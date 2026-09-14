part of '../lumen_cancel.dart';

sealed class LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenEvent();
}

final class LumenCancelReasonScreenReasonEvent
    extends LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenReasonEvent(this.value);

  final String value;
}

final class LumenCancelReasonScreenSkipEvent
    extends LumenCancelReasonScreenEvent {
  const LumenCancelReasonScreenSkipEvent();
}

final _lumenCancelReasonScreenEvents =
    SurfaceScreenEventContract<LumenCancelReasonScreenEvent>.generated(
  hash:
      "sha256:55bb77c38f6e53b2258a45594521bc78c955d54ae17505b1633c04fbba822784",
  decodeValidated: _decodeValidatedLumenCancelReasonScreenEvent,
);

final _lumenCancelReasonScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: "lumen_cancel_reason",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 6,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"reason\",\"arguments\":{\"encoding\":\"value\",\"shape\":{\"kind\":\"string\"}}},{\"id\":\"skip\",\"arguments\":{\"encoding\":\"none\"}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey: "assets/restage/bundles/lib/surfaces/lumen_cancel.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/lumen_cancel.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 31033,
        sha256:
            "sha256:1afb457035f5ab2169fd4830497d5a23502500a90bc616e8a23fc93447dd1ee0",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/7986973e7d641fcd/lumen_cancel_reason.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:4626263e7b23cd51848dee63e2f8e2e459654c7a54e86787c17de7cad3e2512f",
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Positioned': buildPositioned,
        'Row': buildRow,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Stack': buildStack,
        'Text': buildText,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf57a: IconData(0xf57a,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
);

final lumenCancelReasonScreenRef = SurfaceScreenRef<
    LumenCancelReasonScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelReasonScreenProvenance,
  eventContract: _lumenCancelReasonScreenEvents,
  measurementPublicationDraftDigest:
      "068d8f9073a7895ad3e34c92f10ac9f841f69b05e1d72d2104dde913ecc7ec28",
);

LumenCancelReasonScreenEvent _decodeValidatedLumenCancelReasonScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "reason":
      return LumenCancelReasonScreenReasonEvent(arguments['value'] as String);
    case "skip":
      return const LumenCancelReasonScreenSkipEvent();
  }
  throw FormatException(
      "Invalid LumenCancelReasonScreen event \"" + name + "\".");
}

final class LumenCancelReasonScreenSurface extends StatelessWidget {
  const LumenCancelReasonScreenSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<LumenCancelReasonScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelReasonScreenEvent>(
      screen: lumenCancelReasonScreenRef,
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => LumenCancelReasonScreen(),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}

sealed class LumenCancelThanksScreenEvent {
  const LumenCancelThanksScreenEvent();
}

final class LumenCancelThanksScreenFinishEvent
    extends LumenCancelThanksScreenEvent {
  const LumenCancelThanksScreenFinishEvent();
}

final _lumenCancelThanksScreenEvents =
    SurfaceScreenEventContract<LumenCancelThanksScreenEvent>.generated(
  hash:
      "sha256:ca846c32a23d2d98fb3ca253fc69fb1ccef2fa2ee9fa5397947d5e5c2e03bc31",
  decodeValidated: _decodeValidatedLumenCancelThanksScreenEvent,
);

final _lumenCancelThanksScreenProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.survey,
  slug: "lumen_cancel_thanks",
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 6,
    requiredLibraries: const [],
  ),
  eventSchemaJson:
      "{\"schemaVersion\":1,\"events\":[{\"id\":\"finish\",\"arguments\":{\"encoding\":\"none\"}}]}",
  bundle: SurfaceScreenBundleLocator(
    assetKey: "assets/restage/bundles/lib/surfaces/lumen_cancel.rsbundle",
    packageName: "restage_example",
    authoredLibraryPath: "lib/surfaces/lumen_cancel.dart",
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.rfw",
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 14841,
        sha256:
            "sha256:5814bceec07efdaa4eddc5204a3c7163b26cd864b5d2a96da4d4bd00166aa14a",
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            "assets/survey/screens/measurement/79821ca45fbefc0b/lumen_cancel_thanks.capability.json",
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 141,
        sha256:
            "sha256:5c74693663b86d14f2a0feac4cada505bb953e20c389d42bda7ead1e937c98d5",
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Positioned': buildPositioned,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Stack': buildStack,
        'Text': buildText,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf738: IconData(0xf738, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
);

final lumenCancelThanksScreenRef = SurfaceScreenRef<
    LumenCancelThanksScreenEvent>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _lumenCancelThanksScreenProvenance,
  eventContract: _lumenCancelThanksScreenEvents,
  measurementPublicationDraftDigest:
      "47e8e690662135eafef454babef0922e40d3850ec580f3f5690d5bc417d8cba0",
);

LumenCancelThanksScreenEvent _decodeValidatedLumenCancelThanksScreenEvent(
  String name,
  Map<String, Object?> arguments,
) {
  switch (name) {
    case "finish":
      return const LumenCancelThanksScreenFinishEvent();
  }
  throw FormatException(
      "Invalid LumenCancelThanksScreen event \"" + name + "\".");
}

final class LumenCancelThanksScreenSurface extends StatelessWidget {
  const LumenCancelThanksScreenSurface({
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
  });

  final ValueChanged<LumenCancelThanksScreenEvent>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return RestageScreen<LumenCancelThanksScreenEvent>(
      screen: lumenCancelThanksScreenRef,
      unavailable: SurfaceScreenUnavailablePolicy.fallback(
        builder: (context, error) => LumenCancelThanksScreen(),
      ),
      onEvent: onEvent,
      resolver: resolver,
      onUnavailable: onUnavailable,
      loadingBuilder: loadingBuilder,
    );
  }
}
