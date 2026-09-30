# DRC Sentinel Site Geocoding

Derives latitude and longitude for the **26 sentinel sites** of the DRC
surveillance network — one per province — from each site's name and province,
using the Google Maps Geocoding API.

The full method, quality rules and troubleshooting live in
[`pipeline/drc-geocoding-workflow.qmd`](pipeline/drc-geocoding-workflow.qmd).
This file is just enough to get you running.

## Layout

```
input/     drc_sentinel_sites_26.csv   the 26 sites (province, sentinel_site)
           manual_overrides.csv        analyst-pinned coordinates
pipeline/  config.R                    country profile, province list, thresholds
           geocode-functions.R         geocoder, quality gate, cache, overrides
           drc-geocoding-workflow.qmd  the workflow document -- run this
           test-geocode-functions.R    test suite
reference/ drc_provinces.csv           province boundaries for the PDF map
output/    generated results (git-ignored)
cache/     cached API responses (git-ignored)
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

## API key

You need a Google Cloud key with the **Geocoding API** enabled
(<https://console.cloud.google.com/apis/library>). The pipeline reads it from
the environment and never prints or writes it:

```bash
export GOOGLE_MAPS_API_KEY="your-key-here"
```

Export it in the shell rather than putting it in `.Renviron`: after
`source .uvr/activate`, R no longer reads `.Renviron` files.

A `REQUEST_DENIED` error almost always means the Geocoding API is not enabled on
the project, or the key has referrer restrictions that block server-side use.

Roughly 100 requests per full run — comfortably inside the free monthly tier.

## Running

```bash
quarto render pipeline/drc-geocoding-workflow.qmd --to html   # interactive
quarto render pipeline/drc-geocoding-workflow.qmd --to pdf    # report
```

The two formats are deliberately different documents from one source:

- **HTML** is for whoever runs the pipeline — interactive leaflet map, fold-out
  R code, setup and troubleshooting sections. It is a single self-contained
  file, so it can be emailed or moved without a companion folder.
- **PDF** is a report for review — no code, no setup or troubleshooting, and a
  static print map of the sites coloured by confidence.

Responses are cached in `cache/`, so re-rendering costs no API calls and yields
identical coordinates. Delete the cache file to force fresh lookups.

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

Run it from `pipeline/`: it sources `config.R` and `geocode-functions.R` by
relative path. 64 assertions, no API key and no network needed. Every Google
response used is a verbatim fixture recorded from the live API, so the quality
gate is exercised against what the API actually returns. Run these after any change to
`config.R` or `geocode-functions.R`.

## Outputs

| File | What it holds |
|---|---|
| `drc_sentinel_sites_geocoded.csv` | Main results: input columns plus coordinates and provenance |
| `drc_geocoding_candidates.csv` | Every candidate considered at every rung, accepted or rejected |
| `drc_geocoding_review.csv` | Anything below `high` confidence — look at these |
| `drc_geocoding_failed.csv` | Sites where no candidate could be trusted |
| `drc_sentinel_sites_map.html` | Interactive map |

## Correcting a bad result

Add a row to `input/manual_overrides.csv` and re-render:

```csv
site_id,latitude,longitude,note
DRC-MIKALAYI,-6.0500,22.3167,pinned from field GPS
```

Overrides take precedence over anything the API returned and are marked
`geocode_status = "manual"`. `site_id` is derived from the site name
(`DRC-VANGA`, `DRC-MWENE-DITU`), so overrides survive the input being re-sorted.

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

## Contact

- **Author**: Kaiza Ilomo
- **Project**: MoDD Africa
- **Institution**: Ifakara Health Institute
- **Email**: kilomo@ihi.or.tz
