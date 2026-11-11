
# 06 — Complete DRC sentinel-site analysis

run_analysis <- function(full_rebuild = FALSE) {

  previous_options <- options(
    drc.full_rebuild = full_rebuild,
    drc.rebuild_routes = full_rebuild
  )

  on.exit(
    options(previous_options),
    add = TRUE
  )

  scripts <- c(
    "R/00_packages.R",
    "R/01_spatial_expansion_sentinel_sites.R",
    "R/02_accessibility.R",
    "R/03_assigned_travel_time.R",
    "R/04_walking_routes.R",
    "R/05_results_summary.R"
  )

  stopifnot(all(file.exists(scripts)))

  out_dir <- "output/unified"

  assigned_file <- file.path(
    out_dir,
    "Table_assigned_travel_times.csv"
  )

  # Run analyses in the correct order

  for (script in scripts) {

    # Reuse validated assigned travel times unless
    # a full rebuild has been explicitly requested.

    if (
      script == "R/03_assigned_travel_time.R" &&
      !full_rebuild &&
      file.exists(assigned_file)
    ) {

      existing <- readr::read_csv(
        assigned_file,
        show_col_types = FALSE
      )

      required_columns <- c(
        "network",
        "mode",
        "province",
        "dps_office",
        "sentinel_site",
        "dps_longitude",
        "dps_latitude",
        "site_longitude",
        "site_latitude",
        "travel_hours",
        "straight_km"
      )

      stopifnot(
        nrow(existing) == 176,
        all(required_columns %in% names(existing)),
        all(is.finite(existing$travel_hours)),
        all(is.finite(existing$straight_km))
      )

      counts <- table(
        factor(
          existing$network,
          levels = c(11, 26, 51)
        ),
        factor(
          existing$mode,
          levels = c("walking", "motorized")
        )
      )

      stopifnot(
        identical(
          as.integer(counts[, "walking"]),
          c(11L, 26L, 51L)
        ),
        identical(
          as.integer(counts[, "motorized"]),
          c(11L, 26L, 51L)
        )
      )

      rm(existing, counts)
      invisible(gc(verbose = FALSE))

      next
    }

    environment <- new.env(
      parent = globalenv()
    )

    sys.source(
      script,
      envir = environment
    )

    rm(environment)
    invisible(gc(verbose = FALSE))
  }

  # Verify final outputs

  outputs <- c(
    "Figure1_network_evolution_clean.png",
    "Figure1_network_evolution_labeled.png",
    "Figure2_walking_accessibility_final.png",
    "Figure3_motorized_accessibility_final.png",
    "FigureS1_walking_nearest_sentinel_sites.png",
    "FigureS2_motorized_nearest_sentinel_sites.png",
    "Figure4_assigned_travel_time_distributions.png",
    "Figure5_walking_vs_motorized.png",
    "Figure6_spatial_accessibility_comparison.png",
    "Table_accessibility_validation.csv",
    "Table_assigned_travel_times.csv",
    "Table_assigned_travel_time_summary.csv",
    "Table_assigned_travel_time_QC.csv",
    "walking_route_distances.csv",
    "walking_routes.gpkg",
    "Table_network_journey_summary.csv",
    "Table_spatial_accessibility_summary.csv",
    "Table_spatial_accessibility_comparison.csv",
    "accessibility_model_configuration.csv",
    "R_session_information.txt"
  )

  paths <- file.path(
    out_dir,
    outputs
  )

  status <- data.frame(
    output = outputs,
    exists = file.exists(paths),
    size_mb = round(
      file.info(paths)$size / 1024^2,
      2
    )
  )

  print(status, row.names = FALSE)

  stopifnot(
    all(status$exists),
    all(!is.na(status$size_mb)),
    all(file.info(paths)$size > 0)
  )

  invisible(status)
}

run_analysis(full_rebuild = FALSE)
