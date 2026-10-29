/// Carries the canonical forms computed in one isolate back to another, so a
/// value decoded off the isolate that draws frames is not encoded again.
library;

export 'src/canonical.dart'
    show CanonicalForms, adoptCanonicalForms, recordCanonicalForms;
