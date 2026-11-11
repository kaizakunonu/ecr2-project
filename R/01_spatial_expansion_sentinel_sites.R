
# 01 — Spatial expansion of sentinel sites in DRC

source("R/00_packages.R")

out_dir <- "output/unified"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# 1. Load sentinel-site data

ss11 <- read.csv("output/ss_11.csv")
ss26 <- read.csv("output/ss_26.csv")
ss51 <- read.csv("output/network_51/ss_51.csv")

clean_name <- function(x) {
  x <- trimws(as.character(x))
  z <- iconv(x, to = "ASCII//TRANSLIT")
  z[is.na(z)] <- x[is.na(z)]
  gsub("[^a-z0-9]", "", tolower(z))
}

prepare_sites <- function(x, network_name) {
  data.frame(
    network = network_name,
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

# 2. Classify sentinel sites by expansion period

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

panels <- c("11 sites", "26 sites", "51 sites")

sites$network <- factor(
  sites$network,
  levels = panels
)

sites$stage <- factor(
  sites$stage,
  levels = c(
    "Historical 11",
    "2014 additional 15",
    "2021 proposed 25"
  )
)

# 3. Validate network configurations

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
  sum(ss51$network == "2021_expansion") == 25,
  !anyNA(sites[, c("longitude", "latitude")]),
  all(
    as.matrix(table(sites$network, sites$stage)) ==
      expected
  )
)

print(table(sites$network, sites$stage))

# 4. Load historical provincial boundaries

prov11 <- sf::st_read(
  "RDC_11_provinces_1988_2015/RDC_11_provinces_1988_2015.shp",
  quiet = TRUE
) |>
  sf::st_make_valid() |>
  sf::st_transform(4326)

# 5. Load modern provincial boundaries

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

# 6. Prepare boundaries for the three maps

add_network <- function(x, network_name) {
  sf::st_sf(
    network = rep(network_name, nrow(x)),
    geometry = sf::st_geometry(x)
  )
}

boundaries <- dplyr::bind_rows(
  add_network(prov11, "11 sites"),
  add_network(prov26, "26 sites"),
  add_network(prov26, "51 sites")
)

boundaries$network <- factor(
  boundaries$network,
  levels = panels
)

# 7. Colours and panel headings

site_colors <- c(
  "Historical 11" = "#8E44AD",
  "2014 additional 15" = "#E64B35",
  "2021 proposed 25" = "#F4A300"
)

panel_labels <- c(
  "11 sites" = "2003–2005: 11 sentinel sites",
  "26 sites" = "2014: 26 sentinel sites",
  "51 sites" = "2021: 26 existing + 25 proposed"
)

# 8. Create map function

make_map <- function(show_labels = FALSE) {

  p <- ggplot() +

    # Provincial boundaries
    geom_sf(
      data = boundaries,
      fill = "grey97",
      colour = "grey70",
      linewidth = 0.3
    ) +

    # Sentinel sites: filled circles
    geom_point(
      data = sites,
      aes(
        x = longitude,
        y = latitude,
        fill = stage
      ),
      shape = 21,
      colour = "white",
      stroke = 0.35,
      size = 2.8
    ) +

    scale_fill_manual(
      values = site_colors,
      breaks = names(site_colors),
      drop = FALSE,
      name = "Sentinel sites"
    ) +

    # Three maps with centred headings
    facet_wrap(
      ~network,
      nrow = 1,
      labeller = labeller(
        network = panel_labels
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
      title = paste(
        "Spatial expansion of sentinel sites",
        "for entomological surveillance in DRC"
      ),
      subtitle = paste(
        "Historical, existing and proposed",
        "surveillance network configurations"
      ),
      caption = paste(
        "Historical provincial boundaries are used for 2003–2005;",
        "modern provincial boundaries are used for 2014 and 2021.",
        "The 2021 configuration includes 26 existing",
        "and 25 proposed sentinel sites."
      ),
      x = NULL,
      y = NULL
    ) +

    theme_minimal(base_size = 11) +

    theme(
      panel.grid = element_blank(),
      panel.background = element_blank(),

      axis.title = element_blank(),
      axis.text = element_blank(),
      axis.ticks = element_blank(),

      strip.background = element_blank(),

      strip.text = element_text(
        face = "bold",
        size = 12,
        hjust = 0.5,
        margin = margin(b = 5)
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
      legend.justification = "center",
      legend.title = element_text(face = "bold"),

      panel.spacing = grid::unit(0.7, "lines"),
      plot.margin = margin(10, 10, 10, 10)
    )

  # Optional map with sentinel-site names
  if (show_labels) {

    p <- p +

      ggrepel::geom_text_repel(
        data = sites,
        aes(
          x = longitude,
          y = latitude,
          label = sentinel_site
        ),
        size = 2.5,
        colour = "grey20",
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

# 9. Save Figure 1 — Clean map

p_clean <- make_map(show_labels = FALSE)

ggsave(
  file.path(
    out_dir,
    "Figure1_network_evolution_clean.png"
  ),
  plot = p_clean,
  width = 18,
  height = 7.5,
  dpi = 200,
  bg = "white"
)

rm(p_clean)
invisible(gc(verbose = FALSE))

# 10. Save Figure 1 — Labelled map

p_labeled <- make_map(show_labels = TRUE)

ggsave(
  file.path(
    out_dir,
    "Figure1_network_evolution_labeled.png"
  ),
  plot = p_labeled,
  width = 22,
  height = 9,
  dpi = 200,
  bg = "white"
)

rm(p_labeled)
invisible(gc(verbose = FALSE))
