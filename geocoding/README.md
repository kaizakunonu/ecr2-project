# DRC Sentinel Site Geocoding

Derives latitude and longitude for the **sentinel sites** of the DRC
surveillance network from each site's name and province. It covers the 26
sites of the 2014 network (one per province) and the 25 selected in the 2021
expansion.

Every site is geocoded independently by several providers: the Google
Geocoding API, GRID3's health-system geography, OpenStreetMap (through
Nominatim and Photon) and, once it has a username, GeoNames. Two coordinate
sets are kept side by side:
- `google_first`: Google's answer, with the open sources filling its gaps.
- `open_first`: the open sources, with Google filling only what they cannot.

Each kept point is cross-checked against the other providers. Only open-source
coordinates can be published, because Google's terms do not allow its
coordinates to be.

The full method, quality rules and troubleshooting live in
[`pipeline/drc-geocoding-workflow.qmd`](pipeline/drc-geocoding-workflow.qmd).
This file is just enough to get you running.

## Layout

```
input/     drc_sentinel_sites_26.csv   the 26 sites of 2014 (province, sentinel_site)
           drc_sentinel_sites_2021_expansion.csv  the 25 sites selected in 2021
           manual_overrides.csv        analyst-pinned coordinates
           drc_dps.csv                 the 31 DPS seats: 26 current, 5 pre-2015 (dps, province, chef_lieu)
           dps_manual_overrides.csv    analyst-pinned DPS coordinates
           drc_dps_site_pairs.csv      DPS-site pairs (network, province, dps, sentinel_site)
pipeline/  config.R                    country profile, provinces, providers, chains, thresholds, ladders
           geocode-functions.R         quality gate, ladder walk, chains, cross-check, cache, overrides
           providers.R                 one adapter per provider (Google, GRID3, Nominatim, Photon, GeoNames)
           pairs-functions.R           DPS-site pairing and straight-line distance
           drc-geocoding-workflow.qmd  the sentinel site workflow -- run this first
           drc-dps-site-pairs.qmd      the DPS geocoding and pairs workflow
           drc-geocoding-benchmark.qmd compares the providers -- run this last
           test-geocode-functions.R    test suite
           fixtures/                   recorded provider responses the tests replay
reference/ drc_provinces.csv           province boundaries for the PDF map and Photon's province boxes
output/    generated results (git-ignored)
cache/     cached responses, one file per provider (git-ignored)
```

## Setup

R and Quarto. Required packages:

```
tidyverse  httr  jsonlite  leaflet  htmlwidgets  knitr
```

Dependencies are pinned with `uvr` **in the repository root** (`uvr.toml`,
`uvr.lock`), not here. So:

- Inside the repository, install them once from the root, then activate the
  project library in every shell you run the pipeline from:
  ```bash
  uvr sync                 # from the repository root
  source .uvr/activate     # from the repository root; lasts for this shell
  ```
  Activation matters. The root `.Rprofile` links the project library only when
  R starts in the root, and the pipeline runs from `geocoding/`. Without
  activation R silently falls back to your user library.
- If this folder was copied out on its own, there is no lockfile — install the
  packages directly:
  ```r
  install.packages(c("tidyverse", "httr", "jsonlite",
                     "leaflet", "htmlwidgets", "knitr"))
  ```

This is the only thing outside `geocoding/` that the pipeline depends on.

## Credentials

The pipeline reads credentials from the environment and never prints or writes
them. They are needed only for requests that are not already cached, so a
re-render needs none.

```bash
export GOOGLE_MAPS_API_KEY="your-key-here"   # Google Cloud key with the Geocoding API enabled
export NOMINATIM_EMAIL="you@example.org"     # optional: a contact for Nominatim's operators
export GEONAMES_USERNAME="your-username"     # once GeoNames is enabled in config.R
```

Export them in the shell rather than putting them in `.Renviron`: after
`source .uvr/activate`, R no longer reads `.Renviron` files. GRID3 and Photon
need nothing.

- **Google**: a `REQUEST_DENIED` error almost always means the Geocoding API is
  not enabled on the project, or the key has referrer restrictions that block
  server-side use. Roughly 100 requests per full run, comfortably inside the
  free monthly tier.
- **GeoNames**: off by default (`providers$geonames$enabled` in `config.R`).
  Register a free account at <https://www.geonames.org/login>, enable its free
  web services, export `GEONAMES_USERNAME`, then switch it on.
