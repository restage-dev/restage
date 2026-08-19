import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';

/// Compares [left] and [right] by ascending UTF-8 path-byte order.
///
/// This is the canonical ordering for the whole generated-output artifact
/// family: bundle entries, the physical output locator
/// (`restage.outputs.json`), and CLI publication validation all sort and
/// verify logical paths this way, so an index and the bundles it locates
/// always agree with each other.
///
/// It compares UTF-8 encoded bytes, not UTF-16 code units, so it is **not**
/// the same as [String]'s default `compareTo`. A character outside the
/// Basic Multilingual Plane is encoded in UTF-16 as a surrogate pair whose
/// leading unit (`U+D800`–`U+DBFF`) is numerically lower than many
/// single-unit Basic Multilingual Plane characters, even though the
/// supplementary character it represents has a higher code point — so
/// code-unit comparison and byte comparison can disagree. This function
/// always follows byte order.
///
/// Returns a negative number if [left] sorts before [right], zero if they
/// are equal, and a positive number if [left] sorts after [right]. Throws a
/// [FormatException] if either string contains an unpaired UTF-16
/// surrogate, since that cannot be encoded as well-formed UTF-8.
int compareGeneratedOutputPaths(String left, String right) =>
    SurfaceContractJson.compareUtf8(left, right);
