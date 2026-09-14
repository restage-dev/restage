# Frozen factory oracle

These three Dart files are byte-for-byte snapshots of the catalog registration
outputs before factory compaction.
The runtime differential test feeds both versions through real RFW DataSource
objects and compares widget fields, live data updates, and typed event payloads.

These are independent compatibility fixtures, not generated build outputs.
Do not regenerate or copy current registrations over them to make a test pass.
A deliberate future catalog contract change must review and document any oracle
update alongside the behavior change.

Original SHA-256 digests:

- Core: `afb89cb0821e2c1b69851e3431e8d920ce6b4b02e3e383b823fd99592e8b3bc7`
- Material: `2e6f8796c45f2ee593574ae42a986adb2d1887b90a3eb074cc684c636e260a1b`
- Cupertino: `727a4f9d3ecdeee1231d3e12b1e35f3334196cd78114ad7ba92ee979fe8978cc`
