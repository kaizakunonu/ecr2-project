#!/usr/bin/env Rscript
# Build the inputs of the walking-time reports (DRC_walking_travel_time_*.Rmd)
# from the geocoding pipeline's DPS-site pairs.
#
#   Rscript build_walking_inputs.R                    # google_first, into output/
#   Rscript build_walking_inputs.R --chain open_first --out output_open_first
#
# Run from the repo root, after geocoding/pipeline/drc-dps-site-pairs.qmd.
#
# Writes, under --out (default output/, which is where the Rmds read):
#   dps_11.csv, ss_11.csv              2003_2005 network, paired by row order
#   dps_26.csv, ss_26.csv              2014 network, paired by row order
#   network_51/ss_51.csv               2014 + 2021_expansion, paired by province
#   network_51/missing_2021_site.csv   provinces with no 2021_expansion site
#
# and, only when missing, the boundary layers the Rmds read through shp_path:
#   RDC_11_provinces_1988_2015/        unzipped from utilities/
#   GRID3_COD_health_zones/            downloaded from GRID3's ArcGIS service
#
# dps_province is written in each boundary layer's own spelling, because the
# Rmds check it against the layer's names with setdiff().
#
# google_first coordinates may not be published or shown on a non-Google map;
# open_first ones may (see CLAUDE.md).

suppressMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(stringr)
})

args <- commandArgs(TRUE)
arg_value <- function(flag, default) {
  i <- match(flag, args)
  if (is.na(i)) return(default)
  if (i == length(args)) stop(flag, " needs a value")
  args[i + 1]
}
chain   <- arg_value("--chain", "google_first")
out_dir <- arg_value("--out", "output")
if (!chain %in% c("google_first", "open_first")) {
  stop("--chain must be google_first or open_first, not ", chain)
}

pairs_file <- file.path("geocoding", "output",
                        paste0("drc_dps_site_pairs_", chain, ".csv"))
# The Rmds' shp_path defaults
prov11_shp <- "RDC_11_provinces_1988_2015/RDC_11_provinces_1988_2015.shp"
grid3_shp  <- "GRID3_COD_health_zones/GRID3_COD_health_zones_v9_0.shp"
prov11_zip <- "utilities/RDC_11_provinces_1988_2015_shapefile.zip"
grid3_layer <- paste0("https://services3.arcgis.com/BU6Aadhn6tbBEdyk/arcgis/",
                      "rest/services/GRID3_COD_health_zones_v9_0/FeatureServer/0")

if (!file.exists(pairs_file)) {
  stop(pairs_file, " not found: render ",
       "geocoding/pipeline/drc-dps-site-pairs.qmd first")
}

# ---------------------------------------------------------------------------
# Boundary layers
# ---------------------------------------------------------------------------

# GDAL cannot open a .shp without its .shx, .dbf and .prj
shp_complete <- function(shp) {
  all(file.exists(paste0(tools::file_path_sans_ext(shp),
                         c(".shp", ".shx", ".dbf", ".prj"))))
}

if (!shp_complete(prov11_shp)) {
  if (!file.exists(prov11_zip)) {
    stop(prov11_shp, " is incomplete and ", prov11_zip, " is missing")
  }
  layer <- tools::file_path_sans_ext(basename(prov11_shp))
  unzip(prov11_zip, exdir = dirname(prov11_shp), overwrite = FALSE,
        files = paste0(layer, c(".shp", ".shx", ".dbf", ".prj", ".cpg")))
  message("Unzipped ", prov11_shp, " from ", prov11_zip)
}

# The layer is fetched in pages over HTTP/1.1: one 140 MB response is more
# than the server reliably completes, and it resets long HTTP/2 streams.
arcgis_query <- function(layer, query, dest) {
  response <- httr::RETRY(
    "GET", paste0(layer, "/query"), query = query,
    httr::config(http_version = 2L),   # 2 = CURL_HTTP_VERSION_1_1
    httr::timeout(300), httr::write_disk(dest, overwrite = TRUE),
    times = 5, quiet = TRUE
  )
  httr::stop_for_status(response)
  dest
}

