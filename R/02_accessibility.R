
# 02 — Accessibility analysis in DRC
# Reproducible walking and motorised travel-time modelling

source("R/00_packages.R")

# 1. Settings

full_rebuild <- isTRUE(getOption("drc.full_rebuild", FALSE))
make_figures <- TRUE

out_dir <- "output/unified"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

poster_dir <- "output/poster"
dir.create(poster_dir, recursive = TRUE, showWarnings = FALSE)

buffer_km <- 50
directions <- 8

panels <- c("11 sites", "26 sites", "51 sites")

panel_labels <- c(
  "11 sites" = "2003–2005: 11 sentinel sites",
  "26 sites" = "2014: 26 sentinel sites",
  "51 sites" = "2021: 26 existing + 25 proposed"
)

site_colors <- c(
  "Historical 11" = "#8E44AD",
  "2014 additional 15" = "#E64B35",
  "2021 proposed 25" = "#F4A300"
)

travel_colors <- c(
  "#DCECCF",
  "#B8E3D8",
  "#7FCFCF",
  "#44B6C9",
  "#2F8FC1",
  "#2B65AD",
  "#273C88"
)

# 2. Load locations

ss11 <- read.csv("output/ss_11.csv")
ss26 <- read.csv("output/ss_26.csv")
ss51 <- read.csv("output/network_51/ss_51.csv")

dps11 <- read.csv("output/dps_11.csv")
dps26 <- read.csv("output/dps_26.csv")

stopifnot(
  nrow(ss11) == 11,
  nrow(ss26) == 26,
  nrow(ss51) == 51,
  nrow(dps11) == 11,
  nrow(dps26) == 26,
  sum(ss51$network == "2021_expansion") == 25
)

clean_name <- function(x) {
  x <- trimws(as.character(x))
  z <- iconv(x, to = "ASCII//TRANSLIT")
  z[is.na(z)] <- x[is.na(z)]
  gsub("[^a-z0-9]", "", tolower(z))
}

prepare_sites <- function(x, panel_name) {
  data.frame(
    panel = panel_name,
    sentinel_site = x$sentinel_site,
    longitude = x$longitude,
    latitude = x$latitude
  )
}

sites <- dplyr::bind_rows(
  prepare_sites(ss11, "11 sites"),
  prepare_sites(ss26, "26 sites"),
  prepare_sites(ss51, "51 sites")
)

historical <- clean_name(ss11$sentinel_site)

proposed <- clean_name(
  ss51$sentinel_site[ss51$network == "2021_expansion"]
)

sites$stage <- ifelse(
  clean_name(sites$sentinel_site) %in% historical,
  "Historical 11",
  ifelse(
    clean_name(sites$sentinel_site) %in% proposed,
    "2021 proposed 25",
    "2014 additional 15"
  )
)

sites$panel <- factor(sites$panel, levels = panels)

