# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A research project (MAP Early Career Researcher study, MoDD Africa / Ifakara Health Institute) on the geographic accessibility of the DRC's malaria entomological sentinel surveillance sites. Most of it is Quarto writing. The only real code is the sentinel-site geocoding pipeline in `geocoding/`, plus a Python script that builds its input.

The documents disagree on scope, so check which one a task is about:
- `proposal.qmd` is **provincial**: Kasaï-Central, its 26 health zones, anchored on entomological data.
- `ecr_progress report.qmd` is **national**: 26 provinces, one sentinel site each, open geospatial data only.
- `sentinel-accessibility-outline.md` explains this split and recommends treating them as two papers (P1 national, P2 Kasaï-Central).

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

# Geocoding tests: 148 assertions, no network or API key needed.
# Must run from pipeline/, because the script sources config.R by relative path.
cd geocoding/pipeline && Rscript test-geocode-functions.R

# Geocoding run (needs GOOGLE_MAPS_API_KEY; the cache makes re-renders free)
cd geocoding && quarto render pipeline/drc-geocoding-workflow.qmd --to html
cd geocoding && quarto render pipeline/drc-geocoding-workflow.qmd --to pdf   # xelatex

# DPS headquarters + DPS-site pairs (needs the key; reads the sentinel output, so render that first)
cd geocoding && quarto render pipeline/drc-dps-site-pairs.qmd --to html

# Documents (the progress report's filename contains a space)
quarto render proposal.qmd
quarto render "ecr_progress report.qmd"

