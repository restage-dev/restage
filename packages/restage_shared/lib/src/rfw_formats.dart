// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
// Vendored from package:rfw 1.1.3 (lib/formats.dart). Upstream license:
// src/rfw_formats/LICENSE-rfw (BSD-3-Clause).

/// # Remote Flutter Widgets — formats only (vendored).
///
/// Pure-Dart subset of the [rfw](https://pub.dev/packages/rfw) library that
/// does not depend on Flutter. Lets pure-Dart code parse and (de)encode
/// `.rfwtxt`/`.rfw` files without pulling in the Flutter SDK as a transitive
/// dependency (rfw's Flutter SDK dependency would otherwise block resolution).
///
/// Mirrors the exports of `package:rfw/formats.dart`:
///
///  * `parseLibraryFile` and `parseDataFile`, for parsing Remote Flutter
///    Widgets text library and data files respectively.
///  * `encodeLibraryBlob` and `encodeDataBlob`, for encoding the output of
///    the previous methods into binary form.
///  * `decodeLibraryBlob` and `decodeDataBlob`, which decode those binary
///    forms.
///  * The `DynamicMap`, `DynamicList`, and `BlobNode` types (and
///    subclasses), which are used to represent the data model and remote
///    widget libraries in memory.
library;

export 'rfw_formats/binary.dart';
export 'rfw_formats/model.dart';
export 'rfw_formats/text.dart';
