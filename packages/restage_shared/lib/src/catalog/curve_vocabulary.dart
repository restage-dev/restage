/// The supported animation-curve wire vocabulary — the curve member names a
/// `curve`-typed catalog property slot may carry on the wire.
///
/// Single source of truth shared by three surfaces: the runtime decoder (which
/// maps each name to its concrete curve), the build-time catalog validator
/// (which rejects any curve string outside this set with an actionable
/// diagnostic), and the editor's curve dropdown. Pinning all three to one list
/// is what stops a curve name no decoder can resolve from silently falling back
/// to the framework default in a shipped blob.
///
/// Once a blob referencing a curve name ships, this vocabulary is
/// **additive-only**: appending a name is safe (a blob that does not reference
/// it is unaffected), but renaming or removing one is a wire break — a live
/// blob carrying the old name would silently fall back to the framework
/// default. The order is the editor dropdown's presentation order and is not
/// significant to the wire.
const List<String> kSupportedCurveNames = [
  'linear',
  'decelerate',
  'fastLinearToSlowEaseIn',
  'ease',
  'easeIn',
  'easeInToLinear',
  'easeInSine',
  'easeInQuad',
  'easeInCubic',
  'easeInQuart',
  'easeInQuint',
  'easeInExpo',
  'easeInCirc',
  'easeInBack',
  'easeOut',
  'linearToEaseOut',
  'easeOutSine',
  'easeOutQuad',
  'easeOutCubic',
  'easeOutQuart',
  'easeOutQuint',
  'easeOutExpo',
  'easeOutCirc',
  'easeOutBack',
  'easeInOut',
  'easeInOutSine',
  'easeInOutQuad',
  'easeInOutCubic',
  'easeInOutCubicEmphasized',
  'easeInOutQuart',
  'easeInOutQuint',
  'easeInOutExpo',
  'easeInOutCirc',
  'easeInOutBack',
  'fastOutSlowIn',
  'slowMiddle',
  'bounceIn',
  'bounceOut',
  'bounceInOut',
  'elasticIn',
  'elasticOut',
  'elasticInOut',
];
