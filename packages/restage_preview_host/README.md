# restage_preview_host

A transport-neutral Flutter host for rendering RFW bundles. It provides a
versioned message protocol, capability manifests, a provider-driven in-process
preview surface, and a raw render surface for tools that need an isolated
preview runtime.

Bundles with a PNG snapshot handler advertise the additive `snapshot`
capability in their ready handshake. Shells resolve it through
`surfaceSnapshotProviderFor`; a null result means the peer is render-only and
must retain its normal live-render fallback. Legacy peers continue rendering
without sending or rejecting unsupported snapshot traffic.

This package is pre-release and is not currently published.
