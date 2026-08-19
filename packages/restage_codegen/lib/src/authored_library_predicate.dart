import 'package:build/build.dart';
import 'package:restage_codegen/src/surface_publication/output_placement.dart';

/// Whether [asset] is an authored Dart library candidate for Restage source
/// discovery.
///
/// The resolver remains responsible for rejecting Dart `part` files. This
/// predicate attaches product meaning to exactly one directory name — the
/// reserved generated-output collection directory, which is never an input.
/// An authored source may otherwise live anywhere beneath `lib/`, including a
/// directory literally named `generated`.
bool isAuthoredDartLibraryAsset(AssetId asset) =>
    asset.path.startsWith('lib/') &&
    asset.path.endsWith('.dart') &&
    !asset.path.endsWith('.g.dart') &&
    !asset.path.endsWith('.stories.dart') &&
    !isReservedRestageGeneratedPath(asset.path);
