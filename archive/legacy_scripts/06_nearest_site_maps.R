
# Supplementary figures — Accessibility to the nearest sentinel site

source("R/00_packages.R")

out_dir <- "output/unified"

# 1. Load sentinel sites and DPS offices
ss11 <- read.csv("output/ss_11.csv")
ss26 <- read.csv("output/ss_26.csv")
ss51 <- read.csv("output/network_51/ss_51.csv")

dps11 <- read.csv("output/dps_11.csv")
dps26 <- read.csv("output/dps_26.csv")

panels <- c("11 sites", "26 sites", "51 sites")

site_colors <- c(
  "Historical 11" = "#6A3D9A",
  "2014 additional 15" = "#009E73",
  "2021 proposed 25" = "#E69F00"
)

clean_name <- function(x) {
  z <- iconv(trimws(as.character(x)), to = "ASCII//TRANSLIT")
  z[is.na(z)] <- x[is.na(z)]
  gsub("[^a-z0-9]", "", tolower(z))
}

historical <- clean_name(ss11$sentinel_site)

proposed <- clean_name(
  ss51$sentinel_site[ss51$network == "2021_expansion"]
)


# 2. Prepare site markers
make_sites <- function(x, net) {
  data.frame(
    panel = paste(net, "sites"),
    sentinel_site = x$sentinel_site,
    longitude = x$longitude,
    latitude = x$latitude
  )
}