- **Nominatim** allows at most one request per second, so the first full run
  takes a few minutes.

An enabled provider whose credential is missing stops the run at its first
uncached request. Disable it in `config.R` to run without it.

## Running

```bash
quarto render pipeline/drc-geocoding-workflow.qmd --to html   # interactive
quarto render pipeline/drc-geocoding-workflow.qmd --to pdf    # report
quarto render pipeline/drc-dps-site-pairs.qmd --to html       # DPS seats and pairs
quarto render pipeline/drc-geocoding-benchmark.qmd --to html  # provider comparison, no requests
```

The two formats are deliberately different documents from one source:

- **HTML** is for whoever runs the pipeline — interactive leaflet map, fold-out
  R code, setup and troubleshooting sections. It is a single self-contained
  file, so it can be emailed or moved without a companion folder.
- **PDF** is a report for review — no code, no setup or troubleshooting, and a
  static print map of the sites coloured by confidence.

Responses are cached in `cache/`, one file per provider, so re-rendering costs
no requests and yields identical coordinates. Delete a provider's file to force
fresh lookups from it. Google's answers expire by themselves after 30 days, as
its terms require.

The PDF needs a LaTeX installation. If you do not have one:

```bash
quarto install tinytex
```

The static map is drawn from `reference/drc_provinces.csv`, a flattened set of
DRC province boundaries committed to this folder. It is plotted with ggplot2
alone, so no spatial packages (and no GDAL/GEOS/PROJ system libraries) are
needed.

## Tests

```bash
cd pipeline && Rscript test-geocode-functions.R
```

Run it from `pipeline/`: it sources `config.R`, `geocode-functions.R`,
`providers.R` and `pairs-functions.R` by relative path, and reads `fixtures/`.
278 assertions, no API key and no network needed. Every response used was
recorded from the live APIs: Google's as parsed rows, the open providers' as
raw bodies in `fixtures/` that go through the real parsers. So the quality gate
is exercised against what the providers actually return. Run these after any
change to the pipeline's R files.

## Outputs

| File | What it holds |
|---|---|
| `drc_sentinel_sites_geocoded_{chain}.csv` | Main results, one file per set: input columns plus coordinates, provenance and cross-check |
| `drc_geocoding_review_{chain}.csv` | Anything below `high` confidence or short of `agree` — look at these |
| `drc_geocoding_by_provider.csv` | Every provider's own answer for every site |
| `drc_geocoding_candidates.csv` | Every candidate every provider offered at every rung, accepted or rejected |
| `drc_geocoding_provider_stats.csv` | Requests and cache hits per provider |
| `drc_geocoding_failed.csv` | Sites where no provider's candidate could be trusted |
| `drc_sentinel_sites_map.html` | Interactive map of both sets |

`{chain}` is `google_first` or `open_first`. `geocode_status` names the provider
each coordinate came from (or `manual`); `crosscheck` says whether another
source confirms it (`agree`), contradicts it (`disagree`), or has nothing
(`single-source`).

## Correcting a bad result

Add a row to `input/manual_overrides.csv` and re-render:

```csv
site_id,latitude,longitude,note
DRC-MIKALAYI,-6.0500,22.3167,pinned from field GPS
```

Overrides take precedence over anything the providers returned, in both sets,
and are marked `geocode_status = "manual"`. The cross-check then compares the
pinned point with every provider. `site_id` is derived from the site name
(`DRC-VANGA`, `DRC-MWENE-DITU`), so overrides survive the input being re-sorted.

## DPS–site pairs

`pipeline/drc-dps-site-pairs.qmd` gives each sentinel site's DPS headquarters a
coordinate, and pairs the two, once per coordinate set. It reads the sentinel
workflow's output, so it must be rendered after that workflow:

```bash
quarto render pipeline/drc-dps-site-pairs.qmd --to html
```

Each DPS is geocoded through the same gate with its own ladder in `config.R`:
the office (`Division Provinciale de la Sante <province>`) first, then the
chef-lieu town. Every result is matched against the chef-lieu name, so a
building in the wrong town is refused.

