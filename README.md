# DRC Malaria Sentinel-Site Accessibility

## Overview
National geospatial analysis of malaria
entomological sentinel-site surveillance
in the Democratic Republic of the Congo.

Three network configurations are compared:
- 11 historical sentinel sites
- 26 existing sentinel sites
- 51 sites: 26 existing and 25 proposed

The analysis uses MAP 2020 friction surfaces
to compare walking and motorised accessibility.

## Project organisation

- R/: active analysis scripts
- 06_run_analysis.R: main analysis runner
- build_walking_inputs.R: builds the analysis inputs in output/
  from the geocoding pipeline's DPS-site pairs
- data/: research input datasets
- geocoding/: geocoding workflow
- output/: input caches and model outputs
- output/unified/: final figures and tables
- output/poster/: 300-dpi figures for the poster
- ecr_poster.qmd: the poster; render it after the analysis
- poster/: poster Typst template and logos
- docs/: scientific notes and documentation
- archive/: legacy materials

## Run the analysis

Open ecr2-project.Rproj, then run:

```r
source("06_run_analysis.R")
```

The default run reuses validated existing
models and outputs where supported.
It is not a rebuild from raw data.

## Important

Run scripts from the project root.
Keep source inputs, geocoding data,
friction rasters and transition models.

The national accessibility study and
the Kasaï-Central proposal have
different scientific scopes.

R package versions are managed using uvr.
