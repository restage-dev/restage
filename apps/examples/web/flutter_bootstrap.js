{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Let Flutter select Skwasm or the CanvasKit fallback for this browser.
    canvasKitBaseUrl: 'canvaskit/',
    fontFallbackBaseUrl: 'assets/fonts/fallback/',
  },
});
