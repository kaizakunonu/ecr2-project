
# 03 — Travel time from DPS offices to assigned sentinel sites

source("R/00_packages.R")

out_dir <- "output/unified"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_dir, "matrices"), recursive = TRUE, showWarnings = FALSE)

# 1. Input data and transition models

transition_files <- c(
  walking = "output/transition_walk_drc_gc.rds",
  motorized = "output/transition_motorized_drc_gc_50km.rds"
)

friction_files <- c(
  walking = "output/friction_walk_drc_buffer.tif",
  motorized = "output/friction_motorized_drc_buffer_50km.tif"
)

stopifnot(
  all(file.exists(transition_files)),
  all(file.exists(friction_files))
)

networks <- list(
  "11" = list(
    dps = "output/dps_11.csv",
    sites = "output/ss_11.csv",
    period = "2003–2005"
  ),
  "26" = list(
    dps = "output/dps_26.csv",
    sites = "output/ss_26.csv",
    period = "2014"
  ),
  "51" = list(
    dps = "output/dps_26.csv",
    sites = "output/network_51/ss_51.csv",
    period = "2021 proposed"
  )
)

# 2. Validate coordinates and site assignments

valid_coordinates <- function(x) {
  is.finite(x$longitude) &
    is.finite(x$latitude) &
    x$longitude >= -180 &
    x$longitude <= 180 &
    x$latitude >= -90 &
    x$latitude <= 90
}

load_network <- function(network) {

  info <- networks[[network]]

  dps <- readr::read_csv(
    info$dps,
    show_col_types = FALSE
  )

  sites <- readr::read_csv(
    info$sites,
    show_col_types = FALSE
  )

  stopifnot(
    all(c("dps_province", "longitude", "latitude") %in%
          names(dps)),
    all(c("sentinel_site", "longitude", "latitude") %in%
          names(sites))
  )

  for (column in c("longitude", "latitude")) {
    dps[[column]] <- as.numeric(dps[[column]])
    sites[[column]] <- as.numeric(sites[[column]])
  }

  stopifnot(
    all(valid_coordinates(dps)),
    all(valid_coordinates(sites)),
    !anyDuplicated(dps$dps_province)
  )

  if (network == "51") {

    stopifnot(
      nrow(dps) == 26,
      nrow(sites) == 51,
      all(c("dps_province", "network") %in% names(sites)),
      sum(sites$network == "2021_expansion") == 25
    )

    # Match each site to its provincial DPS
    dps_index <- match(
      sites$dps_province,
      dps$dps_province
    )

    if (anyNA(dps_index)) {
      stop(
        "Some proposed-network sites cannot be matched ",
        "to their provincial DPS. Check province names."
      )
    }

    province <- sites$dps_province

    site_stage <- ifelse(
      sites$network == "2021_expansion",
      "2021 proposed",
      "Existing"
    )

  } else {

    # Historical assignments were verified by row order
    n <- as.integer(network)

    stopifnot(
      nrow(dps) == n,
      nrow(sites) == n
    )

    dps_index <- seq_len(n)

    province <- dps$dps_province

    site_stage <- rep(
      if (network == "11") "Historical" else "Existing",
      n
    )
  }

  # Preserve verified Katana coordinates
  katana <- grep(
    "katana",
    sites$sentinel_site,
    ignore.case = TRUE
  )

  if (length(katana)) {

    stopifnot(
      all(abs(sites$latitude[katana] + 2.225) <= 0.10),
      all(abs(sites$longitude[katana] - 28.83139) <= 0.10)
    )
  }

  list(
    dps = dps,
    sites = sites,
    index = dps_index,
    province = province,
    stage = site_stage,
    period = info$period
  )
}

# 3. Calculate the full travel-time matrix

