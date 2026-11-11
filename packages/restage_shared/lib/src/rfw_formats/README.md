# rfw formats codec

The `.dart` files here are copies of a pure-Dart formats library derived from rfw
2.0.0's `lib/src/dart/`, kept identical to their source. They let pure-Dart code,
such as servers and build tools, parse and encode `.rfwtxt` and `.rfw` without a
Flutter dependency.

Don't edit them here; change the source and copy the files over. These
files keep upstream's formatting, so they're excluded from `dart format`.

`packages/restage_core/test/rfw_wire_parity_test.dart` checks that blobs encoded
here decode identically in the Flutter runtime, and the reverse.

`LICENSE-rfw` is the upstream BSD-3-Clause license for these files.
