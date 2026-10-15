import 'render_core.dart';

/// Creates the browser transport used by an isolated render bundle.
///
/// Non-browser platforms fail closed because they cannot authenticate a
/// parent-window source.
RenderMessageTransport createBrowserRenderMessageTransport({
  required String parentOrigin,
}) {
  throw UnsupportedError(
    'The browser render message transport is available only on the web.',
  );
}
