# restage_render_host

[![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

Renders a Flutter app's own widgets for a Restage preview.

`restage build push` builds a small web bundle from your app: your widgets, the
Restage runtime, and this package. A preview loads that bundle and asks it to
draw a surface, so the preview runs your own code.

You don't add this package to your app. The CLI adds it to the bundle it
generates, at the version that matches the `restage` your app resolves.

## License

FSL-1.1-ALv2. See [LICENSE](LICENSE).
