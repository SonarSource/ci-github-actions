# Release channel pointer schema

JSON Schema for the per-channel pointer JSON file written by the `update-release-channel` GitHub Action to
`s3://downloads-cdn-eu-central-1-prod/<prefix>/<product>/<channel>.json`.

The action also writes a sibling plain-text file at
`s3://downloads-cdn-eu-central-1-prod/<prefix>/<product>/<channel>.version` containing only the version string. That
file is not covered by this JSON schema.

## Versioning

The schema version lives in the **filename** (`v1.json`, `v2.json`, ...) and in lockstep in the `schemaVersion` field
inside the JSON document.

A new file (e.g. `v2.json`) is introduced **only** when existing fields are removed, renamed, or changed in a
non-backwards-compatible way. Additive changes (new optional fields) ship as updates to `v1.json` — consumers MUST
ignore unknown fields.

## v1 fields

| Field           | Type    | Required | Description                                                              |
| --------------- | ------- | -------- | ------------------------------------------------------------------------ |
| `schemaVersion` | integer | yes      | Const `1`.                                                               |
| `version`       | string  | yes      | Currently published version on this channel (e.g. `0.9.0.977`).          |
| `updatedAt`     | string  | yes      | ISO-8601 UTC timestamp at which the channel was promoted to `version`.   |

`additionalProperties: true` — unknown fields are accepted and MUST be ignored by older consumers.
