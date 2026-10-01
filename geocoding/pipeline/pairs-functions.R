# Origin-destination pairs: each DPS headquarters joined to its sentinel site.
#
# Source after config.R and geocode-functions.R, which provide make_id(),
# normalise_name() and the tidyverse functions used here.
#
# A pair is keyed by names, as the workbook lists them (network, dps,
# sentinel_site), and resolved against two registries: the geocoded DPS and
# the geocoded sentinel sites. A new network is new rows in the pairs file.

#' Great-circle distance in kilometres.
#'
#' A straight line, not a travel distance: it is here to catch blunders (a pair
#' hundreds of km apart within one province) and co-located pairs.
haversine_km <- function(lat1, lon1, lat2, lon2, radius = 6371) {
  rad  <- pi / 180
  dlat <- (lat2 - lat1) * rad
  dlon <- (lon2 - lon1) * rad
  a <- sin(dlat / 2)^2 + cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2)^2
  2 * radius * asin(pmin(1, sqrt(a)))
}

#' Join each pair to the coordinates of both of its points.
#'
#' Stops if a pair names a DPS or site missing from its registry: a new
#' network's sites must be geocoded by the sentinel workflow first. Pairs whose
#' points lack coordinates are kept and marked incomplete, not dropped.
build_pairs <- function(pairs, dps, sites, co_located_km = 1) {

  pairs <- pairs |>
    mutate(
      dps_id  = make_id(dps, dps_profile$id_prefix),
      site_id = make_id(sentinel_site, country_profile$id_prefix)
    )

  missing <- c(setdiff(pairs$dps_id, dps$dps_id),
               setdiff(pairs$site_id, sites$site_id))
  if (length(missing) > 0) {
    stop("Pairs reference points that have not been geocoded: ",
         paste(unique(missing), collapse = ", "),
         ".\nAdd them to the DPS or sentinel input and re-render.", call. = FALSE)
  }

  dupes <- pairs |> count(network, site_id) |> filter(n > 1)
  if (nrow(dupes) > 0) {
    stop("A site is paired more than once within a network: ",
         paste(dupes$network, dupes$site_id, collapse = ", "), call. = FALSE)
  }

  pairs |>
    select(network, dps_id, site_id) |>
    left_join(
      dps |> select(dps_id, dps, dps_province = province, chef_lieu,
                    dps_lat = latitude, dps_lon = longitude,
                    dps_confidence = confidence, dps_basis = point_basis),
      by = "dps_id"
    ) |>
    left_join(
      sites |> select(site_id, sentinel_site, site_province = province,
                      site_lat = latitude, site_lon = longitude,
                      site_confidence = confidence),
      by = "site_id"
    ) |>
    mutate(
      straight_line_km  = haversine_km(dps_lat, dps_lon, site_lat, site_lon),
      complete          = !is.na(straight_line_km),
      co_located        = complete & straight_line_km < co_located_km,
      province_mismatch = normalise_name(dps_province) != normalise_name(site_province)
    )
}
