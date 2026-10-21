# Accessibility figures for DRC
# Figure 2 = Walking accessibility
# Figure 3 = Motorised accessibility

source("R/00_packages.R")

out_dir <- "output/unified"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# 1. Load sentinel sites and DPS offices

ss11 <- read.csv("output/ss_11.csv")
ss26 <- read.csv("output/ss_26.csv")
ss51 <- read.csv("output/network_51/ss_51.csv")

dps11 <- read.csv("output/dps_11.csv")
dps26 <- read.csv("output/dps_26.csv")

panels <- c("11 sites", "26 sites", "51 sites")

clean_name <- function(x) {
  x <- as.character(x)
  z <- iconv(trimws(x), to = "ASCII//TRANSLIT")
  z[is.na(z)] <- x[is.na(z)]
  gsub("[^a-z0-9]", "", tolower(z))
}

# 2. Sentinel-site groups and colours

stage_colors <- c(
  "Historical 11" = "#8E44AD",
  "2014 additional 15" = "#E64B35",
  "2021 proposed 25" = "#F4A300"
)

prepare_sites <- function(x, panel_name) {
  data.frame(
    panel = panel_name,
    sentinel_site = x$sentinel_site,
    longitude = x$longitude,
    latitude = x$latitude,
    stringsAsFactors = FALSE
  )
}

sites <- dplyr::bind_rows(
  prepare_sites(ss11, "11 sites"),
  prepare_sites(ss26, "26 sites"),
  prepare_sites(ss51, "51 sites")
)

historical <- clean_name(ss11$sentinel_site)
proposed <- clean_name(ss51$sentinel_site[ss51$network == "2021_expansion"])

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
  levels = c(
    "Historical 11",
    "2014 additional 15",
    "2021 proposed 25"
  )
)

# 3. DPS offices

prepare_dps <- function(x, panel_name) {
  data.frame(
    panel = panel_name,
    longitude = x$longitude,
    latitude = x$latitude,
    stringsAsFactors = FALSE
  )
}

offices <- dplyr::bind_rows(
  prepare_dps(dps11, "11 sites"),
  prepare_dps(dps26, "26 sites"),
  prepare_dps(dps26, "51 sites")
)

offices$panel <- factor(offices$panel, levels = panels)

# 4. Check expected numbers

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
  nrow(sites) == 88,
  all(as.matrix(table(sites$panel, sites$stage)) == expected)
)

# 5. Load boundaries

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
  dplyr::summarise(.groups = "drop")

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

# 6. Titles centred above each map (facet strips)

panel_labels <- c(
  "11 sites" = "2003–2005: 11 sentinel sites",
  "26 sites" = "2014: 26 sentinel sites",
  "51 sites" = "2021: 51 sentinel sites"
)

# 7. Raster preparation

prepare_raster <- function(file, boundary, panel_name) {
  
  r <- terra::rast(file)
  
  # reduce plotting load
  r <- terra::aggregate(
    r,
    fact = 8,
    fun = mean,
    na.rm = TRUE
  )
  
  b <- terra::vect(boundary)
  
  if (!terra::same.crs(r, b)) {
    b <- terra::project(b, terra::crs(r))
  }
  
  r <- terra::crop(r, b)
  r <- terra::mask(r, b)
  
  x <- terra::as.data.frame(
    r,
    xy = TRUE,
    na.rm = TRUE
  )
  
  names(x)[3] <- "hours"
  x$panel <- panel_name
  
  x
}

# 8. Colour ramp for accessibility surface
# close to the original visual style

travel_colors <- c(
  "#DCECCF",
  "#AEE4D6",
  "#63D1CE",
  "#2BAAC2",
  "#2C7FB8",
  "#325AA6",
  "#2C3E80"
)

# 9. Main plotting function

