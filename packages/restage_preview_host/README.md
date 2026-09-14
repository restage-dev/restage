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

## Preview tooling only

This host is for preview and authoring tools, not for an application you ship.
A preview renders content the tool cannot know ahead of time, so the host
carries every built-in widget and adds every built-in icon to the process-wide
icon table. Embedding it in a shipped application therefore keeps the whole
built-in catalog and both icon fonts in that application's build, which is
exactly what a shipped application should avoid.

Adding icons never changes the meaning of an entry the embedding application
already installed, so a tool that embeds the host keeps its own icons.

This package is pre-release and is not currently published.