# Rebuild the 26-site input from the workbook (needs openpyxl; no Python env is committed)
python3 extract_sentinel_sites_26.py            # writes geocoding/input/drc_sentinel_sites_26.csv
python3 extract_sentinel_sites_26.py --audit    # adds provenance columns; writes ./drc_sentinel_sites_26_audit.csv
```

The test suite has no per-test selection. It is a single script of `ok()` assertions grouped by `section()`.

## Data flow

`DRC_Health_Zones_Sentinel_Sites.xlsx` (untracked) → `extract_sentinel_sites_26.py` → `geocoding/input/drc_sentinel_sites_26.csv` → `drc-geocoding-workflow.qmd` → `geocoding/output/` (git-ignored).

The extractor combines two blocks from the workbook's `Metadata` sheet: the original 11 sites, which use pre-2015 province names, and a 15-site delta from 2014. It relabels the 11 onto the post-2015 provinces through `CROSSWALK_2015`, which comes from geography and not from the workbook. A closure check exits non-zero if the 11 + 15 provinces do not exactly equal the workbook's 26. The workbook's 52-site column is deliberately ignored.

Its output is deterministic: rows are sorted by accent-folded province, then site. A regenerated input that differs from the committed CSV means the workbook or the crosswalk changed.

The sentinel workflow reads every file in `paths$input` through `read_sites()`, as one registry of 51 sites. The second file is `geocoding/input/drc_sentinel_sites_2021_expansion.csv`: the 25 sites selected in 2021, taken from the `2021_expansion` sheet of `30Sep/DRC_DPS.xlsx` in sheet order. Kasaï-Central has no 2021 site yet. Never append to `drc_sentinel_sites_26.csv`, which the extractor owns; a new network gets its own input file.

A second flow pairs each site with its DPS (Division Provinciale de la Santé) headquarters. It uses `geocoding/input/drc_dps.csv` (DPS seats: dps, province, chef-lieu) and `geocoding/input/drc_dps_site_pairs.csv` (`network, province, dps, sentinel_site`). It reads the sentinel output, and `drc-dps-site-pairs.qmd` writes `geocoding/output/drc_dps_site_pairs.csv`. The pairs were checked against the `2003_2005`, `2014` and `2021_expansion` sheets of `30Sep/DRC_DPS.xlsx`, which is untracked. The three networks are kept separate, because downstream analysts compare accessibility across them. Each holds exactly what its sheet lists, so the full 2021 configuration is `2014` plus `2021_expansion`.

The 2003–2005 pairs keep their pre-2015 province and DPS names. `provinces_pre2015` in `config.R` records the July 2015 split, which matches `DPS_2015` in `30Sep/RDC_11_provinces_1988_2015_shapefile.zip`. `build_pairs` stops if a pair's DPS seat or site lies outside what its province became. Network names must start with the year the network began. `build_pairs` sorts by network name, which gives chronological output (2003_2005 first), and keeps the workbook's row order within each network.
- Five pre-2015 DPS whose provinces no longer exist have their own registry rows.
- The other six share the row of the same-named current DPS. The seat is the same, and `normalise_name` folds "Kasaï Oriental" to "Kasaï-Oriental".

## Geocoding pipeline architecture (`geocoding/pipeline/`)

- **`config.R`** contains everything specific to the DRC: the country profile (ISO code, language, bounding box, column names, id prefix), the 26 canonical post-2015 provinces and the 2015 split from the 11 old ones (`provinces_pre2015`), the query ladders, the quality-gate thresholds and site-name fixes. Pointing the pipeline at another country should mean editing only this file. `paths` are relative to `pipeline/`.
- **`geocode-functions.R`** calls the Google Geocoding REST API directly with `httr`, not through a wrapper, because the quality gate needs `partial_match`, `location_type`, `types` and the result count. Its pieces:
  - **Query ladder** (`build_query_variants`): the rungs come from `ladders` in `config.R`, one ladder per point set (`sentinel_site`, `dps`). Rungs 1–2 pin `administrative_area` to the province, rungs 3–4 are country-restricted free text. `confidence_tier` depends on that split, so keep it. `geocode_site` stops at the first accepted candidate and logs every candidate to an audit trail.
  - **DPS ladder**: tries the office first, then the chef-lieu, and always matches against the chef-lieu name. The gate cannot tell the office from another building in the same town, because the Geocoding API returns no establishment name. So `point_basis()` labels each result as an establishment or a settlement, and the DPS workflow sends every establishment result to review.
  - **Quality gate** (`assess_candidate`): *hard rejections* discard a candidate: an admin-area centroid, coordinates outside the bounding box, a returned province different from the expected one, or name similarity below `similarity_floor`. *Soft flags* lower confidence but keep the candidate. The province check is needed because Google treats the component filter as advisory. There is deliberately no blacklist on `establishment` / `point_of_interest` types.
  - **Confidence tiers** (`confidence_tier`): high / medium / low / failed, based on flag count and rung.
  - **Cache**: an `.rds` file keyed on address + components. Google's terms allow only short-lived caching, so treat it as disposable.
  - **Manual overrides**: rows in `input/manual_overrides.csv`, keyed on `site_id`, win over API results and get status `manual`. `site_id` is a slug of the site name (`DRC-MWENE-DITU`), not a row number, so it survives re-sorting.
- **`drc-geocoding-workflow.qmd`** builds two different documents from one source. HTML is the operator's version, with folded code, setup and troubleshooting, and a leaflet map. PDF is a review report with no code and a static ggplot map drawn from `reference/drc_provinces.csv`, so no GDAL/sf is needed. HTML-only sections are wrapped in `::: {.content-visible when-format="html"}`, and `echo` is set from `knitr::is_html_output()`.

### The rule that governs changes to the gate

A wrong coordinate is worse than a missing one. An earlier version reported 100% success while placing Mikalayi (Kasaï) on a Kinshasa business about 700 km away. When a site fails, pin it in `manual_overrides.csv`. Do not lower the thresholds in `config.R`: they were calibrated on live responses, where correct matches scored 1.00 and wrong ones 0.56 and 0.25.

Test fixtures are verbatim live API responses. New gate behaviour should be tested against real recorded responses, not made-up ones.

## Conventions

- Provinces use the 26-province (post-2015) vocabulary. `validate_provinces` rejects pre-2015 names such as Bandundu or Katanga. Names are compared through `normalise_name()`, which ignores accents, so "Kasai" and "Kasaï" match.
- `.gitignore` excludes `*.html`, `*.pdf`, `*.csv`, `*.xlsx`, Office files and geospatial data. Exceptions are `geocoding/input/*.csv` and `geocoding/reference/*.csv`. `proposal.html` and `proposal.pdf` are already tracked. Commit any other rendered deliverable deliberately with `git add -f`.
- `GOOGLE_MAPS_API_KEY` is read from the environment and never printed or written. `.Renviron` and `.env` are git-ignored, but see the activation caveat above.
- R style is 2-space indent with the native pipe `|>`, as set in `ecr2-project.Rproj` and used throughout.
- `references.bib` is used only by `proposal.qmd`. The progress report writes its citations as plain text.
