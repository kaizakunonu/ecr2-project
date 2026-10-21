
# Figure 1 — Evolution of sentinel sites for entomological surveillance in DRC

# 1. Load packages
source("R/00_packages.R")

out_dir <- "output/unified"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)


# 2. Load sentinel sites
ss11 <- read.csv("output/ss_11.csv")
ss26 <- read.csv("output/ss_26.csv")
ss51 <- read.csv("output/network_51/ss_51.csv")

clean_name <- function(x) {
  x <- trimws(as.character(x))
  z <- iconv(x, to = "ASCII//TRANSLIT")
  z[is.na(z)] <- x[is.na(z)]
  gsub("[^a-z0-9]", "", tolower(z))
}


# 3. Prepare sentinel-site locations
prepare_sites <- function(x, network_name) {
  data.frame(
    network = network_name,
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

sites$network <- factor(
  sites$network,
  levels = c("11 sites", "26 sites", "51 sites")
)

sites$stage <- factor(
  sites$stage,
  levels = c(
    "Historical 11",
    "2014 additional 15",
    "2021 proposed 25"
  )
)

# Check the number of sites in each group
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
  all(as.matrix(table(sites$network, sites$stage)) == expected)
)


# 4. Load historical and modern provincial boundaries
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


# 5. Prepare provincial boundaries for each map
add_network <- function(x, name) {
  sf::st_sf(
    network = rep(name, nrow(x)),
    geometry = sf::st_geometry(x)
  )
}

boundaries <- rbind(
  add_network(prov11, "11 sites"),
  add_network(prov26, "26 sites"),
  add_network(prov26, "51 sites")
)

boundaries$network <- factor(
  boundaries$network,
  levels = levels(sites$network)
)


# 6. Sentinel-site colours
site_colors <- c(
  "Historical 11" = "#8E44AD",
  "2014 additional 15" = "#E64B35",
  "2021 proposed 25" = "#F4A300"
)


# 7. Create the maps
make_map <- function(show_labels = FALSE) {
  
  p <- ggplot() +
    
    geom_sf(
      data = boundaries,
      fill = "grey97",
      colour = "grey65",
      linewidth = 0.25
    ) +
    
    geom_point(
      data = sites,
      aes(
        x = longitude,
        y = latitude,
        fill = stage
      ),
      shape = 21,
      colour = "white",
      stroke = 0.4,
      size = 3
    ) +
    
    scale_fill_manual(
      values = site_colors,
      drop = FALSE,
      name = "Site category"
    ) +
    
    facet_wrap(
      ~network,
      nrow = 1,
      labeller = as_labeller(c(
        "11 sites" = "2003–2005: Historical sentinel sites (11)",
        "26 sites" = "2014: Existing sentinel sites (26)",
        "51 sites" = "2021: Expanded sentinel sites (51)"
      ))
    ) +
    
    coord_sf(
      datum = NA,
      default_crs = sf::st_crs(4326),
      expand = TRUE
    ) +
    
    labs(
      title = "Evolution of sentinel sites for entomological surveillance in DRC",
      subtitle = "Historical, existing and proposed sentinel-site configurations",
      caption = paste(
        "The 2003–2005 panel uses historical 11-province boundaries;",
        "the 2014 and 2021 panels use modern provincial boundaries.",
        "The 2021 configuration includes 26 existing and 25 proposed sites."
      ),
      x = NULL,
      y = NULL
    ) +
    
    theme_minimal(base_size = 11) +
    
    theme(
      panel.grid = element_blank(),
      strip.text = element_text(
        face = "bold",
        size = 11,
        hjust = 0.5
      ),
      plot.title = element_text(
        face = "bold",
        size = 15,
        hjust = 0.5
      ),
      plot.subtitle = element_text(
        size = 11,
        hjust = 0.5
      ),
      plot.caption = element_text(
        size = 9,
        colour = "grey40",
        hjust = 0.5
      ),
      legend.position = "bottom",
      legend.justification = "center",
      legend.title = element_text(face = "bold"),
      panel.spacing = unit(1.2, "lines"),
      plot.margin = margin(10, 20, 10, 20)
    )
  
  if (show_labels) {
    
    p <- p +
      ggrepel::geom_text_repel(
        data = sites,
        aes(
          x = longitude,
          y = latitude,
          label = sentinel_site
        ),
        size = 2.7,
        colour = "grey15",
        box.padding = 0.3,
        point.padding = 0.2,
        max.overlaps = Inf,
        min.segment.length = 0,
        segment.colour = "grey55",
        seed = 123
      )
  }
  
  p
}


# 8. Figure 1A — Clean map
p_clean <- make_map()

ggsave(
  file.path(out_dir, "Figure1_network_evolution_clean.png"),
  p_clean,
  width = 18,
  height = 8,
  dpi = 300,
  bg = "white"
)


# 9. Figure 1B — Map with site names
p_labeled <- make_map(show_labels = TRUE)

ggsave(
  file.path(out_dir, "Figure1_network_evolution_labeled.png"),
  p_labeled,
  width = 22,
  height = 9,
  dpi = 300,
  bg = "white"
)

print(p_labeled)