download_grid3 <- function(layer, shp, page_size = 50) {
  tmp <- tempfile()
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))

  count_file <- arcgis_query(layer, list(where = "1=1", returnCountOnly = "true",
                                         f = "json"), file.path(tmp, "count.json"))
  n <- jsonlite::read_json(count_file)$count
  pages <- lapply(seq(0, n - 1, by = page_size), function(offset) {
    page <- arcgis_query(layer, list(
      where = "1=1", outFields = "*", outSR = 4326, orderByFields = "OBJECTID",
      resultOffset = offset, resultRecordCount = page_size, f = "geojson"
    ), file.path(tmp, sprintf("page_%04d.geojson", offset)))
    st_read(page, quiet = TRUE)
  })
  hz <- do.call(rbind, pages)
  stopifnot(nrow(hz) == n, !anyDuplicated(hz$OBJECTID),
            n_distinct(hz$province) == 26)

  # Shapefile fields hold at most 10 characters, and if any name is longer sf
  # abbreviates every name (province -> provinc). Shape__Area and
  # Shape__Length are computed by ArcGIS, not GRID3 attributes.
  hz <- hz |>
    select(-Shape__Area, -Shape__Length) |>
    rename(src_acron = source_acronym)
  stopifnot(all(nchar(setdiff(names(hz), "geometry")) <= 10))

  dir.create(dirname(shp), showWarnings = FALSE)
  st_write(hz, shp, layer_options = "ENCODING=UTF-8",
           delete_dsn = file.exists(shp), quiet = TRUE)
  message("Downloaded ", nrow(hz), " health zones to ", shp)
}

if (!shp_complete(grid3_shp)) download_grid3(grid3_layer, grid3_shp)

province_names <- function(shp, column) {
  st_read(shp, quiet = TRUE) |> st_drop_geometry() |> pull(all_of(column)) |>
    unique() |> sort()
}
prov11_names <- province_names(prov11_shp, "PROVINCE")
grid3_names  <- province_names(grid3_shp, "province")

# ---------------------------------------------------------------------------
# Point files
# ---------------------------------------------------------------------------

# Same folding as normalise_name() in geocoding/pipeline/geocode-functions.R
normalise_name <- function(x) {
  x |>
    as.character() |>
    iconv(to = "ASCII//TRANSLIT", sub = "") |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]+", " ") |>
    str_squish()
}

spell_as <- function(x, layer_names) {
  out <- layer_names[match(normalise_name(x), normalise_name(layer_names))]
  if (anyNA(out)) {
    stop("No boundary province for: ", paste(unique(x[is.na(out)]), collapse = ", "))
  }
  out
}

pairs <- read_csv(pairs_file, show_col_types = FALSE)

# network_province is the province the network was set up under: pre-2015 for
# 2003_2005 (dps_province holds its post-2015 successor), current otherwise.
network_rows <- function(net, n, layer_names) {
  rows <- pairs |>
    filter(network == net) |>
    mutate(dps_province = spell_as(network_province, layer_names))
  if (nrow(rows) != n) stop(net, " has ", nrow(rows), " pairs, expected ", n)
  if (!all(rows$complete)) {
    warning(net, ": pairs without coordinates, which the Rmds drop or reject: ",
            paste(rows$sentinel_site[!rows$complete], collapse = ", "),
            call. = FALSE)
  }
  rows
}

written <- character()
write_out <- function(df, file) {
  path <- file.path(out_dir, file)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_csv(df, path)
  written <<- c(written, sprintf("%-36s %2d rows", path, nrow(df)))
}

# The 11- and 26-site Rmds pair row i of dps_ with row i of ss_
write_pairs <- function(rows, n) {
  write_out(transmute(rows, dps_province, latitude = dps_lat, longitude = dps_lon),
            paste0("dps_", n, ".csv"))
  write_out(transmute(rows, sentinel_site, latitude = site_lat, longitude = site_lon),
            paste0("ss_", n, ".csv"))
}

rows_2014 <- network_rows("2014", 26, grid3_names)
write_pairs(network_rows("2003_2005", 11, prov11_names), 11)
write_pairs(rows_2014, 26)

# The 51-site Rmd reuses dps_26.csv and pairs each site with its DPS by
# dps_province, so the full 2021 configuration is 2014 plus 2021_expansion.
rows_2021 <- network_rows("2021_expansion", 25, grid3_names)
write_out(
  bind_rows(rows_2014, rows_2021) |>
    transmute(network, dps_province, sentinel_site,
              latitude = site_lat, longitude = site_lon),
  "network_51/ss_51.csv"
)
write_out(
  tibble(network = "2021_expansion",
         dps_province = setdiff(grid3_names, rows_2021$dps_province),
         sentinel_site = NA_character_,
         note = "No site in the 2021_expansion sheet of data/input/DRC_DPS.xlsx"),
  "network_51/missing_2021_site.csv"
)

message("Coordinates: ", chain, "\n", paste(written, collapse = "\n"))
