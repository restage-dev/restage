# restage_measurement_schema

[![pub package](https://img.shields.io/pub/v/restage_measurement_schema.svg)](https://pub.dev/packages/restage_measurement_schema) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

Shared pure-Dart data types for measurement: manifests, observations, metric
results, and experiment and policy descriptions. Each type has a stable byte
encoding and hash, so every program that reads it agrees on the same value.

The package only describes data. It doesn't collect events, compute metrics or
results, assign experiment variants, store data, or send it anywhere.

## Terms

A **surface publication** ("publication" for short) is one published, served
version of a surface. It names, by digest, the manifest, the uploaded files,
and the draft it was built from. All publications of one surface form a
**family**, and the record of which publication replaced which is its
**lineage**.

## Linking a signed-in user

The package defines the challenge, request, receipt, and failure types for
linking a signed-in user to measurement. Sign-in proofs go only into requests.
Receipts never include external ids, keys, or tokens.

## Identifiers

`OrganizationId`, `ApplicationId`, `EnvironmentTargetId`, and
`NamedEnvironmentId` are positive integers, encoded as bare JSON numbers.
Measurement's own identifiers are length-limited typed strings.

`MeasurementPointOccurrenceIdentityV1` lists the fields that make up a
measurement point's `occurrenceId`.

## Number limits

JSON integers stay within JavaScript's exact range, `-9007199254740991` to
`9007199254740991`, so the Dart VM, Wasm, and JavaScript all hash the same
bytes. Larger exact values are decimal strings of up to 78 digits, with an
optional scale from 0 to 18. Leading zeros, `+` signs, and negative zero are
rejected.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
