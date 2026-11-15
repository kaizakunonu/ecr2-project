# AGENTS.md

This file provides guidance to coding agents (Codex, and Claude Code through `CLAUDE.md`) when working with code in this repository.

## What this repository is

A research project (MAP Early Career Researcher study, MoDD Africa / Ifakara Health Institute) on the geographic accessibility of the DRC's malaria entomological sentinel surveillance sites. Most of it is Quarto writing. The code is the sentinel-site geocoding pipeline in `geocoding/` (plus a Python script that builds its input) and the accessibility analysis in `R/`, run by `06_run_analysis.R`.

The documents disagree on scope, so check which one a task is about:
- `proposal.qmd` is **provincial**: Kasaï-Central, its 26 health zones, anchored on entomological data.
- `ecr_progress report.qmd` is **national**: 26 provinces, one sentinel site each, open geospatial data only.
- `docs/research/sentinel-accessibility-outline.md` explains this split and recommends treating them as two papers (P1 national, P2 Kasaï-Central).

## Environment

R 4.6.1 is managed with **uvr** (`uvr.toml`, `uvr.lock`, library in `.uvr/library`). This replaced renv.

```bash
uvr sync                 # install everything in uvr.lock
uvr add <pkg>            # add a dependency (updates uvr.toml + uvr.lock)
uvr scan                 # list packages used in .R/.qmd files but missing from uvr.toml
uvr run <script.R>       # run a script inside the project environment
source .uvr/activate     # activate in a shell
```

The root `.Rprofile` adds `.uvr/library` to the library path only when R starts **in the repo root**. R started in `geocoding/pipeline/` (tests, Quarto renders) does not read it and silently falls back to the user library, so `source .uvr/activate` first. Once activated, R stops reading `.Renviron` (both `./` and `~/`), so `export` secrets in the shell instead.

`uvr scan` still reports `dplyr`, `purrr`, `stringr` and `tibble` as undeclared. They are installed as part of `tidyverse`, so that is expected. It also reports `renv`, because the workflow text mentions it by name.

## Commands

```bash
source .uvr/activate     # once per shell, from the repo root

# Geocoding tests: 278 assertions, no network or API key needed.
# Must run from pipeline/, because the script sources config.R and reads fixtures/ by relative path.
cd geocoding/pipeline && Rscript test-geocode-functions.R

# Geocoding run. Credentials are needed only for uncached requests; the cache makes re-renders free.
cd geocoding && quarto render pipeline/drc-geocoding-workflow.qmd --to html
cd geocoding && quarto render pipeline/drc-geocoding-workflow.qmd --to pdf   # xelatex

# DPS headquarters + DPS-site pairs (reads the sentinel output, so render that first)
cd geocoding && quarto render pipeline/drc-dps-site-pairs.qmd --to html

# Provider benchmark (no requests; reads both workflows' outputs, so render it last)
cd geocoding && quarto render pipeline/drc-geocoding-benchmark.qmd --to html

# Documents (the progress report's filename contains a space)
quarto render proposal.qmd
quarto render "ecr_progress report.qmd"

# Rebuild the 26-site input from the workbook (needs openpyxl; no Python env is committed)
python3 extract_sentinel_sites_26.py            # writes geocoding/input/drc_sentinel_sites_26.csv
python3 extract_sentinel_sites_26.py --audit    # adds provenance columns; writes ./drc_sentinel_sites_26_audit.csv

# Accessibility inputs (reads the DPS-site pairs, so render those first)
Rscript build_walking_inputs.R                                            # google_first, into output/
Rscript build_walking_inputs.R --chain open_first --out output_open_first

# Accessibility analysis: runs R/00-R/05 in order, writes output/unified/.
# Reuses output/unified/Table_assigned_travel_times.csv when present; call
# run_analysis(full_rebuild = TRUE) to recompute it.
Rscript 06_run_analysis.R
quarto render ecr_final_report.qmd   # reads output/unified/
quarto render ecr_poster.qmd         # reads output/unified/ and output/poster/; Typst, one A0 page
```

