
# Shared functions for nearest-sentinel-site accessibility maps

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

prepare_raster <- function(file, panel_name) {
  
  r <- terra::rast(file)
  
  stopifnot(terra::nlyr(r) == 1)
  
  # Reduce resolution for plotting only
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

draw_nearest_sentinel_map <- function(mode) {
  
  stopifnot(mode %in% c("walking", "motorized"))
  
  out_dir <- "output/unified"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  
  panels <- c("11 sites", "26 sites", "51 sites")
  
  panel_labels <- c(
    "11 sites" = "2003–2005: 11 sentinel sites",
    "26 sites" = "2014: 26 sentinel sites",
    "51 sites" = "2021: 26 existing + 25 proposed"
  )
  
  # Sentinel-site colours
  site_colors <- c(
    "Historical 11" = "#8E44AD",
    "2014 additional 15" = "#E64B35",
    "2021 proposed 25" = "#F4A300"
  )
  
  # Continuous accessibility colours
  travel_colors <- c(
    "#DCECCF",
    "#B8E3D8",
    "#7FCFCF",
    "#44B6C9",
    "#2F8FC1",
    "#2B65AD",
    "#273C88"
  )
  
  # Load sentinel-site locations
  ss11 <- read.csv("output/ss_11.csv")
  ss26 <- read.csv("output/ss_26.csv")
  ss51 <- read.csv("output/network_51/ss_51.csv")
  
  sites <- dplyr::bind_rows(
    prepare_sites(ss11, "11 sites"),
    prepare_sites(ss26, "26 sites"),
    prepare_sites(ss51, "51 sites")
  )
  
  historical <- clean_name(ss11$sentinel_site)
  
  proposed <- clean_name(
    ss51$sentinel_site[
      ss51$network == "2021_expansion"
    ]
  )
  
  site_names <- clean_name(sites$sentinel_site)
  
  sites$stage <- ifelse(
    site_names %in% historical,
    "Historical 11",
    ifelse(
      site_names %in% proposed,
      "2021 proposed 25",
      "2014 additional 15"
    )
  )
  
  sites$panel <- factor(
    sites$panel,
    levels = panels
  )
  
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
    nrow(ss11) == 11,
    nrow(ss26) == 26,
    nrow(ss51) == 51,
    all(
      as.matrix(table(sites$panel, sites$stage)) ==
        expected
    )
  )
  
  # Historical provincial boundaries
  prov11 <- sf::st_read(
    "RDC_11_provinces_1988_2015/RDC_11_provinces_1988_2015.shp",
    quiet = TRUE
  ) |>
    sf::st_make_valid() |>
    sf::st_transform(4326)
  
  # Modern provincial boundaries
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
  
  # Use original boundary geometry, without simplification
  add_panel <- function(x, panel_name) {
    sf::st_sf(
      panel = panel_name,
      geometry = sf::st_geometry(x)
    )
  }
  
  boundaries <- dplyr::bind_rows(
    add_panel(prov11, "11 sites"),
    add_panel(prov26, "26 sites"),
    add_panel(prov26, "51 sites")
  )
  
  boundaries$panel <- factor(
    boundaries$panel,
    levels = panels
  )
  
  # National outline for each panel
  make_outline <- function(x, panel_name) {
    
    geometry <- sf::st_make_valid(
      sf::st_union(sf::st_geometry(x))
    )
    
    sf::st_sf(
      panel = panel_name,
      geometry = geometry
    )
  }
  
  outlines <- dplyr::bind_rows(
    make_outline(prov11, "11 sites"),
    make_outline(prov26, "26 sites"),
    make_outline(prov26, "51 sites")
  )
  
  outlines$panel <- factor(
    outlines$panel,
    levels = panels
  )
  
  # Precise white mask outside national boundaries
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
  
  # Choose mode-specific settings
  if (mode == "walking") {
    
    upper <- 72
    breaks <- c(0, 3, 6, 12, 24, 36, 48, 60, 72)
    
    title_text <- "Walking time to the nearest sentinel site in DRC"
    
    subtitle_text <- paste(
      "Walking-only friction surface (MAP, 2020);",
      "values above 72 h shown as 72+"
    )
    
    legend_title <- "Walking time to nearest sentinel site (hours)"
    
    output_file <- file.path(
      out_dir,
      "FigureS1_walking_nearest_sentinel_sites.png"
    )
    
  } else {
    
    upper <- 24
    breaks <- c(0, 1, 3, 6, 12, 18, 24)
    
    title_text <- "Motorised time to the nearest sentinel site in DRC"
    
    subtitle_text <- paste(
      "MAP 2020 motorised friction surface;",
      "values above 24 h shown as 24+"
    )
    
    legend_title <- "Motorised time to nearest sentinel site (hours)"
    
    output_file <- file.path(
      out_dir,
      "FigureS2_motorized_nearest_sentinel_sites.png"
    )
  }
  
  # Load existing, validated accessibility rasters
  raster_files <- file.path(
    out_dir,
    paste0(
      "test_nearest_sentinel_",
      mode,
      "_",
      c(11, 26, 51),
      ".tif"
    )
  )
  
  if (!all(file.exists(raster_files))) {
    stop(
      "Missing accessibility rasters: ",
      paste(
        raster_files[!file.exists(raster_files)],
        collapse = ", "
      )
    )
  }
  
  raster_data <- dplyr::bind_rows(
    prepare_raster(raster_files[1], "11 sites"),
    prepare_raster(raster_files[2], "26 sites"),
    prepare_raster(raster_files[3], "51 sites")
  )
  
  raster_data$panel <- factor(
    raster_data$panel,
    levels = panels
  )
  
  # Create three-panel figure
  p <- ggplot2::ggplot() +
    
    ggplot2::geom_tile(
      data = raster_data,
      ggplot2::aes(
        x = x,
        y = y,
        fill = hours,
        width = cell_width,
        height = cell_height
      ),
      colour = NA,
      linewidth = 0
    ) +
    
    # Hide raster pixels outside the national boundary
    ggplot2::geom_sf(
      data = outside_mask,
      fill = "white",
      colour = NA
    ) +
    
    # Provincial boundaries
    ggplot2::geom_sf(
      data = boundaries,
      fill = NA,
      colour = "grey75",
      linewidth = 0.22
    ) +
    
    # National outline
    ggplot2::geom_sf(
      data = outlines,
      fill = NA,
      colour = "grey40",
      linewidth = 0.45
    ) +
    
    # Small filled sentinel-site circles
    ggplot2::geom_point(
      data = sites,
      ggplot2::aes(
        x = longitude,
        y = latitude,
        colour = stage
      ),
      shape = 16,
      size = 1.9
    ) +
    
    ggplot2::scale_fill_gradientn(
      colours = travel_colors,
      limits = c(0, upper),
      oob = scales::squish,
      breaks = breaks,
      labels = c(
        as.character(head(breaks, -1)),
        paste0(upper, "+")
      ),
      name = legend_title,
      guide = ggplot2::guide_colorbar(
        title.position = "top",
        barwidth = grid::unit(10, "cm"),
        barheight = grid::unit(0.4, "cm"),
        order = 1
      )
    ) +
    
    ggplot2::scale_colour_manual(
      values = site_colors,
      breaks = names(site_colors),
      drop = FALSE,
      name = "Sentinel sites",
      guide = ggplot2::guide_legend(
        override.aes = list(
          shape = 16,
          size = 3
        ),
        order = 2
      )
    ) +
    
    ggplot2::facet_wrap(
      ~panel,
      nrow = 1,
      labeller = ggplot2::labeller(
        panel = panel_labels
      )
    ) +
    
    ggplot2::coord_sf(
      datum = NA,
      default_crs = sf::st_crs(4326),
      xlim = c(11.5, 32),
      ylim = c(-14, 6),
      expand = FALSE
    ) +
    
    ggplot2::labs(
      title = title_text,
      subtitle = subtitle_text,
      caption = paste(
        "Each panel shows time to the nearest sentinel site.",
        "Network configurations are evaluated using MAP 2020 friction;",
        "the 2021 expansion is proposed."
      ),
      x = NULL,
      y = NULL
    ) +
    
    ggplot2::theme_minimal(base_size = 11) +
    
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      panel.background = ggplot2::element_blank(),
      
      axis.text = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      axis.title = ggplot2::element_blank(),
      
      strip.background = ggplot2::element_blank(),
      
      strip.text = ggplot2::element_text(
        face = "bold",
        size = 12,
        hjust = 0.5,
        margin = ggplot2::margin(b = 5)
      ),
      
      plot.title = ggplot2::element_text(
        face = "bold",
        size = 16,
        hjust = 0.5
      ),
      
      plot.subtitle = ggplot2::element_text(
        size = 11,
        hjust = 0.5,
        colour = "grey30"
      ),
      
      plot.caption = ggplot2::element_text(
        size = 8,
        hjust = 0.5,
        colour = "grey40"
      ),
      
      legend.position = "bottom",
      legend.box = "vertical",
      legend.box.just = "center",
      
      panel.spacing = grid::unit(0.4, "lines"),
      plot.margin = ggplot2::margin(5, 5, 5, 5)
    )
  
  # Save to a temporary PNG first
  temp_file <- tempfile(
    pattern = "nearest_sentinel_",
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
  
  # Replace the final image only after successful rendering
  saved <- file.copy(
    temp_file,
    output_file,
    overwrite = TRUE
  )
  
  unlink(temp_file)
  
  if (!saved) {
    stop(
      "Could not replace the figure. ",
      "Close the PNG in your image viewer and rerun."
    )
  }
  
  message("Saved: ", output_file)
  
  invisible(output_file)
}
