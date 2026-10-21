
# 05 — Results and network comparison

source("00_packages.R")

out_dir <- "output/unified"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# 1. Assigned DPS-to-site travel times

journeys <- readr::read_csv(
  file.path(out_dir, "Table_assigned_travel_times.csv"),
  show_col_types = FALSE
)

stopifnot(
  nrow(journeys) == 176,
  all(c(
    "network", "period", "mode", "province",
    "dps_office", "sentinel_site",
    "dps_longitude", "dps_latitude",
    "site_longitude", "site_latitude",
    "travel_hours", "qc_flag"
  ) %in% names(journeys))
)

finite_median <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  median(x)
}

finite_quantile <- function(x, p) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  as.numeric(quantile(x, p))
}

finite_max <- function(x) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NA_real_)
  max(x)
}

journey_summary <- journeys |>
  dplyr::group_by(network, period, mode) |>
  dplyr::summarise(
    sites = dplyr::n(),
    reachable = sum(is.finite(travel_hours)),
    median_hours = finite_median(travel_hours),
    q25_hours = finite_quantile(travel_hours, 0.25),
    q75_hours = finite_quantile(travel_hours, 0.75),
    p90_hours = finite_quantile(travel_hours, 0.90),
    max_hours = finite_max(travel_hours),
    qc_flags = sum(!is.na(qc_flag) & qc_flag != ""),
    .groups = "drop"
  ) |>
  dplyr::arrange(mode, network) |>
  dplyr::mutate(
    dplyr::across(
      dplyr::ends_with("_hours"),
      ~ round(.x, 2)
    )
  )

print(journey_summary)

readr::write_csv(
  journey_summary,
  file.path(out_dir, "Table_network_journey_summary.csv")
)

# 2. Compare walking and motorised time for the same journeys

journey_id <- c(
  "network", "period", "province",
  "dps_office", "sentinel_site",
  "dps_longitude", "dps_latitude",
  "site_longitude", "site_latitude"
)

paired <- journeys |>
  dplyr::select(
    dplyr::all_of(journey_id),
    mode,
    travel_hours
  ) |>
  tidyr::pivot_wider(
    names_from = mode,
    values_from = travel_hours
  )

stopifnot(
  nrow(paired) == 88,
  all(c("walking", "motorized") %in% names(paired))
)

paired <- paired |>
  dplyr::mutate(
    difference_hours = walking - motorized,
    motorized_longer = (
      is.finite(walking) &
        is.finite(motorized) &
        motorized > walking
    )
  )

print(
  paired |>
    dplyr::group_by(network) |>
    dplyr::summarise(
      journeys = dplyr::n(),
      median_walking = round(finite_median(walking), 2),
      median_motorized = round(finite_median(motorized), 2),
      motorized_longer_count = sum(motorized_longer),
      .groups = "drop"
    )
)

readr::write_csv(
  paired,
  file.path(out_dir, "Table_walking_vs_motorized.csv")
)

# 3. Summarise validated walking-route distances

route_file <- file.path(
  out_dir, "walking_route_distances.csv"
)

if (file.exists(route_file)) {

  routes <- readr::read_csv(
    route_file,
    show_col_types = FALSE
  )

  if ("walking_route_km" %in% names(routes)) {

    valid_routes <- routes$walking_route_km[
      is.finite(routes$walking_route_km)
    ]

    route_overview <- data.frame(
      route_table_rows = nrow(routes),
      routes_with_distance = length(valid_routes),
      median_route_km = if (length(valid_routes)) {
        round(median(valid_routes), 2)
      } else NA_real_,
      max_route_km = if (length(valid_routes)) {
        round(max(valid_routes), 2)
      } else NA_real_
    )

    print(route_overview)

    readr::write_csv(
      route_overview,
      file.path(out_dir, "Table_route_distance_overview.csv")
    )

  } else {

    message(
      "Existing route table uses different distance columns. ",
      "Its contents have been preserved."
    )

    print(names(routes))
  }
}

# 4. Prepare national boundaries for area comparisons

zones <- sf::st_read(
  "GRID3_COD_health_zones/GRID3_COD_health_zones_v9_0.shp",
  quiet = TRUE
) |>
  sf::st_make_valid() |>
  sf::st_transform(4326)