The test suite has no per-test selection. It is a single script of `ok()` assertions grouped by `section()`.

## Data flow

`data/input/DRC_Health_Zones_Sentinel_Sites.xlsx` (untracked) → `extract_sentinel_sites_26.py` → `geocoding/input/drc_sentinel_sites_26.csv` → `drc-geocoding-workflow.qmd` → `geocoding/output/` (git-ignored).

The extractor combines two blocks from the workbook's `Metadata` sheet: the original 11 sites, which use pre-2015 province names, and a 15-site delta from 2014. It relabels the 11 onto the post-2015 provinces through `CROSSWALK_2015`, which comes from geography and not from the workbook. A closure check exits non-zero if the 11 + 15 provinces do not exactly equal the workbook's 26. The workbook's 52-site column is deliberately ignored.

Its output is deterministic: rows are sorted by accent-folded province, then site. A regenerated input that differs from the committed CSV means the workbook or the crosswalk changed.

The sentinel workflow reads every file in `paths$input` through `read_sites()`, as one registry of 51 sites. The second file is `geocoding/input/drc_sentinel_sites_2021_expansion.csv`: the 25 sites selected in 2021, taken from the `2021_expansion` sheet of `data/input/DRC_DPS.xlsx` in sheet order. Kasaï-Central has no 2021 site yet. Never append to `drc_sentinel_sites_26.csv`, which the extractor owns; a new network gets its own input file.

A second flow pairs each site with its DPS (Division Provinciale de la Santé) headquarters. It uses `geocoding/input/drc_dps.csv` (DPS seats: dps, province, chef-lieu) and `geocoding/input/drc_dps_site_pairs.csv` (`network, province, dps, sentinel_site`). It reads the sentinel output, and `drc-dps-site-pairs.qmd` writes `geocoding/output/drc_dps_site_pairs_{chain}.csv`, one per coordinate set. The pairs were checked against the `2003_2005`, `2014` and `2021_expansion` sheets of `data/input/DRC_DPS.xlsx`. The three networks are kept separate, because downstream analysts compare accessibility across them. Each holds exactly what its sheet lists, so the full 2021 configuration is `2014` plus `2021_expansion`.

The 2003–2005 pairs keep their pre-2015 province and DPS names. `provinces_pre2015` in `config.R` records the July 2015 split, which matches `DPS_2015` in `utilities/RDC_11_provinces_1988_2015_shapefile.zip`. `build_pairs` stops if a pair's DPS seat or site lies outside what its province became. Network names must start with the year the network began. `build_pairs` sorts by network name, which gives chronological output (2003_2005 first), and keeps the workbook's row order within each network.
- Five pre-2015 DPS whose provinces no longer exist have their own registry rows.
- The other six share the row of the same-named current DPS. The seat is the same, and `normalise_name` folds "Kasaï Oriental" to "Kasaï-Oriental".

The accessibility analysis (`R/00`–`R/05`, run in order by `06_run_analysis.R`) reads the pairs through `build_walking_inputs.R`, which writes `output/` (git-ignored, separate from `geocoding/output/`):
- `dps_11.csv` + `ss_11.csv` and `dps_26.csv` + `ss_26.csv` are paired by row order.
- `network_51/ss_51.csv` (2014 + 2021_expansion) is paired with `dps_26.csv` by `dps_province`.
- `dps_province` uses each boundary layer's spelling, because the original walking-time Rmds `setdiff()` against it: the 11-province shapefile for 2003_2005, GRID3 v9.0 health zones otherwise (`Mai-Ndombe`, no ï).
- The script also creates those layers when missing: it unzips `RDC_11_provinces_1988_2015/` from `utilities/` and downloads `GRID3_COD_health_zones/` from GRID3's ArcGIS service.
- `R/02_accessibility.R` downloads the MAP friction surfaces with `malariaAtlas` when missing and caches them, with their transition layers, in `output/`; `R/03` and `R/04` reuse them.
- Results go to `output/unified/`, and 300-dpi copies of the poster's figures to `output/poster/` (from `R/01`, `R/02` and `R/05`). `ecr_final_report.qmd`, `ecr_progress report.qmd` and `ecr_poster.qmd` read them and compute their numbers from the tables, so re-render them after a pipeline run.
- The walking and motorised Rmds and numbered scripts that preceded `R/` are kept in `archive/legacy_scripts/` for reference. Nothing runs them.

