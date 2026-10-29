import 'network_access_check_stub.dart'
    if (dart.library.io) 'network_access_check_io.dart' as implementation;

/// Says once per process when a failed request came from an app that may
/// not open network sockets, as an Android build without the INTERNET
/// permission.
void noteRequestFailedBeforeResponse() =>
    implementation.noteRequestFailedBeforeResponse();