calculate_network <- function(mode, network, transition, friction) {

  x <- load_network(network)

  dps <- x$dps
  sites <- x$sites
  dps_index <- x$index

  origins <- as.matrix(
    dps[, c("longitude", "latitude")]
  )

  destinations <- as.matrix(
    sites[, c("longitude", "latitude")]
  )

  storage.mode(origins) <- "double"
  storage.mode(destinations) <- "double"

  # Check that every origin and destination lies on valid friction
  friction_values <- c(
    raster::extract(friction, origins),
    raster::extract(friction, destinations)
  )

  stopifnot(
    all(is.finite(friction_values)),
    all(friction_values > 0)
  )

  message(
    "Calculating ", mode,
    " travel times: ", network,
    " sentinel sites"
  )

  # Result: minutes from each DPS to every site
  time_minutes <- as.matrix(
    gdistance::costDistance(
      transition,
      origins,
      destinations
    )
  )

  stopifnot(
    nrow(time_minutes) == nrow(dps),
    ncol(time_minutes) == nrow(sites)
  )

  rownames(time_minutes) <- dps$dps_province

  colnames(time_minutes) <- make.unique(
    as.character(sites$sentinel_site)
  )

  # Extract the correctly assigned DPS-to-site journeys
  assigned_minutes <- time_minutes[
    cbind(dps_index, seq_len(nrow(sites)))
  ]

  # Save full DPS-to-site matrix
  matrix_table <- data.frame(
    DPS = dps$dps_province,
    time_minutes,
    check.names = FALSE
  )

  readr::write_csv(
    matrix_table,
    file.path(
      file.path(out_dir, "matrices"),
      paste0(
        "Matrix_DPS_to_sites_",
        mode, "_", network, "_minutes.csv"
      )
    )
  )

  # 4. Calculate straight-line geographical distance

  dps_points <- sf::st_as_sf(
    dps,
    coords = c("longitude", "latitude"),
    crs = 4326
  )

  site_points <- sf::st_as_sf(
    sites,
    coords = c("longitude", "latitude"),
    crs = 4326
  )

  straight_km <- as.numeric(
    sf::st_distance(
      dps_points[dps_index, ],
      site_points,
      by_element = TRUE
    )
  ) / 1000

  assigned_hours <- assigned_minutes / 60

  effective_kmh <- ifelse(
    is.finite(assigned_hours) & assigned_hours > 0,
    straight_km / assigned_hours,
    NA_real_
  )

  # 5. Quality-control flags

  qc_flag <- dplyr::case_when(
    !is.finite(assigned_minutes) ~
      "Unreachable: review route and coordinates",

    assigned_minutes == 0 & straight_km > 0.01 ~
      "Zero time: coordinates may share a raster cell",

    mode == "walking" &
      straight_km > 2 &
      is.finite(effective_kmh) &
      effective_kmh < 1.5 ~
      "Very low effective walking speed: review",

    mode == "motorized" &
      straight_km > 10 &
      is.finite(effective_kmh) &
      effective_kmh < 10 ~
      "Low effective motorised speed: review",

    TRUE ~ ""
  )

  results <- data.frame(
    network = as.integer(network),
    period = x$period,
    stage = x$stage,
    mode = mode,
    province = x$province,
    dps_office = dps$dps_province[dps_index],
    sentinel_site = sites$sentinel_site,
    dps_longitude = dps$longitude[dps_index],
    dps_latitude = dps$latitude[dps_index],
    site_longitude = sites$longitude,
    site_latitude = sites$latitude,
    travel_minutes = assigned_minutes,
    travel_hours = assigned_hours,
    straight_km = straight_km,
    effective_kmh = effective_kmh,
    qc_flag = qc_flag
  )

  stopifnot(nrow(results) == as.integer(network))

  results
}

# 6. Run walking and motorised travel-time models

all_results <- list()

for (mode in c("walking", "motorized")) {

  transition <- readRDS(
    transition_files[[mode]]
  )

  friction <- raster::raster(
    friction_files[[mode]]
  )

  stopifnot(
    identical(
      as.integer(dim(transition)[1:2]),
      as.integer(dim(friction)[1:2])
    )
  )

  for (network in c("11", "26", "51")) {

    result <- calculate_network(
      mode,
      network,
      transition,
      friction
    )

    all_results[[paste(mode, network, sep = "_")]] <- result
  }

  rm(transition, friction)
  invisible(gc(verbose = FALSE))
}

journeys <- dplyr::bind_rows(all_results)

# 7. Validate results

counts <- journeys |>
  dplyr::count(mode, network, name = "journeys")

print(counts)

expected_counts <- data.frame(
  mode = rep(c("walking", "motorized"), each = 3),
  network = rep(c(11L, 26L, 51L), times = 2),
  expected = rep(c(11L, 26L, 51L), times = 2)
)

checks <- dplyr::left_join(
  expected_counts,
  counts,
  by = c("mode", "network")
)

stopifnot(
  nrow(journeys) == 176,
  all(checks$journeys == checks$expected),
  all(journeys$travel_minutes >= 0 |
        !is.finite(journeys$travel_minutes))
)

# 8. Save assigned travel-time results

readr::write_csv(
  journeys,
  file.path(
    out_dir,
    "Table_assigned_travel_times.csv"
  )
)

# 9. Summarise travel times by mode and network

summary_table <- journeys |>
  dplyr::group_by(mode, network, period) |>
  dplyr::summarise(
    sites = dplyr::n(),
    unreachable = sum(!is.finite(travel_hours)),
    median_hours = if (any(is.finite(travel_hours))) {
      median(travel_hours[is.finite(travel_hours)])
    } else NA_real_,
    mean_hours = if (any(is.finite(travel_hours))) {
      mean(travel_hours[is.finite(travel_hours)])
    } else NA_real_,
    p90_hours = if (any(is.finite(travel_hours))) {
      as.numeric(quantile(
        travel_hours[is.finite(travel_hours)],
        0.90
      ))
    } else NA_real_,
    max_hours = if (any(is.finite(travel_hours))) {
      max(travel_hours[is.finite(travel_hours)])
    } else NA_real_,
    flagged = sum(qc_flag != ""),
    .groups = "drop"
  ) |>
  dplyr::arrange(mode, network) |>
  dplyr::mutate(
    dplyr::across(
      c(median_hours, mean_hours, p90_hours, max_hours),
      ~ round(.x, 2)
    )
  )

print(summary_table)

readr::write_csv(
  summary_table,
  file.path(
    out_dir,
    "Table_assigned_travel_time_summary.csv"
  )
)

# 10. Save quality-control cases separately

qc_cases <- journeys |>
  dplyr::filter(qc_flag != "")

readr::write_csv(
  qc_cases,
  file.path(
    out_dir,
    "Table_assigned_travel_time_QC.csv"
  )
)