make_map <- function(mode) {
  
  file11 <- file.path(out_dir, paste0("accessibility_", mode, "_11.tif"))
  file26 <- file.path(out_dir, paste0("accessibility_", mode, "_26.tif"))
  
  stopifnot(file.exists(file11), file.exists(file26))
  
  # For this accessibility figure, the 51-site panel uses the same
  # continuous DPS accessibility surface as the 26-site panel.
  raster_data <- dplyr::bind_rows(
    prepare_raster(file11, prov11, "11 sites"),
    prepare_raster(file26, prov26, "26 sites"),
    prepare_raster(file26, prov26, "51 sites")
  )
  
  raster_data$panel <- factor(raster_data$panel, levels = panels)
  
  if (mode == "walking") {
    
    upper <- 72
    breaks <- c(0, 3, 6, 12, 48, 72)
    
    title_text <- "Walking time to the nearest DPS office in DRC"
    subtitle_text <- "Walking-only friction surface (MAP, 2020); values above 72 h shown as 72+"
    legend_title <- "Walking time to nearest DPS (hours)"
    out_file <- "Figure2_walking_accessibility_final.png"
    
  } else if (mode == "motorized") {
    
    upper <- 24
    breaks <- c(0, 4, 8, 12, 16, 20, 24)
    
    title_text <- "Motorised time to the nearest DPS office in DRC"
    subtitle_text <- "MAP 2020 motorised friction surface; values above 24 h shown as 24+"
    legend_title <- "Motorised time to nearest DPS (hours)"
    out_file <- "Figure3_motorized_accessibility_final.png"
    
  } else {
    stop("mode must be 'walking' or 'motorized'")
  }
  
  p <- ggplot() +
    
    geom_tile(
      data = raster_data,
      aes(x = x, y = y, fill = hours)
    ) +
    
    geom_sf(
      data = boundaries,
      fill = NA,
      colour = "grey70",
      linewidth = 0.35
    ) +
    
    # DPS offices = white diamonds
    geom_point(
      data = offices,
      aes(x = longitude, y = latitude, shape = "DPS office"),
      fill = "white",
      colour = "grey30",
      stroke = 0.5,
      size = 2.4
    ) +
    
    # White halo for sentinel sites
    geom_point(
      data = sites,
      aes(x = longitude, y = latitude),
      colour = "white",
      size = 3.2
    ) +
    
    # Sentinel sites = coloured circles
    geom_point(
      data = sites,
      aes(x = longitude, y = latitude, colour = stage),
      size = 2.2
    ) +
    
    scale_fill_gradientn(
      colours = travel_colors,
      values = scales::rescale(breaks, from = c(0, upper)),
      limits = c(0, upper),
      oob = scales::squish,
      breaks = breaks,
      labels = c(as.character(head(breaks, -1)), paste0(upper, "+")),
      name = legend_title,
      guide = guide_colorbar(
        title.position = "top",
        barwidth = grid::unit(8, "cm"),
        barheight = grid::unit(0.45, "cm"),
        order = 1
      )
    ) +
    
    scale_colour_manual(
      values = stage_colors,
      name = "Sentinel sites",
      drop = FALSE,
      guide = guide_legend(
        override.aes = list(size = 3, shape = 16),
        order = 2
      )
    ) +
    
    scale_shape_manual(
      values = c("DPS office" = 23),
      name = "Locations",
      guide = guide_legend(
        override.aes = list(
          fill = "white",
          colour = "grey30",
          size = 3
        ),
        order = 3
      )
    ) +
    
    facet_wrap(
      ~panel,
      nrow = 1,
      labeller = labeller(panel = panel_labels)
    ) +
    
    coord_sf(
      datum = NA,
      default_crs = sf::st_crs(4326),
      xlim = c(11.5, 32),
      ylim = c(-14, 7.1),
      expand = FALSE
    ) +
    
    labs(
      title = title_text,
      subtitle = subtitle_text,
      caption = paste(
        "Historical provincial boundaries are used for 2003–2005.",
        "The 2014 and 2021 panels share the same DPS accessibility surface.",
        "MAP 2020 friction data are applied to each network configuration."
      ),
      x = NULL,
      y = NULL
    ) +
    
    theme_minimal(base_size = 11) +
    theme(
      panel.grid = element_blank(),
      axis.text = element_blank(),
      axis.ticks = element_blank(),
      axis.title = element_blank(),
      
      strip.background = element_blank(),
      strip.text = element_text(
        face = "bold",
        size = 12,
        hjust = 0.5,
        margin = margin(b = 4)
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
      
      panel.spacing = grid::unit(0.7, "lines"),
      plot.margin = margin(10, 10, 10, 10)
    )
  
  ggsave(
    filename = file.path(out_dir, out_file),
    plot = p,
    device = grDevices::png,
    width = 18,
    height = 7.5,
    dpi = 150,
    bg = "white"
  )
  
  invisible(p)
}

# 10. Produce both final figures

p_walking <- make_map("walking")
gc(verbose = FALSE)

p_motorized <- make_map("motorized")
gc(verbose = FALSE)