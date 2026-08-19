# Explicit-authoring corpus

This directory is a source corpus for the explicit-authoring compiler tests. The test
harness mounts each scenario into a virtual `apps_examples` package before
running the production builders; the files are not an application package and
must not be emitted as package artifacts.

The `old` and `new` trees in paired scenarios are deliberately equivalent
authoring. Their canonical flow JSON, RFW text/binary, capability sidecars,
and descriptor/artifact identity are compared by the executable parity tests.
The tests never regenerate or overwrite the pre-change frozen oracle.

The corpus covers linear, branching typed-state, converging completion,
screen-containing cycle/forward-reference, host action, subflow, embedded
paywall, both `@FlowGraph` forms, neutral and categorized screen reuse,
`Surface.general` standalone/flow ownership, authoritative moved IDs,
colocated explicit sources, deprecated compatibility spellings, and the
duplicate/mismatch/terminal diagnostics that must fail closed.