## Geocoding pipeline architecture (`geocoding/pipeline/`)

Every point is geocoded independently by every enabled provider (Google, GRID3, Nominatim, Photon; GeoNames once it has a username). Two coordinate sets are then chosen from the same answers and kept side by side: `google_first` and `open_first` (Google last). Only open-source coordinates may be published: Google's terms allow its coordinates to be cached for 30 days and not shown on a non-Google map.

- **`config.R`** contains everything specific to the DRC: the country profile (ISO code, language, bounding box, column names, id prefix), the 26 canonical post-2015 provinces and the 2015 split from the 11 old ones (`provinces_pre2015`), the query ladders, the quality-gate thresholds and site-name fixes. It also holds:
  - `providers`: family, credential env var, `enabled`, `rate_delay`, `cache_days`, and `skip_rungs` per point set.
  - `chains`: the two provider orders.
  - `crosscheck$agree_km`.
  - `grid3_layers` and `geonames_admin1`, the province code map.

  Pointing the pipeline at another country should mean editing only this file. `paths` are relative to `pipeline/`.
- **`providers.R`** has one adapter per provider. Each answers one ladder rung with `list(status, n_results, candidates)` in a shared candidate schema: `empty_candidates()`, i.e. Google's columns plus `provider`, `kind`, `name` and `name_alt`.
  - `kind` (area / linear / settlement / establishment / other) is how each provider's type system reaches the gate.
  - `provider_fetchers` is the registry of adapters.
  - Google is called over REST with `httr`, not through a wrapper, because the gate needs `partial_match`, `location_type`, `types` and the result count.
  - GRID3 is a set of public ArcGIS tables, fetched whole, cached and matched locally:
    - Rung 1 is the health zone's central office (BCZ).
    - Rung 2 is a settlement named exactly like the site, inside the health zone of that name. Its villages repeat names and near-names.
- **`geocode-functions.R`** is everything that does not depend on the provider:
  - **Query ladder** (`build_query_variants`): the rungs come from `ladders` in `config.R`, one ladder per point set (`sentinel_site`, `dps`). Rungs 1–2 are pinned to the province (Google's `administrative_area`, Nominatim's `state=`, a Photon bbox, GeoNames' `adminCode1`, GRID3's province field), rungs 3–4 are country-restricted free text. `confidence_tier` depends on that split, so keep it. Each rung's `target` (health_zone / office / settlement) lets an adapter route it.
  - **Ladder walk** (`geocode_site`): one provider at a time; it stops at the first accepted candidate and logs every candidate to an audit trail. `fetch` can be injected, which is how the tests replay recorded responses. `geocode_point_all` runs every enabled provider.
  - **DPS ladder**: tries the office first, then the chef-lieu, and always matches against the chef-lieu name. The gate cannot tell the office from another building in the same town. So `matched_kind` labels each result, and the DPS workflow sends every establishment result to review.
  - **Quality gate** (`assess_candidate`):
    - *Hard rejections* discard a candidate:
      - an area's centroid (`kind == "area"`: a Google admin centroid, or an OSM `boundary=administrative|health` polygon)
      - a street, river or railway (`kind == "linear"`)
      - coordinates outside the bounding box
      - a returned province different from the expected one
      - name similarity below `similarity_floor`
      - different numbers in the names (Maluku 1 vs Maluku 2)
    - Providers that name the place itself are compared on **whole names** (`whole_name_similarity`). The substring rule Google needs scored Bakwa-Nyanga 1.00 for Nyanga.
    - *Soft flags* lower confidence but keep the candidate.
    - For non-Google providers, ambiguity counts the distinct places that pass the hard gate, not the raw result count.
    - The province check is needed because Google treats the component filter as advisory.
    - There is deliberately no blacklist on `establishment` / `point_of_interest` types.
  - **Confidence tiers** (`confidence_tier`): high / medium / low / failed, based on flag count and rung.
  - **Chains and cross-check**: `select_chain` keeps the first provider in a chain that resolved the point. `crosscheck_points` then compares the kept point with every other provider's answer (`agree` / `disagree` / `single-source`, within `agree_km`). It counts source *families*, because Nominatim and Photon are both OSM. The cross-check never rejects and never changes `confidence`; `needs_review` sends anything short of a confirmed `high` to review.
  - **Cache**: one `.rds` per provider in `cache/` (`{provider}_geocode_cache.rds`). Each entry has `cached_at`, and expires after the provider's `cache_days`: 30 for Google, as its terms require. Google's key is still address + components, so old Google entries replay. `cache_save()` writes only changed stores and is called after every point. Credentials are read only when a request has to go out.
  - **Manual overrides**: rows in `input/manual_overrides.csv`, keyed on `site_id`, win over API results in both sets and get status `manual`. `site_id` is a slug of the site name (`DRC-MWENE-DITU`), not a row number, so it survives re-sorting.
