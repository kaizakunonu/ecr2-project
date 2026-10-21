
# Figures 2 and 3 — DPS to assigned sentinel sites

source("R/00_packages.R")

out_dir <- "output/unified"

# 1. Load data
dps11 <- read.csv("output/dps_11.csv")
dps26 <- read.csv("output/dps_26.csv")
ss11 <- read.csv("output/ss_11.csv")
ss26 <- read.csv("output/ss_26.csv")
ss51 <- read.csv("output/network_51/ss_51.csv")

results <- read.csv(file.path(out_dir, "site_level_results.csv"))

clean_name <- function(x) {
  z <- iconv(trimws(as.character(x)), to = "ASCII//TRANSLIT")
  z[is.na(z)] <- x[is.na(z)]
  gsub("[^a-z0-9]", "", tolower(z))
}

panels <- c("11 sites", "26 sites", "51 sites")

stages <- c(
  "Historical 11",
  "2014 additional 15",
  "2021 proposed 25"
)

site_colors <- c(
  "Historical 11" = "#6A3D9A",
  "2014 additional 15" = "#009E73",
  "2021 proposed 25" = "#E69F00"
)


# 2. Match DPS offices to sentinel sites
make_pairs <- function(ss, dps, network, index) {
  data.frame(
    network = network,
    sentinel_site = ss$sentinel_site,
    dps_lon = dps$longitude[index],
    dps_lat = dps$latitude[index],
    site_lon = ss$longitude,
    site_lat = ss$latitude
  )
}

i51 <- match(
  clean_name(ss51$dps_province),
  clean_name(dps26$dps_province)
)

stopifnot(!anyNA(i51))

pairs <- dplyr::bind_rows(
  make_pairs(ss11, dps11, 11, seq_len(11)),
  make_pairs(ss26, dps26, 26, seq_len(26)),
  make_pairs(ss51, dps26, 51, i51)
)

pairs$panel <- factor(
  paste(pairs$network, "sites"),
  levels = panels
)


# 3. Add validated modelled travel times
get_times <- function(mode) {
  
  x <- results[results$mode == mode, ]
  
  key_pairs <- paste(
    pairs$network,
    clean_name(pairs$sentinel_site)
  )
  
  key_results <- paste(
    x$network,
    clean_name(x$sentinel_site)
  )
  
  stopifnot(!anyDuplicated(key_results))
  
  i <- match(key_pairs, key_results)
  stopifnot(!anyNA(i))
  
  y <- pairs
  y$hours <- x$time_hours[i]
  y$stage <- factor(x$stage[i], levels = stages)
  
  stopifnot(all(is.finite(y$hours)))
  
  y
}

walking <- get_times("walking")
motorized <- get_times("motorized")


# 4. Load walking routes calculated with shortestPath()
routes <- sf::st_read(
  file.path(out_dir, "walking_routes.gpkg"),
  quiet = TRUE
)

routes$network <- as.integer(as.character(routes$network))

# Reuse matching 51-site routes for the 26-site panel
routes26 <- routes[
  routes$network == 51 &
    clean_name(routes$sentinel_site) %in%
    clean_name(ss26$sentinel_site),
]

routes26$network <- 26
routes <- rbind(routes, routes26)

i <- match(
  paste(routes$network, clean_name(routes$sentinel_site)),
  paste(walking$network, clean_name(walking$sentinel_site))
)

stopifnot(!anyNA(i))

routes$hours <- walking$hours[i]
routes$panel <- factor(
  paste(routes$network, "sites"),
  levels = panels
)


# 5. Load provincial boundaries
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
    panel = panel_name,
    geometry = sf::st_geometry(x)
  )
}

boundaries <- rbind(
  add_panel(prov11, "11 sites"),
  add_panel(prov26, "26 sites"),
  add_panel(prov26, "51 sites")
)

boundaries$panel <- factor(boundaries$panel, levels = panels)


# 6. DPS office markers
make_offices <- function(dps, network) {
  data.frame(
    panel = paste(network, "sites"),
    longitude = dps$longitude,
    latitude = dps$latitude
  )
}

offices <- dplyr::bind_rows(
  make_offices(dps11, 11),
  make_offices(dps26, 26),
  make_offices(dps26, 51)
)

offices$panel <- factor(offices$panel, levels = panels)


# 7. Plot assigned DPS-to-site journeys
make_map <- function(mode) {
  
  is_walking <- mode == "walking"
  x <- if (is_walking) walking else motorized
  
  upper <- if (is_walking) 72 else 8
  
  breaks <- if (is_walking) {
    c(0, 3, 6, 12, 24, 48, 72)
  } else {
    c(0, 1, 2, 4, 6, 8)
  }
  
  title <- if (is_walking) {
    "Walking travel time from DPS offices to assigned sentinel sites"
  } else {
    "Motorised travel time from DPS offices to assigned sentinel sites"
  }
  
  colors <- c(
    "#F1F8E9", "#B5DDD0", "#66C4C5",
    "#2C96B5", "#206F9B", "#1B4B83", "#1B3069"
  )
  
  p <- ggplot() +
    geom_sf(
      data = boundaries,
      fill = "grey98",
      colour = "grey70",
      linewidth = 0.2
    )
  
  if (is_walking) {
    p <- p +
      geom_sf(
        data = routes,
        aes(colour = hours),
        linewidth = 0.5,
        alpha = 0.85
      )
  } else {
    p <- p +
      geom_segment(
        data = x,
        aes(
          x = dps_lon, y = dps_lat,
          xend = site_lon, yend = site_lat,
          colour = hours
        ),
        linetype = "dashed",
        linewidth = 0.4,
        alpha = 0.8
      )
  }
  
  p +
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
      size = 2.6,
      stroke = 0.5
    ) +
    
    # Sentinel sites: coloured circles
    geom_point(
      data = x,
      aes(
        x = site_lon,
        y = site_lat,
        fill = stage
      ),
      shape = 21,
      colour = "white",
      size = 1.9,
      stroke = 0.3
    ) +
    
    scale_colour_gradientn(
      colours = colors,
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
    
    scale_fill_manual(
      values = site_colors,
      breaks = stages,
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
      subtitle = "Travel between DPS offices and their assigned surveillance sites",
      caption = if (is_walking) {
        paste(
          "Lines show modelled least-cost walking routes.",
          "These are not verified footpaths."
        )
      } else {
        paste(
          "Dashed connections indicate assigned DPS–site pairs,",
          "not actual roads or vehicle routes."
        )
      },
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
      legend.position = "bottom"
    )
}


# 8. Save the two figures
p_walking <- make_map("walking")
p_motorized <- make_map("motorized")

ggsave(
  file.path(out_dir, "Figure2_DPS_to_sites_walking.png"),
  p_walking,
  width = 18, height = 7, dpi = 180,
  bg = "white"
)

ggsave(
  file.path(out_dir, "Figure3_DPS_to_sites_motorized.png"),
  p_motorized,
  width = 18, height = 7, dpi = 180,
  bg = "white"
)
