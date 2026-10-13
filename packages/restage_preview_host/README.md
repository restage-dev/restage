# restage_preview_host

[![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

A Flutter host for rendering RFW bundles, independent of how messages reach it.
It provides a versioned message protocol, capability manifests, an in-process
preview surface, and a raw render surface for tools that need a separate
preview runtime.

Bundles declare PNG snapshot support when they connect.
`surfaceSnapshotProviderFor` returns null for bundles without that support;
they continue to render live.

## For preview tools only

This host is for preview and authoring tools. Don't ship it in an app: a
preview can't know ahead of time what it will render, so the host carries every
built-in widget and icon, and pulls the whole catalog and both icon fonts into
your build.

The host never overrides icons your tool already registered.

This package is not published yet.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