country <- sf::st_sf(
  geometry = sf::st_union(sf::st_geometry(zones))
)

country_vect <- terra::vect(country)

# 5. Calculate area within accessibility thresholds

access_file <- function(mode, network) {
  file.path(
    out_dir,
    paste0(
      "accessibility_sentinel_",
      mode, "_", network, ".tif"
    )
  )
}

summarise_accessibility <- function(mode, network) {

  file <- access_file(mode, network)

  stopifnot(file.exists(file))

  r <- terra::rast(file)

  # Apply the same modern national boundary to every scenario
  r <- terra::crop(
    r,
    country_vect,
    mask = TRUE
  )

  # Cell area in square kilometres
  area <- terra::cellSize(
    r,
    unit = "km",
    mask = TRUE
  )

  modelled_area <- terra::global(
    area,
    "sum",
    na.rm = TRUE
  )[1, 1]

  stopifnot(
    is.finite(modelled_area),
    modelled_area > 0
  )

  thresholds <- if (mode == "walking") {
    c(6, 12, 24, 48, 72)
  } else {
    c(1, 3, 6, 12, 24)
  }

  results <- lapply(thresholds, function(h) {

    within <- terra::ifel(
      r <= h,
      area,
      0
    )

    area_within <- terra::global(
      within,
      "sum",
      na.rm = TRUE
    )[1, 1]

    data.frame(
      network = network,
      mode = mode,
      threshold_hours = h,
      modelled_area_km2 = modelled_area,
      area_within_km2 = area_within,
      percent_modelled_area = round(
        100 * area_within / modelled_area,
        2
      )
    )
  })

  dplyr::bind_rows(results)
}

spatial_results <- list()

for (mode in c("walking", "motorized")) {

  for (network in c(11, 26, 51)) {

    message(
      "Summarising spatial accessibility: ",
      mode, " / ", network, " sites"
    )

    spatial_results[[
      paste(mode, network, sep = "_")
    ]] <- summarise_accessibility(
      mode,
      network
    )

    invisible(gc(verbose = FALSE))
  }
}

spatial_summary <- dplyr::bind_rows(spatial_results)

print(spatial_summary)

readr::write_csv(
  spatial_summary,
  file.path(out_dir, "Table_spatial_accessibility_summary.csv")
)

# 6. Check improvement in nearest-site accessibility

spatial_wide <- spatial_summary |>
  dplyr::select(
    mode,
    threshold_hours,
    network,
    percent_modelled_area
  ) |>
  tidyr::pivot_wider(
    names_from = network,
    values_from = percent_modelled_area,
    names_prefix = "sites_"
  )

spatial_wide <- spatial_wide |>
  dplyr::mutate(
    change_11_to_26 = sites_26 - sites_11,
    change_26_to_51 = sites_51 - sites_26
  )

print(spatial_wide)

readr::write_csv(
  spatial_wide,
  file.path(out_dir, "Table_spatial_accessibility_comparison.csv")
)

# 7. Figure 4 — Assigned journey times

network_colors <- c(
  "11 sites" = "#8E44AD",
  "26 sites" = "#E64B35",
  "51 sites" = "#F4A300"
)

journeys$network_label <- factor(
  paste(journeys$network, "sites"),
  levels = names(network_colors)
)

p_journeys <- ggplot(
  journeys |>
    dplyr::filter(is.finite(travel_hours)),
  aes(
    x = network_label,
    y = travel_hours,
    fill = network_label
  )
) +

  geom_boxplot(
    width = 0.55,
    alpha = 0.55,
    outlier.shape = NA
  ) +

  geom_jitter(
    width = 0.12,
    height = 0,
    size = 1.4,
    alpha = 0.6
  ) +

  facet_wrap(
    ~mode,
    ncol = 1,
    scales = "free_y"
  ) +

  scale_fill_manual(
    values = network_colors,
    guide = "none"
  ) +

  labs(
    title = "Travel time from DPS offices to assigned sentinel sites",
    subtitle = "Distribution of modelled journeys by network",
    x = NULL,
    y = "Travel time (hours)",
    caption = paste(
      "Descriptive distributions; different networks include",
      "different assigned journeys.",
      "Friction surfaces represent MAP 2020 conditions."
    )
  ) +

  theme_minimal(base_size = 12) +

  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold"),
    strip.text = element_text(face = "bold"),
    legend.position = "none"
  )

