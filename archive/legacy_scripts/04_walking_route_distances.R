
# Walking-route distances from DPS offices to sentinel sites
# MAP walking-only friction surface and gdistance::shortestPath

source("R/00_packages.R")

out_dir <- "output/unified"

# 1. Load coordinates
dps11 <- read.csv("output/dps_11.csv")
ss11  <- read.csv("output/ss_11.csv")

dps26 <- read.csv("output/dps_26.csv")
ss26  <- read.csv("output/ss_26.csv")
ss51  <- read.csv("output/network_51/ss_51.csv")

clean_name <- function(x) {
  z <- iconv(trimws(as.character(x)), to = "ASCII//TRANSLIT")
  z[is.na(z)] <- x[is.na(z)]
  gsub("[^a-z0-9]", "", tolower(z))
}


# 2. Match each sentinel site to its DPS
make_pairs <- function(dps, ss, network, index) {
  data.frame(
    network = network,
    province = dps$dps_province[index],
    sentinel_site = ss$sentinel_site,
    dps_lon = dps$longitude[index],
    dps_lat = dps$latitude[index],
    site_lon = ss$longitude,
    site_lat = ss$latitude
  )
}

index51 <- match(
  clean_name(ss51$dps_province),
  clean_name(dps26$dps_province)
)

stopifnot(!anyNA(index51))

pairs11 <- make_pairs(dps11, ss11, 11, seq_len(11))
pairs26 <- make_pairs(dps26, ss26, 26, seq_len(26))
pairs51 <- make_pairs(dps26, ss51, 51, index51)

# The 26 existing journeys are also represented in the
# 51-site dataset, so calculate those routes only once.

match26 <- match(
  clean_name(pairs26$sentinel_site),
  clean_name(pairs51$sentinel_site)
)

stopifnot(!anyNA(match26))

coord_cols <- c("dps_lon", "dps_lat", "site_lon", "site_lat")

stopifnot(
  all(
    abs(
      as.matrix(pairs26[coord_cols]) -
        as.matrix(pairs51[match26, coord_cols])
    ) < 0.00001
  )
)

pairs <- rbind(pairs11, pairs51)
rownames(pairs) <- NULL


# 3. Load the existing walking model
transition <- readRDS(
  "output/transition_walk_drc_gc.rds"
)

friction <- raster::raster(
  "output/friction_walk_drc_buffer.tif"
)

stopifnot(raster::isLonLat(friction))


# 4. Calculate modelled walking-route distances
route_km <- rep(NA_real_, nrow(pairs))
route_status <- rep("Not calculated", nrow(pairs))
route_geometry <- vector("list", nrow(pairs))

for (i in seq_len(nrow(pairs))) {
  
  origin <- as.numeric(pairs[i, c("dps_lon", "dps_lat")])
  destination <- as.numeric(pairs[i, c("site_lon", "site_lat")])
  
  cells <- raster::cellFromXY(
    friction,
    rbind(origin, destination)
  )
  
  if (anyNA(cells)) {
    route_status[i] <- "Outside raster"
    next
  }
  
  if (cells[1] == cells[2]) {
    if (all(abs(origin - destination) < 1e-10)) {
      route_km[i] <- 0
      route_status[i] <- "Co-located"
    } else {
      route_status[i] <- "Same raster cell: unresolved"
    }
    next
  }
  
  path <- tryCatch(
    gdistance::shortestPath(
      transition,
      origin,
      destination,
      output = "SpatialLines"
    ),
    error = function(e) NULL
  )
  
  if (is.null(path)) {
    route_status[i] <- "Route unavailable"
    next
  }
  
  path_sf <- sf::st_as_sf(path)
  
  # The returned SpatialLines geometry can lack CRS metadata.
  # The cached MAP raster uses longitude/latitude coordinates.
  if (is.na(sf::st_crs(path_sf))) {
    sf::st_crs(path_sf) <- 4326
  }
  
  stopifnot(sf::st_is_longlat(path_sf))
  
  route_km[i] <- sum(
    as.numeric(sf::st_length(path_sf))
  ) / 1000
  
  route_geometry[[i]] <- sf::st_geometry(path_sf)[[1]]
  route_status[i] <- "Calculated"
  
  if (i %% 10 == 0) {
    message("Walking routes completed: ", i, "/", nrow(pairs))
  }
}

pairs$walking_route_km <- round(route_km, 2)
pairs$route_status <- route_status


# 5. Reuse the 2014 route distances
pairs26$walking_route_km <- pairs$walking_route_km[
  11 + match26
]

pairs26$route_status <- pairs$route_status[
  11 + match26
]

walking_routes <- rbind(
  pairs[pairs$network == 11, ],
  pairs26,
  pairs[pairs$network == 51, ]
)

walking_routes <- walking_routes[
  order(walking_routes$network),
]

rownames(walking_routes) <- NULL


# 6. Add the existing walking travel times
baseline <- read.csv(
  file.path(out_dir, "site_level_results.csv")
)

baseline <- baseline[baseline$mode == "walking", ]

key_routes <- paste(
  walking_routes$network,
  clean_name(walking_routes$sentinel_site)
)

key_baseline <- paste(
  baseline$network,
  clean_name(baseline$sentinel_site)
)

index <- match(key_routes, key_baseline)

stopifnot(!anyNA(index))

walking_routes$straight_km <- baseline$straight_km[index]
walking_routes$walking_hours <- baseline$time_hours[index]


# 7. Save the unified walking-distance table
walking_routes <- walking_routes[
  ,
  c(
    "network",
    "province",
    "sentinel_site",
    "straight_km",
    "walking_route_km",
    "walking_hours",
    "route_status"
  )
]

write.csv(
  walking_routes,
  file.path(out_dir, "walking_route_distances.csv"),
  row.names = FALSE
)


# 8. Save calculated walking-route geometries
valid <- which(route_status == "Calculated")

if (length(valid) > 0) {
  
  geometries <- do.call(
    sf::st_sfc,
    c(route_geometry[valid], list(crs = 4326))
  )
  
  route_lines <- sf::st_sf(
    pairs[valid, c("network", "province", "sentinel_site")],
    geometry = geometries
  )
  
  sf::st_write(
    route_lines,
    file.path(out_dir, "walking_routes.gpkg"),
    delete_dsn = TRUE,
    quiet = TRUE
  )
}


# 9. Display results
print(
  table(
    walking_routes$network,
    walking_routes$route_status
  )
)

print(
  walking_routes[
    grepl("Katana", walking_routes$sentinel_site, ignore.case = TRUE),
  ],
  row.names = FALSE
)