- **`drc-geocoding-benchmark.qmd`** compares the providers from the workflows' `*_by_provider.csv` outputs, making no requests. It reports:
  - coverage
  - pairwise distances and `agree_km` calibration
  - Google's failures
  - a chain simulation over every provider order
  - gate diagnostics

  If `output/baseline/` holds a snapshot of the old Google-only outputs, it checks the Google column against it.
- **`drc-geocoding-workflow.qmd`** builds two different documents from one source. HTML is the operator's version, with folded code, setup and troubleshooting, and a leaflet map. PDF is a review report with no code and a static ggplot map drawn from `reference/drc_provinces.csv`, so no GDAL/sf is needed. HTML-only sections are wrapped in `::: {.content-visible when-format="html"}`, and `echo` is set from `knitr::is_html_output()`.

### The rule that governs changes to the gate

A wrong coordinate is worse than a missing one. An earlier version reported 100% success while placing Mikalayi (Kasaï) on a Kinshasa business about 700 km away. When a site fails, pin it in `manual_overrides.csv`. Do not lower the thresholds in `config.R`: they were calibrated on live Google responses, where correct matches scored 1.00 and wrong ones 0.56 and 0.25.

Those thresholds do not separate the open providers' answers as cleanly. Under whole-name matching, different places with similar names score 0.6–0.9: Katanga for Katana, Kalema for Kalima, Iwela for Ikela. Such answers carry an "imperfect name match" flag, so they are never `high`, and the cross-check usually marks them `disagree`. GRID3's settlement rung requires an exact name for this reason.

Test fixtures are live responses: Google's copied in as parsed rows, the open providers' stored verbatim as JSON in `pipeline/fixtures/` and run through the real parsers. New gate behaviour should be tested against real recorded responses, not made-up ones. The one exception is the cross-check's disagreement test, which is built by hand from real coordinates.

## Conventions

- Provinces use the 26-province (post-2015) vocabulary. `validate_provinces` rejects pre-2015 names such as Bandundu or Katanga. Names are compared through `normalise_name()`, which ignores accents, so "Kasai" and "Kasaï" match.
- `.gitignore` excludes `*.html`, `*.pdf`, `*.csv`, `*.xlsx`, Office files and geospatial data. Exceptions are `geocoding/input/*.csv` and `geocoding/reference/*.csv`. `proposal.pdf` and `ecr_final_report.pdf` are already tracked. Commit any other rendered deliverable deliberately with `git add -f`.
- `GOOGLE_MAPS_API_KEY`, `GEONAMES_USERNAME` and the optional `NOMINATIM_EMAIL` are read from the environment, only when an uncached request needs them, and never printed or written. `.Renviron` and `.env` are git-ignored, but see the activation caveat above.
- R style is 2-space indent with the native pipe `|>`, as set in `ecr2-project.Rproj` and used throughout.
- `references.bib` is used only by `proposal.qmd`. The progress report writes its citations as plain text.