ggsave(
  file.path(
    out_dir,
    "Figure4_assigned_travel_time_distributions.png"
  ),
  p_journeys,
  width = 10,
  height = 8,
  dpi = 180,
  bg = "white"
)

rm(p_journeys)
invisible(gc(verbose = FALSE))

# 8. Figure 5 — Walking versus motorised travel time

p_modes <- ggplot(
  paired |>
    dplyr::filter(
      is.finite(walking),
      is.finite(motorized)
    ),
  aes(
    x = walking,
    y = motorized
  )
) +

  geom_abline(
    intercept = 0,
    slope = 1,
    linetype = "dashed",
    colour = "grey55"
  ) +

  geom_point(
    size = 2,
    alpha = 0.65,
    colour = "#2B65AD"
  ) +

  facet_wrap(
    ~network,
    labeller = as_labeller(
      c(
        "11" = "2003–2005: 11 sites",
        "26" = "2014: 26 sites",
        "51" = "2021: 51 sites"
      )
    )
  ) +

  labs(
    title = "Walking and motorised travel times for assigned journeys",
    subtitle = "Each point represents one DPS-to-site journey",
    x = "Walking travel time (hours)",
    y = "Motorised travel time (hours)",
    caption = "The dashed line represents equal walking and motorised times."
  ) +

  theme_minimal(base_size = 12) +

  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold"),
    strip.text = element_text(face = "bold")
  )

ggsave(
  file.path(
    out_dir,
    "Figure5_walking_vs_motorized.png"
  ),
  p_modes,
  width = 12,
  height = 5,
  dpi = 180,
  bg = "white"
)

rm(p_modes)
invisible(gc(verbose = FALSE))

# 9. Figure 6 — Spatial accessibility across networks

plot_spatial <- spatial_summary |>
  dplyr::filter(
    (mode == "walking" & threshold_hours == 24) |
      (mode == "motorized" & threshold_hours == 6)
  ) |>
  dplyr::mutate(
    network_label = factor(
      paste(network, "sites"),
      levels = names(network_colors)
    ),
    indicator = ifelse(
      mode == "walking",
      "Walking: within 24 hours",
      "Motorised: within 6 hours"
    )
  )

p_spatial <- ggplot(
  plot_spatial,
  aes(
    x = network_label,
    y = percent_modelled_area,
    fill = network_label
  )
) +

  geom_col(width = 0.6) +

  geom_text(
    aes(
      label = paste0(
        round(percent_modelled_area, 1),
        "%"
      )
    ),
    vjust = -0.4,
    size = 3.5
  ) +

  facet_wrap(
    ~indicator,
    ncol = 2
  ) +

  scale_fill_manual(
    values = network_colors,
    guide = "none"
  ) +

  scale_y_continuous(
    limits = c(0, 105),
    breaks = c(0, 25, 50, 75, 100)
  ) +

  labs(
    title = "Spatial accessibility to the nearest sentinel site",
    subtitle = "Comparison of historical, existing and proposed networks",
    x = NULL,
    y = "Percentage of modelled area",
    caption = paste(
      "Area-weighted percentage of raster cells with valid travel-time estimates.",
      "All scenarios use the same DRC boundary.",
      "These estimates are not population-weighted."
    )
  ) +

  theme_minimal(base_size = 12) +

  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold"),
    strip.text = element_text(face = "bold")
  )

ggsave(
  file.path(
    out_dir,
    "Figure6_spatial_accessibility_comparison.png"
  ),
  p_spatial,
  width = 11,
  height = 6,
  dpi = 180,
  bg = "white"
)

rm(p_spatial)
invisible(gc(verbose = FALSE))

# 10. Record software environment

capture.output(
  sessionInfo(),
  file = file.path(
    out_dir,
    "R_session_information.txt"
  )
)
