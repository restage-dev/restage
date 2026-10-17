# restage_compiler_core

[![license](https://img.shields.io/badge/license-FSL--1.1--ALv2-blue.svg)](LICENSE)

The pure-Dart core of the Restage surface compiler. It resolves which catalog
widget each constructor in a compiled RFW library came from, derives the
client capabilities a surface needs, and projects what a published surface
asks of the app that hosts it.

Part of [Restage](https://restage.dev), server-driven UI for Flutter. It has no
`analyzer`, `build` or `dart:io` dependency, so it runs anywhere Dart runs,
including the web. Apps don't depend on it;
[restage_codegen](https://pub.dev/packages/restage_codegen) does.

## License

FSL-1.1-ALv2. See [LICENSE](LICENSE).