sites$stage <- factor(
  sites$stage,
  levels = names(site_colors)
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

stopifnot(
  all(as.matrix(table(sites$panel, sites$stage)) == expected)
)

prepare_dps <- function(x, panel_name) {
  data.frame(
    panel = panel_name,
    longitude = x$longitude,
    latitude = x$latitude
  )
}

offices <- dplyr::bind_rows(
  prepare_dps(dps11, "11 sites"),
  prepare_dps(dps26, "26 sites"),
  prepare_dps(dps26, "51 sites")
)

offices$panel <- factor(offices$panel, levels = panels)

# 3. Load administrative boundaries

prov11 <- sf::st_read(
  "RDC_11_provinces_1988_2015/RDC_11_provinces_1988_2015.shp",
  quiet = TRUE
) |>
  sf::st_make_valid() |>
  sf::st_transform(4326)

zones <- sf::st_read(
  "GRID3_COD_health_zones/GRID3_COD_health_zones_v9_0.shp",
  quiet = TRUE
) |>
  sf::st_make_valid() |>
  sf::st_transform(4326)

prov26 <- zones |>
  dplyr::group_by(province) |>
  dplyr::summarise(.groups = "drop") |>
  sf::st_make_valid()

add_panel <- function(x, panel_name) {
  sf::st_sf(
    panel = rep(panel_name, nrow(x)),
    geometry = sf::st_geometry(x)
  )
}

boundaries <- dplyr::bind_rows(
  add_panel(prov11, "11 sites"),
  add_panel(prov26, "26 sites"),
  add_panel(prov26, "51 sites")
)

boundaries$panel <- factor(boundaries$panel, levels = panels)

make_outline <- function(x, panel_name) {
  sf::st_sf(
    panel = panel_name,
    geometry = sf::st_make_valid(
      sf::st_union(sf::st_geometry(x))
    )
  )
}

outlines <- dplyr::bind_rows(
  make_outline(prov11, "11 sites"),
  make_outline(prov26, "26 sites"),
  make_outline(prov26, "51 sites")
)

outlines$panel <- factor(outlines$panel, levels = panels)

canvas <- sf::st_as_sfc(
  sf::st_bbox(
    c(
      xmin = 11,
      ymin = -14.5,
      xmax = 32.5,
      ymax = 6.5
    ),
    crs = sf::st_crs(4326)
  )
)

make_mask <- function(x) {
  sf::st_sf(
    panel = as.character(x$panel[1]),
    geometry = sf::st_difference(
      canvas,
      sf::st_geometry(x)
    )
  )
}

outside_mask <- dplyr::bind_rows(
  make_mask(outlines[1, ]),
  make_mask(outlines[2, ]),
  make_mask(outlines[3, ])
)

outside_mask$panel <- factor(
  outside_mask$panel,
  levels = panels
)

# 4. Input coordinates for modelling

point_sets <- list(
  dps_11 = dps11,
  dps_26 = dps26,
  sentinel_11 = ss11,
  sentinel_26 = ss26,
  sentinel_51 = ss51
)

get_xy <- function(x) {
  xy <- as.matrix(x[, c("longitude", "latitude")])
  storage.mode(xy) <- "double"

  stopifnot(
    ncol(xy) == 2,
    all(is.finite(xy))
  )

  xy
}

# 5. Raster and transition file paths

friction_files <- c(
  walking = "output/friction_walk_drc_buffer.tif",
  motorized = "output/friction_motorized_drc_buffer_50km.tif"
)

transition_files <- c(
  walking = "output/transition_walk_drc_gc.rds",
  motorized = "output/transition_motorized_drc_gc_50km.rds"
)

map_datasets <- c(
  walking = "Explorer__2020_walking_only_friction_surface",
  motorized = "Explorer__2020_motorized_friction_surface"
)

access_file <- function(mode, target) {

  if (target == "dps_11") {
    return(file.path(
      out_dir,
      paste0("accessibility_", mode, "_11.tif")
    ))
  }

  if (target == "dps_26") {
    return(file.path(
      out_dir,
      paste0("accessibility_", mode, "_26.tif")
    ))
  }

  n <- sub("sentinel_", "", target)

  file.path(
    out_dir,
    paste0("accessibility_sentinel_", mode, "_", n, ".tif")
  )
}

# 6. Migrate previously validated sentinel rasters

migrate_existing <- function(mode) {

  for (n in c(11, 26, 51)) {

    old <- file.path(
      out_dir,
      paste0("test_nearest_sentinel_", mode, "_", n, ".tif")
    )

    new <- access_file(mode, paste0("sentinel_", n))

    if (!full_rebuild && !file.exists(new) && file.exists(old)) {

      copied <- file.copy(old, new)

      if (!copied) {
        stop("Could not copy existing raster: ", old)
      }

      message("Reused validated raster: ", new)
    }
  }
}

# 7. Build the DRC buffer

make_buffer <- function(mode) {

  national <- sf::st_union(sf::st_geometry(prov26))

  if (mode == "walking") {

    # Same geographic buffering approach as the walking analysis
    previous_s2 <- sf::sf_use_s2()
    on.exit(sf::sf_use_s2(previous_s2), add = TRUE)
    sf::sf_use_s2(TRUE)

    buffer <- sf::st_buffer(
      national,
      dist = buffer_km * 1000
    )

  } else {

    # Projected buffer used in the motorised analysis
    buffer <- national |>
      sf::st_transform("ESRI:102023") |>
      sf::st_buffer(dist = buffer_km * 1000) |>
      sf::st_transform(4326)
  }

  sf::st_as_sf(buffer)
}

# 8. Safely replace an output file

replace_output <- function(source_file, destination_file) {

  stopifnot(
    file.exists(source_file),
    file.info(source_file)$size > 0
  )

  copied <- file.copy(
    source_file,
    destination_file,
    overwrite = TRUE
  )

  if (!copied) {
    stop("Unable to write: ", destination_file)
  }

  invisible(destination_file)
}

# 9. Prepare or reuse the friction and transition model

prepare_transition <- function(mode) {

  fr_file <- friction_files[[mode]]
  tr_file <- transition_files[[mode]]

  need_friction <- full_rebuild || !file.exists(fr_file)
  need_transition <- full_rebuild || !file.exists(tr_file)

  if (need_friction) {

    if (!requireNamespace("malariaAtlas", quietly = TRUE)) {
      stop(
        "Install the malariaAtlas package to download ",
        "the MAP friction surface."
      )
    }

    message("Downloading MAP friction surface: ", mode)

    buffer <- make_buffer(mode)

    fr <- malariaAtlas::getRaster(
      dataset_id = map_datasets[[mode]],
      shp = buffer
    )

    stopifnot(
      terra::nlyr(fr) == 1,
      terra::is.lonlat(fr)
    )

    tmp_fr <- tempfile(
      tmpdir = "output",
      fileext = ".tif"
    )

    terra::writeRaster(
      fr,
      tmp_fr,
      overwrite = TRUE
    )

    friction <- raster::raster(tmp_fr)

  } else {

    message("Using cached friction raster: ", mode)

    friction <- raster::raster(fr_file)
  }

  if (need_transition) {

    message("Building transition model: ", mode)

    tr <- gdistance::transition(
      friction,
      transitionFunction = function(x) 1 / mean(x),
      directions = directions
    )

    tr <- gdistance::geoCorrection(
      tr,
      type = "c"
    )

    stopifnot(
      identical(
        as.integer(dim(tr)[1:2]),
        as.integer(dim(friction)[1:2])
      )
    )

    tmp_tr <- tempfile(
      tmpdir = "output",
      fileext = ".rds"
    )

    saveRDS(tr, tmp_tr)

    if (need_friction) {
      replace_output(tmp_fr, fr_file)
      unlink(tmp_fr)
    }

    replace_output(tmp_tr, tr_file)
    unlink(tmp_tr)

  } else {

    message("Using cached transition model: ", mode)

    tr <- readRDS(tr_file)

    stopifnot(
      identical(
        as.integer(dim(tr)[1:2]),
        as.integer(dim(friction)[1:2])
      )
    )

    if (need_friction) {
      replace_output(tmp_fr, fr_file)
      unlink(tmp_fr)
    }
  }

  list(
    friction = friction,
    transition = tr
  )
}

# 10. Calculate accessibility surfaces

calculate_accessibility <- function(mode) {

  targets <- names(point_sets)

  output_files <- vapply(
    targets,
    function(target) access_file(mode, target),
    character(1)
  )

  if (
    !full_rebuild &&
    all(file.exists(output_files))
  ) {

    message("Using existing accessibility rasters: ", mode)
    return(invisible(output_files))
  }

  model <- prepare_transition(mode)

  friction <- model$friction
  tr <- model$transition

  for (target in targets) {

    output_file <- access_file(mode, target)

    if (!full_rebuild && file.exists(output_file)) {
      next
    }

    message("Computing ", mode, ": ", target)

    xy <- get_xy(point_sets[[target]])

    friction_values <- raster::extract(
      friction,
      xy
    )

    if (
      anyNA(friction_values) ||
      any(!is.finite(friction_values)) ||
      any(friction_values <= 0)
    ) {
      stop(
        "Invalid friction cells for ", mode,
        " / ", target,
        ". Check the input coordinates."
      )
    }

    # Cost is in minutes; convert to hours
    access <- gdistance::accCost(
      tr,
      xy
    ) / 60

    source_hours <- raster::extract(
      access,
      xy
    )

    stopifnot(
      all(is.finite(source_hours)),
      all(abs(source_hours) < 0.001)
    )

    tmp_file <- tempfile(
      tmpdir = out_dir,
      fileext = ".tif"
    )

    raster::writeRaster(
      access,
      tmp_file,
      format = "GTiff",
      overwrite = TRUE
    )

    replace_output(tmp_file, output_file)

    unlink(tmp_file)

    rm(access)
    invisible(gc(verbose = FALSE))
  }

  rm(model, friction, tr)
  invisible(gc(verbose = FALSE))

  invisible(output_files)
}

# 11. Run the walking and motorised models

for (mode in c("walking", "motorized")) {

  migrate_existing(mode)

  calculate_accessibility(mode)
}

# 12. Validate the resulting accessibility rasters

validation <- list()

for (mode in c("walking", "motorized")) {

  for (target in names(point_sets)) {

    file <- access_file(mode, target)

    stopifnot(file.exists(file))

    r <- raster::raster(file)

    xy <- get_xy(point_sets[[target]])

    values <- raster::extract(r, xy)

    result <- data.frame(
      mode = mode,
      target = target,
      origins = nrow(xy),
      zero_hour_origins = sum(
        abs(values) < 0.001,
        na.rm = TRUE
      ),
      missing_values = sum(is.na(values))
    )

    validation[[length(validation) + 1]] <- result

    stopifnot(
      result$zero_hour_origins == result$origins,
      result$missing_values == 0
    )
  }
}

validation <- dplyr::bind_rows(validation)

print(validation)

readr::write_csv(
  validation,
  file.path(out_dir, "Table_accessibility_validation.csv")
)

# 13. Check the nested sentinel-site networks

for (mode in c("walking", "motorized")) {

  r11 <- raster::raster(
    access_file(mode, "sentinel_11")
  )

  r26 <- raster::raster(
    access_file(mode, "sentinel_26")
  )

  r51 <- raster::raster(
    access_file(mode, "sentinel_51")
  )

  stopifnot(
    raster::compareRaster(
      r11, r26, r51,
      extent = TRUE,
      rowcol = TRUE,
      crs = TRUE,
      res = TRUE,
      stopiffalse = FALSE
    )
  )

  set.seed(123)

  values <- raster::sampleRandom(
    raster::stack(r11, r26, r51),
    size = 10000,
    na.rm = TRUE
  )

  violations <- c(
    from_11_to_26 = sum(
      values[, 2] > values[, 1] + 0.0001
    ),
    from_26_to_51 = sum(
      values[, 3] > values[, 2] + 0.0001
    )
  )

  print(data.frame(
    mode = mode,
    comparison = names(violations),
    increases = as.integer(violations)
  ))

  stopifnot(all(violations == 0))
}

# 14. Prepare rasters for plotting

prepare_plot_raster <- function(file, panel_name) {

  r <- terra::rast(file)

  r <- terra::crop(
    r,
    terra::ext(11, 32.5, -14.5, 6.5)
  )

  # Aggregation changes the display only
  r <- terra::aggregate(
    r,
    fact = 8,
    fun = mean,
    na.rm = TRUE
  )

  cell_size <- terra::res(r)

  x <- terra::as.data.frame(
    r,
    xy = TRUE,
    na.rm = TRUE
  )

  names(x)[3] <- "hours"

  x$cell_width <- cell_size[1]
  x$cell_height <- cell_size[2]
  x$panel <- panel_name

  x
}

# 15. Save figures safely

save_figure <- function(p, output_file) {

  temp_file <- tempfile(
    tmpdir = out_dir,
    fileext = ".png"
  )

  device <- if (requireNamespace("ragg", quietly = TRUE)) {
    ragg::agg_png
  } else {
    grDevices::png
  }

  ggplot2::ggsave(
    filename = temp_file,
    plot = p,
    device = device,
    width = 18,
    height = 7.5,
    dpi = 170,
    bg = "white"
  )

  replace_output(temp_file, output_file)

  unlink(temp_file)

  message("Saved: ", output_file)

  invisible(output_file)
}

# 16. Plotting function

make_accessibility_map <- function(mode, destination) {

  stopifnot(
    mode %in% c("walking", "motorized"),
    destination %in% c("dps", "sentinel")
  )

  if (destination == "dps") {

    targets <- c("dps_11", "dps_26", "dps_26")

  } else {

    targets <- c(
      "sentinel_11",
      "sentinel_26",
      "sentinel_51"
    )
  }

  raster_data <- dplyr::bind_rows(
    prepare_plot_raster(
      access_file(mode, targets[1]), "11 sites"
    ),
    prepare_plot_raster(
      access_file(mode, targets[2]), "26 sites"
    ),
    prepare_plot_raster(
      access_file(mode, targets[3]), "51 sites"
    )
  )

  raster_data$panel <- factor(
    raster_data$panel,
    levels = panels
  )

  if (mode == "walking") {

    upper <- 72
    breaks <- c(0, 3, 6, 12, 24, 36, 48, 60, 72)

    mode_title <- "Walking"

  } else {

    upper <- 24
    breaks <- c(0, 1, 3, 6, 12, 18, 24)

    mode_title <- "Motorised"
  }

  if (destination == "dps") {

    title_text <- paste(
      mode_title,
      "time to the nearest DPS office in DRC"
    )

    legend_title <- paste(
      mode_title,
      "time to nearest DPS (hours)"
    )

    output_file <- file.path(
      out_dir,
      if (mode == "walking") {
        "Figure2_walking_accessibility_final.png"
      } else {
        "Figure3_motorized_accessibility_final.png"
      }
    )

  } else {

    title_text <- paste(
      mode_title,
      "time to the nearest sentinel site in DRC"
    )

    legend_title <- paste(
      mode_title,
      "time to nearest sentinel site (hours)"
    )

    output_file <- file.path(
      out_dir,
      if (mode == "walking") {
        "FigureS1_walking_nearest_sentinel_sites.png"
      } else {
        "FigureS2_motorized_nearest_sentinel_sites.png"
      }
    )
  }

  p <- ggplot() +

    geom_tile(
      data = raster_data,
      aes(
        x = x,
        y = y,
        fill = hours,
        width = cell_width,
        height = cell_height
      ),
      colour = NA,
      linewidth = 0
    ) +

    geom_sf(
      data = outside_mask,
      fill = "white",
      colour = NA
    ) +

    geom_sf(
      data = boundaries,
      fill = NA,
      colour = "grey75",
      linewidth = 0.22
    ) +

    geom_sf(
      data = outlines,
      fill = NA,
      colour = "grey40",
      linewidth = 0.45
    ) +

    geom_point(
      data = sites,
      aes(
        x = longitude,
        y = latitude,
        colour = stage
      ),
      shape = 16,
      size = 1.9
    )

  if (destination == "dps") {

    p <- p +

      geom_point(
        data = offices,
        aes(
          x = longitude,
          y = latitude,
          shape = "DPS office"
        ),
        fill = "white",
        colour = "grey25",
        size = 1.9,
        stroke = 0.4
      ) +

      scale_shape_manual(
        values = c("DPS office" = 23),
        name = "DPS offices"
      )
  }

  p <- p +

    scale_fill_gradientn(
      colours = travel_colors,
      limits = c(0, upper),
      oob = scales::squish,
      breaks = breaks,
      labels = c(
        as.character(head(breaks, -1)),
        paste0(upper, "+")
      ),
      name = legend_title,
      guide = guide_colorbar(
        title.position = "top",
        barwidth = grid::unit(11, "cm"),
        barheight = grid::unit(0.4, "cm"),
        order = 1
      )
    ) +

    scale_colour_manual(
      values = site_colors,
      breaks = names(site_colors),
      drop = FALSE,
      name = "Sentinel sites"
    ) +

    facet_wrap(
      ~panel,
      nrow = 1,
      labeller = labeller(
        panel = panel_labels
      )
    ) +

    coord_sf(
      datum = NA,
      default_crs = sf::st_crs(4326),
      xlim = c(11.5, 32),
      ylim = c(-14, 6),
      expand = FALSE
    ) +

    labs(
      title = title_text,
      subtitle = paste(
        "MAP 2020 friction surface;",
        "values above", upper,
        "hours shown as", paste0(upper, "+")
      ),
      caption = paste(
        "Each configuration is evaluated using MAP 2020",
        "friction data. The 2021 network includes",
        "26 existing and 25 proposed sentinel sites."
      ),
      x = NULL,
      y = NULL
    ) +

    theme_minimal(base_size = 11) +

    theme(
      panel.grid = element_blank(),
      panel.background = element_blank(),

      axis.text = element_blank(),
      axis.ticks = element_blank(),
      axis.title = element_blank(),

      strip.background = element_blank(),

      strip.text = element_text(
        face = "bold",
        size = 12,
        hjust = 0.5
      ),

      plot.title = element_text(
        face = "bold",
        size = 16,
        hjust = 0.5
      ),

      plot.subtitle = element_text(
        size = 11,
        hjust = 0.5,
        colour = "grey30"
      ),

      plot.caption = element_text(
        size = 8,
        hjust = 0.5,
        colour = "grey40"
      ),

      legend.position = "bottom",
      legend.box = "vertical",
      legend.box.just = "center",

      panel.spacing = grid::unit(0.4, "lines"),

      plot.margin = margin(5, 5, 5, 5)
    )

  save_figure(p, output_file)

  # POSTER_300DPI: 300-dpi copies of Figures S1 and S2 (nearest sentinel site)
  if (destination == "sentinel") {
    poster_name <- if (mode == "walking") {
      "FigureS1_walking_nearest_sentinel_sites_300dpi.png"
    } else {
      "FigureS2_motorized_nearest_sentinel_sites_300dpi.png"
    }

    ggplot2::ggsave(
      file.path(poster_dir, poster_name),
      plot = p,
      width = 15,
      height = 6.25,
      units = "in",
      dpi = 300,
      bg = "white"
    )
  }

  rm(p, raster_data)
  invisible(gc(verbose = FALSE))

  invisible(output_file)
}

# 17. Generate the four accessibility figures

if (make_figures) {

  make_accessibility_map("walking", "dps")

  make_accessibility_map("motorized", "dps")

  make_accessibility_map("walking", "sentinel")

  make_accessibility_map("motorized", "sentinel")
}

# 18. Record the modelling configuration

configuration <- data.frame(
  mode = c("walking", "motorized"),
  dataset_id = unname(map_datasets),
  friction_file = unname(friction_files),
  transition_file = unname(transition_files),
  buffer_km = buffer_km,
  directions = directions,
  geo_correction = "c",
  friction_units = "minutes per metre",
  output_units = "hours",
  rebuilt_from_map = full_rebuild
)

readr::write_csv(
  configuration,
  file.path(out_dir, "accessibility_model_configuration.csv")
)

message("Accessibility analysis completed.")
