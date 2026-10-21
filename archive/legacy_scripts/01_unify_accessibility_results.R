
# ============================================================
# DRC SENTINEL SITE ACCESSIBILITY
# 01 — UNIFY EXISTING RESULTS
#
# Networks: 11, 26 and 51 sites
# Modes: walking and MAP motorised
#
# Original files are preserved.
# New outputs: output/unified/
# ============================================================


# ------------------------------------------------------------
# 1. PACKAGES AND OUTPUT DIRECTORY
# ------------------------------------------------------------

library(sf)
library(dplyr)
library(ggplot2)

out_dir <- "output/unified"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


# ------------------------------------------------------------
# 2. EXISTING RESULTS
# ------------------------------------------------------------

config <- data.frame(
  network = c(11, 26, 51, 11, 26, 51),
  
  mode = c(
    "walking", "walking", "walking",
    "motorized", "motorized", "motorized"
  ),
  
  file = c(
    "output/network_11/Table1_DPS_to_site_11.csv",
    "output/network_26/Table1_DPS_to_site_26.csv",
    "output/network_51/Table1_DPS_to_site_51.csv",
    
    "output/network_11/motorized/Table1_DPS_to_site_motorized_11.csv",
    "output/network_26/motorized/Table1_DPS_to_site_motorized_26.csv",
    "output/network_51/motorized/Table1_DPS_to_site_motorized_51.csv"
  )
)

stopifnot(all(file.exists(config$file)))


# ------------------------------------------------------------
# 3. LOAD AND CLASSIFY SENTINEL SITES
# ------------------------------------------------------------

ss11 <- read.csv("output/ss_11.csv")
ss26 <- read.csv("output/ss_26.csv")
ss51 <- read.csv("output/network_51/ss_51.csv")

clean_name <- function(x) {
  
  x <- trimws(as.character(x))
  
  z <- iconv(
    x,
    to = "ASCII//TRANSLIT"
  )
  
  z[is.na(z)] <- x[is.na(z)]
  
  gsub("[^a-z0-9]", "", tolower(z))
}

historical_names <- clean_name(ss11$sentinel_site)

reference_names <- clean_name(ss51$sentinel_site)

stopifnot(
  nrow(ss11) == 11,
  nrow(ss26) == 26,
  nrow(ss51) == 51,
  !anyDuplicated(reference_names),
  all(historical_names %in% reference_names),
  all(clean_name(ss26$sentinel_site) %in% reference_names)
)

ss51$stage <- ifelse(
  clean_name(ss51$sentinel_site) %in% historical_names,
  "Historical 11",
  ifelse(
    ss51$network == "2021_expansion",
    "2021 proposed 25",
    "2014 additional 15"
  )
)

stage_levels <- c(
  "Historical 11",
  "2014 additional 15",
  "2021 proposed 25"
)

stage_colors <- c(
  "Historical 11" = "#7546A8",
  "2014 additional 15" = "#2582B7",
  "2021 proposed 25" = "#E59A30"
)

get_stage <- function(site_names) {
  
  index <- match(
    clean_name(site_names),
    reference_names
  )
  
  if (anyNA(index)) {
    stop(
      "Unmatched sentinel site: ",
      paste(site_names[is.na(index)], collapse = ", ")
    )
  }
  
  ss51$stage[index]
}


# ------------------------------------------------------------
# 4. READ ALL SIX TRAVEL-TIME TABLES
# ------------------------------------------------------------

