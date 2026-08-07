# restage_preview_harness

A minimal Flutter entrypoint that connects generated customer widget
registrations to `restage_preview_host` and renders incoming RFW bundles.

The browser adapter accepts messages only from an explicitly configured parent
origin and sends replies to that same origin. Built render bundles select their
root from the RFW declarations: one `main` declaration takes precedence, with a
single legacy `Paywall` declaration supported when `main` is absent.

Customer bundle entrypoints provide their generated registration function,
canonical catalog JSON, Flutter engine facts, and non-secret parent origin at
build time. Credentials and application state are not harness inputs.

The harness advertises the optional `snapshot` protocol capability and can
capture the latest settled canonical root as a bounded PNG. Snapshot requests
carry only the settled render epoch and authored root path; credentials and
dashboard state remain outside the seam.

This package is pre-release and is not currently published.
