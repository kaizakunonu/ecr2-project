# Origin-destination pairs: each DPS headquarters joined to its sentinel site.
#
# Source after config.R and geocode-functions.R, which provide make_id(),
# normalise_name(), haversine_km() and the tidyverse functions used here.
#
# A pair is keyed by names, as the workbook lists them (network, province, dps,
# sentinel_site), and resolved against two registries: the geocoded DPS seats
# and the geocoded sentinel sites. A new network is new rows in the pairs file.
#
# `province` is the province as the network named it, so the 2003-2005 pairs
# keep their pre-2015 names. Both registries record the current province each
# point lies in; the 2015 split in config.R connects the two.

#' The current provinces a province name covers.
#'
#' A 1988-2015 province returns what it became in 2015; a current province
#' returns itself; anything else returns NA. Equateur and Kasai-Oriental name
#' both an old and a current province and resolve to the old, larger set -- for
#' a current-province pair, province_mismatch still flags a site outside its
#' DPS's own province.
successor_provinces <- function(province) {
  key <- normalise_name(province)
  old <- match(key, normalise_name(names(provinces_pre2015)))
  if (!is.na(old)) return(provinces_pre2015[[old]])
  current <- match(key, normalise_name(drc_provinces))
  if (!is.na(current)) return(drc_provinces[current])
  NA_character_
}

#' Join each pair to the coordinates of both of its points.
#'
#' Stops if a pair names a DPS or site missing from its registry: a new
#' network's sites must be geocoded by the sentinel workflow first. Also stops
#' if a pair's DPS seat or site lies outside what its province became in 2015,
#' which means the wrong DPS or site for that province. Pairs whose points lack
#' coordinates are kept and marked incomplete, not dropped. The result is in
#' chronological order of network. Where the registries record where each
#' coordinate came from (`geocode_status`), it is kept as `dps_source` and
#' `site_source`.
build_pairs <- function(pairs, dps, sites, co_located_km = 1) {

  # A network is named from the year it began ("2003_2005", "2014"), so sorting
  # by name is chronological. Rows keep their input order within a network.
  undated <- unique(pairs$network[!str_detect(pairs$network, "^[0-9]{4}")])
  if (length(undated) > 0) {
    stop("Network names must start with the year the network began ",
         "(e.g. 2003_2005, 2014): ", paste(undated, collapse = ", "), call. = FALSE)
  }

  pairs <- pairs |>
    mutate(
      network = as.character(network),
      dps_id  = make_id(dps, dps_profile$id_prefix),
      site_id = make_id(sentinel_site, country_profile$id_prefix),
      .row    = row_number()
    ) |>
    arrange(network, .row) |>
    select(-.row)

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

  unknown <- unique(pairs$province[map_lgl(pairs$province,
                                           \(p) anyNA(successor_provinces(p)))])
  if (length(unknown) > 0) {
    stop("Unrecognised province(s) in the pairs file: ",
         paste(unknown, collapse = ", "),
         ".\nUse a current or a 1988-2015 province name.", call. = FALSE)
  }

  # The DPS name comes from the pair, not the registry: a seat shared by an old
  # and a current DPS keeps the name its network used ("DPS Kasaï Oriental").
  out <- pairs |>
    select(network, network_province = province, dps, dps_id, site_id) |>
    left_join(
      dps |> select(dps_id, dps_province = province, chef_lieu,
                    dps_lat = latitude, dps_lon = longitude,
                    dps_confidence = confidence, dps_basis = point_basis,
                    any_of(c(dps_source = "geocode_status"))),
      by = "dps_id"
    ) |>
    left_join(
      sites |> select(site_id, sentinel_site, site_province = province,
                      site_lat = latitude, site_lon = longitude,
                      site_confidence = confidence,
                      any_of(c(site_source = "geocode_status"))),
      by = "site_id"
    )

  in_successors <- function(prov, network_prov) {
    map2_lgl(prov, network_prov,
             \(p, n) normalise_name(p) %in% normalise_name(successor_provinces(n)))
  }
  outside <- out |>
    filter(!in_successors(dps_province, network_province) |
             !in_successors(site_province, network_province))
  if (nrow(outside) > 0) {
    stop("Pairs outside what their province became in 2015:\n",
         paste0("  ", outside$network, " ", outside$network_province, ": ",
                outside$dps, " (", outside$dps_province, ") / ",
                outside$sentinel_site, " (", outside$site_province, ")",
                collapse = "\n"),
         "\nCheck the DPS and site paired under that province.", call. = FALSE)
  }

  out |>
    mutate(
      straight_line_km  = haversine_km(dps_lat, dps_lon, site_lat, site_lon),
      complete          = !is.na(straight_line_km),
      co_located        = complete & straight_line_km < co_located_km,
      province_mismatch = normalise_name(dps_province) != normalise_name(site_province)
    )
}