read_scenario <- function(i) {
  
  net <- config$network[i]
  mode <- config$mode[i]
  file <- config$file[i]
  
  x <- read.csv(
    file,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  
  time_column <- if (mode == "walking") {
    "Walking time (hours)"
  } else {
    "Motorised time (hours)"
  }
  
  required <- c(
    "Province",
    "Sentinel site",
    "Straight-line distance (km)",
    time_column
  )
  
  if (!all(required %in% names(x))) {
    stop("Missing columns in: ", file)
  }
  
  if (nrow(x) != net) {
    stop("Unexpected number of sites in: ", file)
  }
  
  data.frame(
    network = net,
    mode = mode,
    
    province = x[["Province"]],
    sentinel_site = x[["Sentinel site"]],
    
    site_key = clean_name(x[["Sentinel site"]]),
    
    stage = get_stage(x[["Sentinel site"]]),
    
    straight_km = as.numeric(
      x[["Straight-line distance (km)"]]
    ),
    
    time_hours = as.numeric(
      x[[time_column]]
    ),
    
    source_file = file,
    
    stringsAsFactors = FALSE
  )
}

results <- do.call(
  rbind,
  lapply(seq_len(nrow(config)), read_scenario)
)

rownames(results) <- NULL

stopifnot(nrow(results) == 176)

if (
  any(!is.finite(results$time_hours)) ||
  any(results$time_hours < 0)
) {
  stop("Invalid travel time detected.")
}


# ------------------------------------------------------------
# 5. VALIDATE NETWORK COMPOSITION
# ------------------------------------------------------------

count_check <- with(
  subset(results, mode == "walking"),
  table(
    factor(network, levels = c(11, 26, 51)),
    factor(stage, levels = stage_levels)
  )
)

expected <- matrix(
  c(
    11, 0, 0,
    11, 15, 0,
    11, 15, 25
  ),
  nrow = 3,
  byrow = TRUE
)

cat("\n========== NETWORK COMPOSITION ==========\n")

print(count_check)

stopifnot(
  all(as.matrix(count_check) == expected)
)


# ------------------------------------------------------------
# 6. VERIFY THE 26 SHARED SITES
# ------------------------------------------------------------

cat("\n========== 26 VS 51 CONSISTENCY ==========\n")

for (travel_mode in c("walking", "motorized")) {
  
  a <- subset(
    results,
    network == 26 & mode == travel_mode,
    select = c("site_key", "time_hours")
  )
  
  b <- subset(
    results,
    network == 51 & mode == travel_mode,
    select = c("site_key", "time_hours")
  )
  
  compare <- merge(
    a,
    b,
    by = "site_key",
    suffixes = c("_26", "_51")
  )
  
  stopifnot(nrow(compare) == 26)
  
  difference <- abs(
    compare$time_hours_26 -
      compare$time_hours_51
  )
  
  cat(
    travel_mode,
    ": maximum difference =",
    max(difference),
    "hours\n"
  )
  
  if (any(difference > 0.11)) {
    stop(
      "Unexpected difference between 26 and 51 sites."
    )
  }
}


# ------------------------------------------------------------
# 7. ADD OPERATIONAL TRAVEL-TIME CATEGORIES
# ------------------------------------------------------------

results$time_category <- NA_character_

walking <- results$mode == "walking"

results$time_category[walking] <- as.character(
  cut(
    results$time_hours[walking],
    breaks = c(-Inf, 3, 6, 12, Inf),
    labels = c(
      "0-3 hours",
      ">3-6 hours",
      ">6-12 hours",
      ">12 hours"
    )
  )
)

results$time_category[!walking] <- as.character(
  cut(
    results$time_hours[!walking],
    breaks = c(-Inf, 1, 3, 6, Inf),
    labels = c(
      "0-1 hour",
      ">1-3 hours",
      ">3-6 hours",
      ">6 hours"
    )
  )
)

# Categories represent modelled continuous travel,
# not validated working-day or overnight schedules.


# ------------------------------------------------------------
# 8. CLASSIFY ZERO TRAVEL TIMES
# ------------------------------------------------------------

results$zero_time_note <- ifelse(
  results$time_hours == 0 &
    results$straight_km == 0,
  
  "Co-located or zero after rounding",
  
  ifelse(
    results$time_hours == 0 &
      results$straight_km > 0,
    
    "Nonzero distance: inspect raster resolution or rounding",
    
    ""
  )
)


# ------------------------------------------------------------
# 9. GENERATE ONE SUMMARY TABLE
# ------------------------------------------------------------

summarise_scenario <- function(i) {
  
  net <- config$network[i]
  travel_mode <- config$mode[i]
  
  x <- subset(
    results,
    network == net & mode == travel_mode
  )
  
  data.frame(
    Network = net,
    Mode = travel_mode,
    
    Sites = nrow(x),
    
    Median_hours = median(x$time_hours),
    
    Min_hours = min(x$time_hours),
    
    Max_hours = max(x$time_hours),
    
    Zero_time_sites = sum(x$time_hours == 0),
    
    Zero_with_nonzero_distance = sum(
      x$time_hours == 0 & x$straight_km > 0
    ),
    
    stringsAsFactors = FALSE
  )
}

summary_table <- do.call(
  rbind,
  lapply(seq_len(nrow(config)), summarise_scenario)
)

cat("\n========== UNIFIED SUMMARY ==========\n")

print(summary_table, row.names = FALSE)


# ------------------------------------------------------------
# 10. SAVE CONSOLIDATED TABLES
# ------------------------------------------------------------

write.csv(
  results,
  file.path(out_dir, "site_level_results.csv"),
  row.names = FALSE,
  na = ""
)

write.csv(
  summary_table,
  file.path(out_dir, "scenario_summary.csv"),
  row.names = FALSE
)

write.csv(
  subset(results, nzchar(zero_time_note)),
  file.path(out_dir, "zero_time_review.csv"),
  row.names = FALSE
)


# ------------------------------------------------------------
# 11. PREPARE NETWORK LOCATION MAPS
# ------------------------------------------------------------

prepare_map_points <- function(x, net) {
  
  data.frame(
    network = paste(net, "sites"),
    sentinel_site = x$sentinel_site,
    stage = get_stage(x$sentinel_site),
    longitude = x$longitude,
    latitude = x$latitude
  )
}

map_points <- rbind(
  prepare_map_points(ss11, 11),
  prepare_map_points(ss26, 26),
  prepare_map_points(ss51, 51)
)

map_points$network <- factor(
  map_points$network,
  levels = c(
    "11 sites",
    "26 sites",
    "51 sites"
  )
)

map_points$stage <- factor(
  map_points$stage,
  levels = stage_levels
)


# ------------------------------------------------------------
# 12. LOAD CURRENT PROVINCIAL BOUNDARIES
# ------------------------------------------------------------

zones <- sf::st_read(
  paste0(
    "GRID3_COD_health_zones/",
    "GRID3_COD_health_zones_v9_0.shp"
  ),
  quiet = TRUE
)

stopifnot("province" %in% names(zones))

provinces <- zones |>
  sf::st_make_valid() |>
  sf::st_transform(4326) |>
  dplyr::group_by(province) |>
  dplyr::summarise(.groups = "drop")


# ------------------------------------------------------------
# 13. FIGURE 1 — NETWORK EVOLUTION
# ------------------------------------------------------------

p_network <- ggplot() +
  
  geom_sf(
    data = provinces,
    fill = "grey97",
    colour = "grey65",
    linewidth = 0.2
  ) +
  
  geom_point(
    data = map_points,
    aes(
      x = longitude,
      y = latitude,
      colour = stage
    ),
    size = 2.5
  ) +
  
  scale_colour_manual(
    values = stage_colors,
    drop = FALSE,
    name = "Site group"
  ) +
  
  facet_wrap(
    ~network,
    nrow = 1
  ) +
  
  coord_sf(
    datum = NA,
    expand = FALSE
  ) +
  
  labs(
    title = "Evolution of sentinel surveillance sites in DRC",
    subtitle = "Historical, existing and proposed networks",
    caption = paste(
      "Modern provincial boundaries shown for comparison.",
      "The 2021 sites represent proposed locations."
    ),
    x = NULL,
    y = NULL
  ) +
  
  theme_minimal(base_size = 11) +
  
  theme(
    panel.grid = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.title = element_text(face = "bold"),
    legend.position = "bottom"
  )

print(p_network)

ggsave(
  file.path(out_dir, "Figure1_network_evolution.png"),
  p_network,
  width = 13,
  height = 6,
  dpi = 200,
  bg = "white"
)


# ------------------------------------------------------------
# 14. FIGURE 2 — TRAVEL-TIME COMPARISON
# ------------------------------------------------------------

plot_results <- results

plot_results$network <- factor(
  plot_results$network,
  levels = c(11, 26, 51),
  labels = c("11 sites", "26 sites", "51 sites")
)

plot_results$stage <- factor(
  plot_results$stage,
  levels = stage_levels
)

plot_results$mode <- factor(
  plot_results$mode,
  levels = c("walking", "motorized"),
  labels = c("Walking", "MAP motorised")
)

p_times <- ggplot(
  plot_results,
  aes(
    x = network,
    y = time_hours
  )
) +
  
  geom_boxplot(
    width = 0.5,
    outlier.shape = NA,
    fill = "grey95",
    colour = "grey35"
  ) +
  
  geom_jitter(
    aes(colour = stage),
    width = 0.13,
    height = 0,
    alpha = 0.8,
    size = 1.8
  ) +
  
  scale_colour_manual(
    values = stage_colors,
    name = "Site group"
  ) +
  
  facet_wrap(
    ~mode,
    scales = "free_y"
  ) +
  
  labs(
    title = "Travel time from DPS offices to sentinel sites",
    subtitle = "Existing modelled results across three networks",
    x = "Sentinel network",
    y = "Modelled travel time (hours)",
    caption = paste(
      "26- and 51-site results contain shared locations.",
      "Times are rounded values from existing tables."
    )
  ) +
  
  theme_minimal(base_size = 11) +
  
  theme(
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold"),
    legend.position = "bottom"
  )

print(p_times)

ggsave(
  file.path(out_dir, "Figure2_travel_time_comparison.png"),
  p_times,
  width = 12,
  height = 6,
  dpi = 200,
  bg = "white"
)


# ------------------------------------------------------------
# 15. RECORD METHODOLOGICAL LIMITATIONS
# ------------------------------------------------------------

limitations <- c(
  "DRC SENTINEL SITE ACCESSIBILITY — METHOD NOTES",
  "",
  "1. Networks: 11 historical, 26 existing, 51 mapped expanded sites.",
  "2. Historical locations are evaluated with circa-2020 friction.",
  "3. Historical analysis is not a reconstruction of past roads.",
  "4. Walking and MAP motorised are modelled baseline scenarios.",
  "5. MAP motorised is not a motorcycle-specific or 4x4-specific model.",
  "6. Motorcycle and 4x4 scenarios require explicit accessibility",
  "   and speed assumptions and remain uncalibrated.",
  "7. Road-surface and passability information is incomplete.",
  "8. Wet-season and dry-season travel may differ.",
  "9. Times represent continuous least-cost modelled travel.",
  "10. Rest, overnight stays, security and operational delays",
  "    are not explicitly represented.",
  "11. Zero travel times may reflect co-location, raster resolution",
  "    or rounding. They do not necessarily mean zero real travel.",
  "12. Network comparisons include repeated historical sites.",
  "13. Friction surfaces may allow cross-border routes.",
  "14. Assigned-DPS travel time differs from nearest-DPS access.",
  "15. Straight-line distance is not road or walking-route distance.",
  "16. Figures are descriptive and do not prove surveillance",
  "    network effectiveness or epidemiological representativeness."
)

writeLines(
  limitations,
  file.path(out_dir, "methodological_limitations.txt")
)

cat("\n========================================\n")
cat("UNIFIED BASELINE RESULTS COMPLETED\n")
cat("Scenarios: 6\n")
cat("Site-mode-network records:", nrow(results), "\n")
cat("Results folder:", out_dir, "\n")
cat("Original input files preserved.\n")
cat("========================================\n")
