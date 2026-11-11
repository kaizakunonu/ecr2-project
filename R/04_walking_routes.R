
# 04 — Walking routes and distances to assigned sentinel sites

source("R/00_packages.R")

# FALSE: preserve existing validated route outputs
# TRUE: rebuild all routes from the transition model

rebuild_routes <- isTRUE(getOption("drc.rebuild_routes", FALSE))

out_dir <- "output/unified"

journey_file <- file.path(
  out_dir, "Table_assigned_travel_times.csv"
)

transition_file <- "output/transition_walk_drc_gc.rds"
friction_file <- "output/friction_walk_drc_buffer.tif"

distance_file <- file.path(
  out_dir, "walking_route_distances.csv"
)

geometry_file <- file.path(
  out_dir, "walking_routes.gpkg"
)

stopifnot(
  file.exists(journey_file),
  file.exists(transition_file),
  file.exists(friction_file)
)

# 1. Read walking journeys

journeys <- readr::read_csv(
  journey_file,
  show_col_types = FALSE
) |>
  dplyr::filter(mode == "walking") |>
  dplyr::arrange(network, province, sentinel_site)

required <- c(
  "network",
  "province",
  "dps_office",
  "sentinel_site",
  "dps_longitude",
  "dps_latitude",
  "site_longitude",
  "site_latitude",
  "travel_minutes",
  "travel_hours"
)

stopifnot(
  all(required %in% names(journeys)),
  nrow(journeys) == 88,
  all(is.finite(journeys$travel_minutes))
)

# 2. Identify distinct geographical journeys

journeys$route_key <- sprintf(
  "%.8f|%.8f|%.8f|%.8f",
  journeys$dps_longitude,
  journeys$dps_latitude,
  journeys$site_longitude,
  journeys$site_latitude
)

journeys$route_id <- match(
  journeys$route_key,
  unique(journeys$route_key)
)

unique_routes <- journeys |>
  dplyr::distinct(route_id, .keep_all = TRUE)

message(
  "Walking scenario records: ", nrow(journeys),
  "\nDistinct DPS-to-site routes: ", nrow(unique_routes)
)

# 3. Calculate walking routes