The gate cannot tell the DPS office from another building in the right town:
Google returns no establishment name, and an OpenStreetMap building's name is
not checked against the office. So **every building result goes to
`drc_dps_review_{chain}.csv`**, even at high confidence. To confirm or
correct one, pin it in `input/dps_manual_overrides.csv`, keyed on `dps_id`
(e.g. `DRC-DPS-KASAI-CENTRAL`).

The chef-lieux in `drc_dps.csv` are the provincial capitals under the 2006
Constitution. Check them against the DPS records before relying on them.

Three networks are paired, and kept separate so that accessibility can be
compared across them:

| Network | Pairs | What it is |
|---|---|---|
| `2003_2005` | 11 | The original 11 sites |
| `2014` | 26 | One site per current province |
| `2021_expansion` | 25 | The sites selected in 2021 |

Each network holds exactly what its workbook sheet lists. The 2021 expansion
adds to 2014, so the full 2021 configuration is `2014` plus `2021_expansion`.
Kasaï-Central's 2021 site is still to come.

The 2003–2005 pairs keep their 1988–2015 province names, for example
`Kasaï Oriental` and `DPS Kasaï Oriental`. `provinces_pre2015` in `config.R`
maps each old province onto the current provinces it was split into in 2015.
The build stops if either end of a pair falls outside them.

Each pre-2015 DPS seat is also a current chef-lieu:
- **Five old DPS whose provinces no longer exist have their own registry rows:**
  Bandundu, Bas-Congo, Kasaï Occidental, Katanga and Province Orientale.
- **The other six share a row with the current DPS of the same name:** Équateur,
  Kasaï Oriental, Kinshasa, Maniema, Nord-Kivu and Sud-Kivu.

Only one original site ended up in a different province from its old DPS:
Mwene-Ditu. It was under DPS Kasaï Oriental (Mbuji-Mayi) and is now in Lomami.
The pairs file flags it `province_mismatch`.

| File | What it holds |
|---|---|
| `drc_dps_site_pairs_{chain}.csv` | One row per pair: both coordinates and their sources, provenance, straight-line km, `complete`, `co_located` |
| `drc_dps_geocoded_{chain}.csv` | DPS coordinates, basis (establishment/settlement/manual), cross-check and review reason |
| `drc_dps_review_{chain}.csv` | DPS to check by hand |
| `drc_dps_by_provider.csv` | Every provider's own answer for every DPS seat |
| `drc_dps_candidates.csv` | Every DPS candidate at every rung, from every provider |
| `drc_dps_site_pairs_map.html` | Interactive map of the pairs in both sets |

To add a network:

1. Put its new sites in their own input file and add that file to
   `paths$input` in `config.R`.
2. Re-render the sentinel workflow.
3. Add its rows to `drc_dps_site_pairs.csv` with a new `network`.

Any DPS or site the rows name must first be in its input. If one is missing,
the build stops and names it.

A network's name must start with the year it began, e.g. `2003_2005`, `2014`,
`2021_expansion`. The build sorts networks by name, so the pairs output is always
chronological, with 2003_2005 first. Rows keep their input order (the
workbook's) within a network. The inputs follow the same order, and the DPS
registry lists its 5 pre-2015 seats first.

## Judge the run by confidence, not success rate

This is the one thing worth internalising before changing anything.

The pipeline **rejects** a candidate outright when it sits in the wrong province,
or when the returned name bears no resemblance to the site. A site that ends up
in `drc_geocoding_failed.csv` is not a bug — it means nothing trustworthy was
found, and the honest answer is no coordinate.

An earlier version treated these as warnings rather than rejections. It reported
100% success while placing one health zone on a business in Kinshasa, roughly
700 km from where it belongs. For spatial analysis a wrong coordinate is worse
than a missing one, because nothing downstream will ever flag it.

So if the success rate looks low, the fix is to pin the location in
`manual_overrides.csv` — not to lower the thresholds in `config.R`.

The open providers brought new ways of being wrong, each now a rejection:
OpenStreetMap's health-zone polygons (their centroid is not the site), streets
and rivers named after towns, a village whose name merely contains the site's
(Bakwa-Nyanga for Nyanga), and a different number (Maluku 2 for Maluku 1). And
because providers can each be wrong in their own way, a point no other source
confirms goes to review, however high its confidence.

## Contact

- **Author**: Kaiza Ilomo
- **Project**: MoDD Africa
- **Institution**: Ifakara Health Institute
- **Email**: kilomo@ihi.or.tz
