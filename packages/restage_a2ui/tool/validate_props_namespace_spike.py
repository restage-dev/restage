#!/usr/bin/env python3
"""Check the generated required-props layout against the upstream A2UI schemas.

Takes a local checkout of the A2UI specification (https://github.com/google/genui)
as its one argument, and refuses to run unless that checkout sits at the commit
pinned below, so a schema change upstream is a loud failure rather than a silent
re-baseline.

    python3 tool/validate_props_namespace_spike.py /path/to/genui

Not part of the published package; see .pubignore.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


EXPECTED_UPSTREAM_COMMIT = "ec97cb0d7499932e67003ffe5b709a3db7e7033a"


def dynamic_ref(version: str, name: str) -> dict[str, str]:
    return {
        "$ref": f"https://a2ui.org/specification/{version}/common_types.json#/$defs/{name}"
    }


def component_schema(version: str) -> dict[str, object]:
    props: dict[str, object] = {
        "type": "object",
        "properties": {
            "id": {"type": "string"},
            "component": {"type": "string"},
            "catalogId": {"type": "string"},
            "props": {"type": "string"},
            "literalValue": dynamic_ref(version, "DynamicString"),
            "pathValue": dynamic_ref(version, "DynamicString"),
            "callValue": dynamic_ref(version, "DynamicString"),
            "node": {
                "type": "object",
                "properties": {
                    "label": {"type": "string"},
                    "child": {
                        "anyOf": [
                            {
                                "$ref": "#/components/CustomerCard/allOf/"
                                + ("2" if version == "v0_9" else "1")
                                + "/properties/props/properties/node"
                            },
                            {"type": "null"},
                        ]
                    },
                },
                "required": ["label"],
            },
            "counts": {
                "type": "object",
                "additionalProperties": {"type": "integer"},
            },
            "meta": {
                "type": "object",
                "properties": {
                    "label": {"type": "string"},
                    "count": {"type": "integer"},
                },
                "required": ["label", "count"],
            },
            "leading": dynamic_ref(version, "ComponentId"),
            "children": dynamic_ref(version, "ChildList"),
            "enabled": dynamic_ref(version, "DynamicBoolean"),
        },
        "required": [
            "id",
            "component",
            "catalogId",
            "props",
            "literalValue",
            "pathValue",
            "callValue",
            "node",
            "counts",
            "meta",
            "leading",
            "children",
            "enabled",
        ],
        "additionalProperties": False,
    }
    overlays: list[dict[str, object]] = [
        dynamic_ref(version, "ComponentCommon"),
    ]
    if version == "v0_9":
        overlays.append({"$ref": "#/$defs/CatalogComponentCommon"})
    overlays.append(
        {
            "type": "object",
            "properties": {
                "component": {"const": "CustomerCard"},
                "props": props,
            },
            "required": ["component", "props"],
        }
    )
    return {
        "type": "object",
        "allOf": overlays,
        "unevaluatedProperties": False,
    }


def leaf_schema(version: str) -> dict[str, object]:
    overlays: list[dict[str, object]] = [dynamic_ref(version, "ComponentCommon")]
    if version == "v0_9":
        overlays.append({"$ref": "#/$defs/CatalogComponentCommon"})
    overlays.append(
        {
            "type": "object",
            "properties": {
                "component": {"const": "SpikeLeaf"},
                "props": {
                    "type": "object",
                    "properties": {"label": {"type": "string"}},
                    "required": ["label"],
                    "additionalProperties": False,
                },
            },
            "required": ["component", "props"],
        }
    )
    return {
        "type": "object",
        "allOf": overlays,
        "unevaluatedProperties": False,
    }


def catalog(version: str) -> dict[str, object]:
    catalog_id = f"https://a2ui.org/specification/{version}/catalog.json"
    result: dict[str, object] = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": catalog_id,
        "title": "Restage required props feasibility catalog",
        "catalogId": catalog_id,
        "components": {
            "CustomerCard": component_schema(version),
            "SpikeLeaf": leaf_schema(version),
        },
        "functions": {},
        "$defs": {
            "anyComponent": {
                "oneOf": [
                    {"$ref": "#/components/CustomerCard"},
                    {"$ref": "#/components/SpikeLeaf"},
                ]
            },
            "anyFunction": {"type": "object"},
        },
    }
    if version == "v0_9":
        result["description"] = "A2UI v0.9.1 feasibility catalog."
        result["$defs"]["CatalogComponentCommon"] = {  # type: ignore[index]
            "type": "object"
        }
        result["$defs"]["theme"] = {  # type: ignore[index]
            "type": "object",
            "additionalProperties": True,
        }
    else:
        result["protocolVersion"] = "1.0"
    return result


def payload(version: str) -> dict[str, object]:
    component: dict[str, object] = {
        "id": "root",
        "component": "CustomerCard",
        "props": {
            "id": "customer-id",
            "component": "customer-component",
            "catalogId": "customer-catalog",
            "props": "customer-props",
            "literalValue": "literal",
            "pathValue": {"path": "/boundLabel"},
            "callValue": {
                "call": "spikeString",
                **({"returnType": "string"} if version == "v0_9" else {}),
            },
            "node": {
                "label": "root-node",
                "child": {"label": "child-node"},
            },
            "counts": {"a": 1, "b": 2},
            "meta": {"label": "record", "count": 3},
            "leading": "leading",
            "children": ["first", "second"],
            "enabled": {"path": "/enabled"},
        },
    }
    if version == "v1_0":
        component["catalogId"] = "https://a2ui.org/specification/v1_0/catalog.json"
    return {
        "version": "v0.9.1" if version == "v0_9" else "v1.0",
        "updateComponents": {
            "surfaceId": "props-spike-surface",
            "components": [
                component,
                {
                    "id": "leading",
                    "component": "SpikeLeaf",
                    "props": {"label": "leading"},
                },
                {
                    "id": "first",
                    "component": "SpikeLeaf",
                    "props": {"label": "first"},
                },
                {
                    "id": "second",
                    "component": "SpikeLeaf",
                    "props": {"label": "second"},
                },
            ],
        },
    }


def run_ajv(schema: Path, data: Path, references: list[Path]) -> None:
    command = [
        "npx",
        "--yes",
        "-p",
        "ajv-cli@5",
        "-p",
        "ajv-formats@3",
        "ajv",
        "validate",
        "-s",
        str(schema),
        "-d",
        str(data),
        "--spec=draft2020",
        "--strict=false",
        "-c",
        "ajv-formats",
    ]
    for reference in references:
        if reference != schema:
            command.extend(["-r", str(reference)])
    subprocess.run(command, check=True)


def validate_version(upstream: Path, version: str) -> None:
    source = upstream / "specification" / ("v0_9_1" if version == "v0_9" else "v1_0")
    with tempfile.TemporaryDirectory(prefix=f"restage-a2ui-{version}-") as raw_tmp:
        tmp = Path(raw_tmp)
        shutil.copytree(source / "json", tmp / "json")
        generated_catalog = tmp / "catalog.json"
        generated_payload = tmp / "payload.json"
        generated_catalog.write_text(json.dumps(catalog(version), indent=2) + "\n")
        generated_payload.write_text(json.dumps(payload(version), indent=2) + "\n")
        common = tmp / "json" / "common_types.json"
        message = tmp / "json" / (
            "server_to_client.json" if version == "v0_9" else "agent_to_renderer.json"
        )
        run_ajv(message, generated_payload, [common, generated_catalog])
        if version == "v1_0":
            run_ajv(
                tmp / "json" / "catalog_definition.json",
                generated_catalog,
                [common],
            )
    print(f"PASS official {version} required-props payload")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream", type=Path)
    args = parser.parse_args()
    commit = subprocess.run(
        ["git", "-C", str(args.upstream), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if commit != EXPECTED_UPSTREAM_COMMIT:
        raise SystemExit(
            f"expected A2UI {EXPECTED_UPSTREAM_COMMIT}, found {commit}"
        )
    validate_version(args.upstream, "v0_9")
    validate_version(args.upstream, "v1_0")
    print(f"PASS pinned upstream commit {commit}")


if __name__ == "__main__":
    main()
