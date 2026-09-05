/// The `data.device.*` shipped-blob contract — the dot-paths a transpiled
/// surface may reference, and that the SDK publishes into a rendered
/// surface's `DynamicContent`.
///
/// Shared by the SDK's device publisher and the codegen-side contract
/// validation. The contract is **additive-only**: a rename, removal, or retype
/// would break a live blob.
library;

/// Every in-contract path in the `data.device.*` namespace. `countryCode` is
/// omitted when the ambient locale carries no country. The `safeArea*` paths
/// carry `MediaQueryData.padding`, the `viewPadding*` paths carry
/// `MediaQueryData.viewPadding`, both at the surface's mount point.
const Set<String> kDeviceContractPaths = {
  'locale',
  'languageCode',
  'countryCode',
  'platform',
  'screenWidth',
  'screenHeight',
  'shortestSide',
  'longestSide',
  'orientation',
  'pixelRatio',
  'safeAreaTop',
  'safeAreaBottom',
  'safeAreaLeft',
  'safeAreaRight',
  'viewPaddingTop',
  'viewPaddingBottom',
  'viewPaddingLeft',
  'viewPaddingRight',
};

/// The wire-value kind a device contract path publishes, paired with every
/// path in [kDeviceContractPathKinds].
enum DeviceContractValueKind {
  /// A double-valued measurement — a screen dimension, an inset, a ratio.
  size,

  /// A string token — a locale subtag, a platform identifier, an
  /// orientation.
  token,
}

/// Every in-contract path mapped to the [DeviceContractValueKind] it
/// publishes. Keys are exactly [kDeviceContractPaths].
final Map<String, DeviceContractValueKind> kDeviceContractPathKinds =
    Map.unmodifiable(<String, DeviceContractValueKind>{
  'locale': DeviceContractValueKind.token,
  'languageCode': DeviceContractValueKind.token,
  'countryCode': DeviceContractValueKind.token,
  'platform': DeviceContractValueKind.token,
  'screenWidth': DeviceContractValueKind.size,
  'screenHeight': DeviceContractValueKind.size,
  'shortestSide': DeviceContractValueKind.size,
  'longestSide': DeviceContractValueKind.size,
  'orientation': DeviceContractValueKind.token,
  'pixelRatio': DeviceContractValueKind.size,
  'safeAreaTop': DeviceContractValueKind.size,
  'safeAreaBottom': DeviceContractValueKind.size,
  'safeAreaLeft': DeviceContractValueKind.size,
  'safeAreaRight': DeviceContractValueKind.size,
  'viewPaddingTop': DeviceContractValueKind.size,
  'viewPaddingBottom': DeviceContractValueKind.size,
  'viewPaddingLeft': DeviceContractValueKind.size,
  'viewPaddingRight': DeviceContractValueKind.size,
});
