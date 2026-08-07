/// The default render-bundle channel.
const renderBundleMainChannel = 'main';

/// Maximum length of the handle portion of a user render-bundle channel.
const renderBundleUserHandleMaxLength = 32;

final RegExp _userChannelPattern = RegExp(
  r'^user/[a-z0-9](?:[a-z0-9_-]{0,30}[a-z0-9])?$',
);

/// Whether [channel] is a canonical render-bundle channel.
///
/// Accepted values are [renderBundleMainChannel] and `user/<handle>`, where
/// the handle is 1–32 lowercase ASCII alphanumeric characters with `-` or `_`
/// allowed only between alphanumeric characters.
bool isValidRenderBundleChannel(String channel) {
  if (channel == renderBundleMainChannel) return true;
  return _userChannelPattern.hasMatch(channel);
}

/// Returns [channel] when it is canonical.
///
/// Throws a [FormatException] before callers perform any external work when
/// the channel is invalid.
String validateRenderBundleChannel(String channel) {
  if (!isValidRenderBundleChannel(channel)) {
    throw const FormatException('Invalid render-bundle channel.');
  }
  return channel;
}