calculate_routes <- function() {

  transition <- readRDS(transition_file)

  friction <- raster::raster(
    friction_file
  )

  stopifnot(
    identical(
      as.integer(dim(transition)[1:2]),
      as.integer(dim(friction)[1:2])
    )
  )

  previous_s2 <- sf::sf_use_s2()

  on.exit(
    sf::sf_use_s2(previous_s2),
    add = TRUE
  )

  sf::sf_use_s2(TRUE)

  route_results <- vector(
    "list",
    nrow(unique_routes)
  )

  for (i in seq_len(nrow(unique_routes))) {

    x <- unique_routes[i, ]

    origin <- c(
      x$dps_longitude,
      x$dps_latitude
    )

    destination <- c(
      x$site_longitude,
      x$site_latitude
    )

    origin_cell <- raster::cellFromXY(
      friction,
      matrix(origin, nrow = 1)
    )

    destination_cell <- raster::cellFromXY(
      friction,
      matrix(destination, nrow = 1)
    )

    stopifnot(
      is.finite(origin_cell),
      is.finite(destination_cell)
    )

    if (origin_cell == destination_cell) {

      # Same raster cell: zero modelled route distance

      xy <- raster::xyFromCell(
        friction,
        origin_cell
      )

      line <- sf::st_linestring(
        rbind(xy, xy)
      )

      distance_km <- 0
      route_status <- "same_raster_cell"

    } else {

      path <- gdistance::shortestPath(
        transition,
        origin,
        destination,
        output = "SpatialLines"
      )

      path_sf <- sf::st_as_sf(path)

      if (is.na(sf::st_crs(path_sf))) {
        sf::st_crs(path_sf) <- 4326
      }

      path_sf <- sf::st_transform(
        path_sf,
        4326
      )

      stopifnot(nrow(path_sf) == 1)

      coords <- sf::st_coordinates(
        path_sf
      )

      if (
        "L1" %in% colnames(coords) &&
        length(unique(coords[, "L1"])) != 1
      ) {
        stop(
          "Multiple route segments found for route ",
          x$route_id
        )
      }

      stopifnot(
        nrow(coords) >= 2,
        all(is.finite(coords[, 1:2]))
      )

      line <- sf::st_linestring(
        unname(
          as.matrix(coords[, 1:2])
        )
      )

      # Geodesic length of the modelled walking route

      distance_km <- as.numeric(
        sf::st_length(
          sf::st_sfc(
            line,
            crs = 4326
          )
        )
      ) / 1000

      route_status <- "calculated"
    }

    route_results[[i]] <- list(
      route_id = x$route_id,
      line = line,
      distance_km = distance_km,
      status = route_status
    )

    if (
      i %% 10 == 0 ||
      i == nrow(unique_routes)
    ) {
      message(
        "Calculated ", i, "/",
        nrow(unique_routes), " routes"
      )
    }
  }

  # 4. Prepare route distance table

  route_table <- data.frame(
    route_id = vapply(
      route_results,
      function(x) x$route_id,
      integer(1)
    ),
    walking_route_km = vapply(
      route_results,
      function(x) x$distance_km,
      numeric(1)
    ),
    route_status = vapply(
      route_results,
      function(x) x$status,
      character(1)
    )
  )

  stopifnot(
    nrow(route_table) == nrow(unique_routes),
    !anyNA(route_table$walking_route_km),
    all(route_table$walking_route_km >= 0)
  )

  # Attach route distances to all 88 journey records

  scenario_results <- journeys |>
    dplyr::left_join(
      route_table,
      by = "route_id"
    ) |>
    dplyr::select(-route_key)

  stopifnot(
    nrow(scenario_results) == 88,
    !anyNA(scenario_results$walking_route_km)
  )

  # 5. Prepare route geometries

  geometry <- sf::st_sfc(
    lapply(
      route_results,
      function(x) x$line
    ),
    crs = 4326
  )

  route_geometries <- sf::st_sf(
    route_table,
    geometry = geometry
  )

  # 6. Save outputs after successful calculations

  temp_csv <- tempfile(
    tmpdir = out_dir,
    fileext = ".csv"
  )

  temp_gpkg <- tempfile(
    tmpdir = out_dir,
    fileext = ".gpkg"
  )

  on.exit(
    unlink(c(temp_csv, temp_gpkg)),
    add = TRUE
  )

  readr::write_csv(
    scenario_results,
    temp_csv
  )

  sf::st_write(
    route_geometries,
    temp_gpkg,
    layer = "walking_routes",
    quiet = TRUE
  )

  stopifnot(
    file.exists(temp_csv),
    file.exists(temp_gpkg),
    file.info(temp_csv)$size > 0,
    file.info(temp_gpkg)$size > 0
  )

  stopifnot(
    file.copy(
      temp_gpkg,
      geometry_file,
      overwrite = TRUE
    ),
    file.copy(
      temp_csv,
      distance_file,
      overwrite = TRUE
    )
  )

  invisible(scenario_results)
}

# 7. Reuse existing results or rebuild routes

if (
  !rebuild_routes &&
  file.exists(distance_file) &&
  file.exists(geometry_file)
) {

  message(
    "Existing walking-route results preserved."
  )

} else {

  calculate_routes()
}

# 8. Summarise walking-route results

routes <- readr::read_csv(
  distance_file,
  show_col_types = FALSE
)

# Compatibility with the previously validated distance table

if (
  "walking_hours" %in% names(routes) &&
  !"travel_hours" %in% names(routes)
) {

  routes <- dplyr::rename(
    routes,
    travel_hours = walking_hours
  )
}

stopifnot(
  nrow(routes) == 88,
  all(c(
    "network",
    "province",
    "sentinel_site",
    "walking_route_km",
    "travel_hours"
  ) %in% names(routes))
)

summary_table <- routes |>
  dplyr::group_by(network) |>
  dplyr::summarise(
    journeys = dplyr::n(),
    routes_with_distance = sum(
      !is.na(walking_route_km)
    ),
    median_route_km = round(
      median(walking_route_km, na.rm = TRUE),
      2
    ),
    max_route_km = round(
      max(walking_route_km, na.rm = TRUE),
      2
    ),
    median_walking_hours = round(
      median(travel_hours, na.rm = TRUE),
      2
    ),
    .groups = "drop"
  )

print(summary_table)

readr::write_csv(
  summary_table,
  file.path(
    out_dir,
    "Table_walking_route_summary.csv"
  )
)

# 9. Verify historical Katana route

katana <- routes |>
  dplyr::filter(
    network == 11,
    grepl(
      "katana",
      sentinel_site,
      ignore.case = TRUE
    )
  )

if (nrow(katana) > 0) {

  print(
    katana |>
      dplyr::select(
        province,
        sentinel_site,
        travel_hours,
        walking_route_km
      )
  )
}