sites <- dplyr::bind_rows(
  make_sites(ss11, 11),
  make_sites(ss26, 26),
  make_sites(ss51, 51)
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

sites$panel <- factor(sites$panel, levels = panels)

sites$stage <- factor(
  sites$stage,
  levels = names(site_colors)
)

make_dps <- function(x, net) {
  data.frame(
    panel = paste(net, "sites"),
    longitude = x$longitude,
    latitude = x$latitude
  )
}

offices <- dplyr::bind_rows(
  make_dps(dps11, 11),
  make_dps(dps26, 26),
  make_dps(dps26, 51)
)

offices$panel <- factor(offices$panel, levels = panels)


# 3. Provincial boundaries
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

add_panel <- function(x, name) {
  sf::st_sf(
    panel = name,
    geometry = sf::st_geometry(x)
  )
}

boundaries <- rbind(
  add_panel(prov11, "11 sites"),
  add_panel(prov26, "26 sites"),
  add_panel(prov26, "51 sites")
)

boundaries$panel <- factor(boundaries$panel, levels = panels)


# 4. Reuse or calculate nearest-site accessibility
get_surface <- function(mode, net, ss) {
  
  file <- file.path(
    out_dir,
    paste0("accessibility_to_sites_", mode, "_", net, ".tif")
  )
  
  if (file.exists(file)) {
    return(raster::raster(file))
  }
  
  transition_file <- if (mode == "walking") {
    "output/transition_walk_drc_gc.rds"
  } else {
    "output/transition_motorized_drc_gc_50km.rds"
  }
  
  tr <- readRDS(transition_file)
  
  r <- gdistance::accCost(
    tr,
    as.matrix(ss[, c("longitude", "latitude")])
  ) / 60
  
  raster::writeRaster(r, file, overwrite = TRUE)
  
  rm(tr, r)
  gc(verbose = FALSE)
  
  raster::raster(file)
}


# 5. Prepare smaller rasters for display
prepare_raster <- function(r, boundary, net) {
  
  r <- raster::aggregate(
    r,
    fact = 8,
    fun = mean,
    na.rm = TRUE
  )
  
  r <- raster::mask(r, as(boundary, "Spatial"))
  
  x <- raster::as.data.frame(
    r,
    xy = TRUE,
    na.rm = TRUE
  )
  
  names(x)[3] <- "hours"
  x$panel <- paste(net, "sites")
  
  x
}


# 6. Create the supplementary maps
make_map <- function(mode) {
  
  r11 <- get_surface(mode, 11, ss11)
  r26 <- get_surface(mode, 26, ss26)
  r51 <- get_surface(mode, 51, ss51)
  
  raster_data <- dplyr::bind_rows(
    prepare_raster(r11, prov11, 11),
    prepare_raster(r26, prov26, 26),
    prepare_raster(r51, prov26, 51)
  )
  
  raster_data$panel <- factor(
    raster_data$panel,
    levels = panels
  )
  
  if (mode == "walking") {
    upper <- 72
    breaks <- c(0, 3, 6, 12, 24, 48, 72)
    title <- "Walking accessibility to the nearest sentinel site"
  } else {
    upper <- 24
    breaks <- c(0, 1, 3, 6, 12, 18, 24)
    title <- "Motorised accessibility to the nearest sentinel site"
  }
  
  ggplot() +
    geom_tile(
      data = raster_data,
      aes(x = x, y = y, fill = hours)
    ) +
    
    geom_sf(
      data = boundaries,
      fill = NA,
      colour = "grey70",
      linewidth = 0.2
    ) +
    
    # DPS offices: white diamonds
    geom_point(
      data = offices,
      aes(
        x = longitude,
        y = latitude,
        shape = "DPS office"
      ),
      fill = "white",
      colour = "black",
      size = 2.4,
      stroke = 0.4
    ) +
    
    # Sentinel sites: coloured circles
    geom_point(
      data = sites,
      aes(x = longitude, y = latitude),
      colour = "white",
      size = 2.5
    ) +
    
    geom_point(
      data = sites,
      aes(
        x = longitude,
        y = latitude,
        colour = stage
      ),
      size = 1.7
    ) +
    
    scale_fill_gradientn(
      colours = c(
        "#E8F5E9", "#CDEEE1", "#9DDFDA",
        "#63C6D0", "#2D93BF", "#245E9B", "#253B82"
      ),
      limits = c(0, upper),
      oob = scales::squish,
      breaks = breaks,
      name = "Travel time (hours)",
      guide = guide_colorbar(
        title.position = "top",
        barwidth = grid::unit(7, "cm"),
        barheight = grid::unit(0.35, "cm")
      )
    ) +
    
    scale_colour_manual(
      values = site_colors,
      drop = FALSE,
      name = "Sentinel sites"
    ) +
    
    scale_shape_manual(
      values = c("DPS office" = 23),
      name = "Locations"
    ) +
    
    facet_wrap(
      ~panel,
      nrow = 1,
      labeller = as_labeller(c(
        "11 sites" = "2003–2005: 11 sites",
        "26 sites" = "2014: 26 sites",
        "51 sites" = "2021: 51 sites"
      ))
    ) +
    
    coord_sf(
      datum = NA,
      default_crs = sf::st_crs(4326)
    ) +
    
    labs(
      title = title,
      subtitle = "Geographic accessibility under each sentinel-site configuration",
      caption = paste(
        "Continuous least-cost accessibility surface.",
        "This does not represent assigned DPS-to-site journeys."
      ),
      x = NULL,
      y = NULL
    ) +
    
    theme_minimal(base_size = 11) +
    theme(
      panel.grid = element_blank(),
      strip.text = element_text(face = "bold", hjust = 0.5),
      plot.title = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5),
      plot.caption = element_text(hjust = 0.5),
      legend.position = "bottom",
      legend.box = "vertical"
    )
}


# 7. Save supplementary figures
p_s1 <- make_map("walking")

ggsave(
  file.path(out_dir, "FigureS1_nearest_site_walking.png"),
  p_s1,
  width = 18, height = 7, dpi = 160,
  bg = "white"
)

rm(p_s1)
gc(verbose = FALSE)

p_s2 <- make_map("motorized")

ggsave(
  file.path(out_dir, "FigureS2_nearest_site_motorized.png"),
  p_s2,
  width = 18, height = 7, dpi = 160,
  bg = "white"
)
