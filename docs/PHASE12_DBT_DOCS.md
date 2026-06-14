# Phase 12: dbt Documentation and Lineage

## Goal

Generate a searchable dbt documentation site, capture lineage/model screenshots for the portfolio, and add a human-readable data dictionary for the analytics mart.

## Completion Summary

Phase 12 completes the documentation layer for the GitHub Analytics Pipeline:

- Added a repo-local dbt docs automation script: `scripts/generate_and_capture_dbt_docs.ps1`
- Added dbt package declaration for `dbt_utils`: `dbt/github_dbt/packages.yml`
- Added the portfolio data dictionary: `docs/DATA_DICTIONARY.md`
- Standardized dbt docs output screenshots under `docs/screenshots/`
- Documented the correct repo-local profile flow with `--profiles-dir dbt`

## Why This Phase Matters

dbt documentation turns the transformation layer into an inspectable contract. Reviewers can see:

- Source-to-mart lineage
- Model descriptions and ownership metadata
- Column descriptions and tests
- Relationship tests between facts and dimensions
- Freshness rules for raw sources

## dbt Docs Artifacts

When the automation script succeeds, dbt writes:

| Artifact | Location | Purpose |
|----------|----------|---------|
| `manifest.json` | `dbt/github_dbt/target/manifest.json` | Model graph, configs, refs, tests, docs metadata |
| `catalog.json` | `dbt/github_dbt/target/catalog.json` | Warehouse-backed column metadata in full mode; empty catalog stub in metadata-only mode |
| `index.html` | `dbt/github_dbt/target/index.html` | Static dbt docs application |
| Lineage screenshot | `docs/screenshots/dbt-lineage.png` | Portfolio lineage image |
| Fact model screenshot | `docs/screenshots/dbt-fact_events.png` | `fact_events` docs page |
| Actor model screenshot | `docs/screenshots/dbt-dim_actor.png` | `dim_actor` docs page |

## Important Fixes

### Repo-local dbt profile

The dbt project uses this profile name:

```yaml
profile: github_dbt
```

The repo already includes the matching profile at:

```text
dbt/profiles.yml
```

Earlier docs-generation attempts failed because dbt searched the default user profile directory instead of the repo-local profile directory. The corrected commands pass:

```powershell
--profiles-dir dbt
```

### dbt package dependency

The mart models call:

```sql
dbt_utils.generate_surrogate_key(...)
```

Phase 12 now includes `dbt/github_dbt/packages.yml`, so `dbt deps` can install `dbt_utils` before docs generation.

### Environment variables

The helper script imports `.env` into the current PowerShell process before running dbt. This keeps credentials out of docs while satisfying the `env_var(...)` calls in `dbt/profiles.yml`.

## One-command Workflow

Run from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate_and_capture_dbt_docs.ps1
```

The script performs:

1. Resolve repo root, dbt project path, and screenshot output folder.
2. Load `.env` values into process environment variables.
3. Locate dbt from `.venv`, `venv`, common Python install paths, or `PATH`.
4. Run `dbt deps --profiles-dir dbt` when `packages.yml` exists.
5. Run `dbt debug --profiles-dir dbt`.
6. Run `dbt docs generate --profiles-dir dbt`.
7. Capture screenshots from `target/static_index.html` using headless Chrome or Edge.
8. Fall back to `dbt docs serve` only if `static_index.html` is unavailable.
9. Stop the docs server when the fallback path is used.

## Local Metadata-only Workflow

If the Snowflake account identifier is not ready yet, generate a local docs site with an empty warehouse catalog:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate_and_capture_dbt_docs.ps1 -EmptyCatalog
```

This still creates the manifest, static docs site, lineage graph, model pages, and screenshots. It does not include live Snowflake catalog metadata such as database column types fetched from information schema.

In this mode the script runs `dbt parse` before `dbt docs generate --empty-catalog --no-compile --no-populate-cache` so `target/manifest.json` exists without opening a Snowflake session.

This workflow has been completed locally. The generated `catalog.json` is intentionally empty because it was produced with `--empty-catalog`.

## Manual Workflow

Use this when debugging one step at a time:

```powershell
# From repository root
$env:DBT_PROFILES_DIR = "dbt"
cd dbt/github_dbt

dbt deps --profiles-dir .. 
dbt debug --profiles-dir ..
dbt docs generate --profiles-dir ..
dbt docs serve --profiles-dir .. --port 8000 --no-browser
```

Open:

```text
http://localhost:8000
```

Recommended screenshot routes:

```text
http://localhost:8000/#!/overview
http://localhost:8000/#!/model/model.github_dbt.fact_events
http://localhost:8000/#!/model/model.github_dbt.dim_actor
```

## Screenshot Checklist

Save these files in `docs/screenshots/`:

- `dbt-lineage.png`
- `dbt-fact_events.png`
- `dbt-dim_actor.png`

The screenshots folder is intentionally used for documentation artifacts only. dbt runtime outputs remain in `dbt/github_dbt/target/`.

## Model Coverage

The current dbt documentation graph covers:

| Layer | Models |
|-------|--------|
| Sources | `github_archive.github_events`, `github_archive.load_history` |
| Staging | `stg_github_events`, `stg_actors`, `stg_repositories`, `stg_event_types` |
| Dimensions | `dim_actor`, `dim_repository`, `dim_event_type` |
| Facts | `fact_events` |
| Tests | Source freshness, not-null, unique, accepted-values, relationships, and custom SQL tests |

## Data Dictionary

The business-facing dictionary is available at:

```text
docs/DATA_DICTIONARY.md
```

It documents the source tables, staging models, mart models, business glossary, and core analytics questions.

## Troubleshooting

### `Could not find profile named 'github_dbt'`

Run dbt with the repo-local profiles directory:

```powershell
dbt debug --profiles-dir ..
```

when inside `dbt/github_dbt`, or:

```powershell
dbt debug --profiles-dir dbt --project-dir dbt/github_dbt
```

from the repo root.

### `dbt_utils` macro not found

Install dbt dependencies:

```powershell
cd dbt/github_dbt
dbt deps --profiles-dir ..
```

### Snowflake connection fails

Check that the following environment variables are available in the current shell:

```text
SNOWFLAKE_ACCOUNT
SNOWFLAKE_USER
SNOWFLAKE_PASSWORD
SNOWFLAKE_ROLE
SNOWFLAKE_WAREHOUSE
```

The automation script loads these from `.env`.

If Snowflake returns `404 Not Found` for the login request, update `SNOWFLAKE_ACCOUNT` to the full account identifier from the Snowflake account URL. Depending on the Snowflake account, this is often either an org-account name or an account locator with region/cloud suffix.

### Screenshot capture fails

Install Google Chrome or Microsoft Edge, then rerun:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/generate_and_capture_dbt_docs.ps1
```

## Validation Checklist

- [x] Phase 12 runbook written
- [x] Data dictionary added
- [x] dbt package dependency declared
- [x] Helper script uses repo-local `profiles.yml`
- [x] Helper script captures lineage and model screenshots
- [x] `dbt deps` completed locally
- [x] Metadata-only `dbt parse` path added
- [x] Metadata-only `dbt docs generate` completed locally
- [x] Screenshots saved in `docs/screenshots/`
- [ ] Full `dbt debug` completed after correcting `SNOWFLAKE_ACCOUNT`
- [ ] Full warehouse-backed `dbt docs generate` completed after correcting `SNOWFLAKE_ACCOUNT`

---

**Status**: Local/static documentation complete; warehouse catalog pending Snowflake account fix  
**Phase**: 12 of 15  
**Next Phase**: Phase 13 - Power BI Dashboard
