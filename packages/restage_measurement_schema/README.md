# restage_measurement_schema

[![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Deterministic pure-Dart contracts shared by measurement producers and
consumers. The package defines canonical bytes and hashes, measurement
manifests, semantic observations, descriptive metric results, and inert
experiment and policy descriptions.

The package does not collect events, evaluate metrics, assign treatments,
perform statistical inference, persist data, or transport payloads.

## Vocabulary

**Measurement**, capitalised, names the capability these contracts serve:
defining what a surface should record, collecting it, and describing the
result. Lower-case "measurement" keeps its ordinary English sense.

A **surface publication** — "publication" for short — is the versioned unit in
which a surface is published and served. One publication names, by digest, the
selected manifest, the assembled upload, the declared artifact closure, and the
draft they were generated from. The publications of a single surface belong to
a **family**, and the ordered record of which publication replaced which is
that family's **lineage**.

## Governed subject contracts

The package also defines canonical challenge, request, receipt, and failure
vocabulary for explicit governed Measurement operations. Raw host assertion
bytes and authenticated evidence are request inputs only. Receipts expose the
operation, policy and purpose references, subject kind, generation, and coarse
failure output without external identifiers, keys, or bearer material.

These types describe a public contract; they do not create subject authority,
persistence, or transport behavior.

## Identity boundaries

`OrganizationId`, `ApplicationId`, `EnvironmentTargetId`, and
`NamedEnvironmentId` preserve the existing positive integer authorities from
the control plane. They encode as bare JSON integers and are capped at the
portable exact bound below; they are not slugs or newly minted semantic IDs.
New measurement-owned semantic IDs remain bounded typed strings.

Source event identity is the exact public callback property name already
admitted by catalog compilation. It remains distinct from optional normalized
interaction metadata and supports the compiler's public ASCII Dart member
grammar, including legal `$` characters. Generated Dart symbols use that same
boundary and reject hard keywords and private names.

`MeasurementPointOccurrenceIdentityV1` is the explicit point-ID preimage. It
contains only schema version, published surface revision, artifact graph,
artifact, artifact-occurrence edge, artifact content, canonical node token, and
the exact source event or synthetic presentation slot. Target, lineage, display,
normalization, privacy, semantic-value, and collection fields remain record
metadata and do not change `occurrenceId`.

## Canonical number bounds

Bare JSON integers are limited to JavaScript's portable exact range,
`-9007199254740991` through `9007199254740991`, so VM, Wasm, and JavaScript
consumers hash the same value bytes. Wider exact quantities use normalized
decimal-string coefficients capped at 78 digits, enough for signed 256-bit-scale
values while bounding parser and payload work. Scaled decimals pair that
coefficient with an explicit scale from 0 through 18. Leading zeroes, `+` signs,
negative zero, and larger coefficients or scales are not canonical.
