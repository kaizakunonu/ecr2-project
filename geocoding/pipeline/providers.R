# Provider adapters for the geocoding pipeline.
#
# Source after config.R and geocode-functions.R.
#
# Every adapter answers one query variant -- a row of build_query_variants() --
# with list(status, n_results, candidates), where `candidates` has the columns
# of empty_candidates(). Each translates its provider's notion of a place into
# the gate's vocabulary:
#
#   kind      area | linear | settlement | establishment | other. The gate
#             rejects areas (the centroid of a province or health zone) and
#             linear features (streets, rivers).
#   admin1    the province, which the gate checks against the expected one.
#   name      the place's own name, if the provider gives one; the gate then
#             compares whole names (whole_name_similarity()). Google gives
#             none, and is matched on its address as before.
#   place_id  the provider's id; prefixed ("osm:node/1", "grid3:...") for all
#             but Google, so nobody mistakes one for a Google place ID.
#
# Requests go through cached_fetch() and throttle(), so a cached answer costs
# nothing and live requests respect each provider's rate in config.R.

GOOGLE_GEOCODE_URL <- "https://maps.googleapis.com/maps/api/geocode/json"
NOMINATIM_URL      <- "https://nominatim.openstreetmap.org/search"
PHOTON_URL         <- "https://photon.komoot.io/api/"
GEONAMES_URL       <- "https://secure.geonames.org/searchJSON"

# Nominatim requires an identifying User-Agent; stock library agents are refused.
USER_AGENT <- "ecr2-geocoding/1.0 (MAP Early Career Researcher study, DRC sentinel sites)"

# ---------------------------------------------------------------------------
# Shared plumbing
# ---------------------------------------------------------------------------

#' The candidate schema, with no rows.
empty_candidates <- function() {
  tibble(
    lat = numeric(0), lon = numeric(0), formatted_address = character(0),
    location_type = character(0), types = character(0),
    partial_match = logical(0), place_id = character(0),
    admin1 = character(0), admin2 = character(0), locality = character(0),
    provider = character(0), kind = character(0),
    name = character(0), name_alt = character(0)
  )
}

#' Wrap parsed candidates (possibly none) as an adapter's response.
as_response <- function(candidates) {
  if (is.null(candidates) || nrow(candidates) == 0) candidates <- empty_candidates()
  list(status     = if (nrow(candidates) > 0) "OK" else "ZERO_RESULTS",
       n_results  = nrow(candidates),
       candidates = candidates)
}

#' A stable cache key for a set of query parameters.
query_key <- function(params) {
  paste(names(params), unlist(params), sep = "=", collapse = "&")
}

#' GET a JSON endpoint, throttled and counted against `provider`.
#'
#' Messages name the provider but never the URL, which can carry a credential.
http_get_json <- function(url, query, provider) {
  throttle(provider)
  response <- httr::RETRY("GET", url, query = query, httr::user_agent(USER_AGENT),
                          times = 3, pause_base = 1, quiet = TRUE)
  if (httr::status_code(response) != 200) {
    stop(provider, " returned HTTP ", httr::status_code(response), call. = FALSE)
  }
  jsonlite::fromJSON(httr::content(response, as = "text", encoding = "UTF-8"),
                     simplifyVector = FALSE)
}

.reference <- new.env(parent = emptyenv())

#' A province's extent, c(lon_min, lat_min, lon_max, lat_max), padded by `pad`
#' degrees, from the outlines in reference/drc_provinces.csv.
province_bbox <- function(province, path = paths$provinces, pad = 0.1) {
  if (is.null(.reference$provinces)) {
    .reference$provinces <- read.csv(path, stringsAsFactors = FALSE)
  }
  p    <- .reference$provinces
  rows <- p[normalise_name(p$province) == normalise_name(province), ]
  if (nrow(rows) == 0) stop("No outline for province '", province, "' in ", path, call. = FALSE)
  c(min(rows$lon) - pad, min(rows$lat) - pad, max(rows$lon) + pad, max(rows$lat) + pad)
}

# ---------------------------------------------------------------------------
# Google Geocoding API
# ---------------------------------------------------------------------------

#' Pull a named component out of a Google address_components block.
extract_component <- function(components, type) {
  for (comp in components) {
    if (type %in% unlist(comp$types)) return(comp$long_name)
  }
  NA_character_
}

#' Flatten one Google result into a single-row tibble.
parse_google_result <- function(res) {
  tibble(
    lat               = res$geometry$location$lat %||% NA_real_,
    lon               = res$geometry$location$lng %||% NA_real_,
    formatted_address = res$formatted_address %||% NA_character_,
    location_type     = res$geometry$location_type %||% NA_character_,
    types             = paste(unlist(res$types), collapse = "|"),
    partial_match     = isTRUE(res$partial_match),
    place_id          = res$place_id %||% NA_character_,
    admin1            = extract_component(res$address_components, "administrative_area_level_1"),
    admin2            = extract_component(res$address_components, "administrative_area_level_2"),
    locality          = extract_component(res$address_components, "locality")
  )
}

#' Add the provider-neutral columns to Google candidates.
#'
#' Applied after the cache, because responses cached before there were other
#' providers lack them.
complete_google_candidates <- function(candidates) {
  if (nrow(candidates) == 0) return(empty_candidates())
  candidates |>
    mutate(provider = "google",
           kind     = google_kind(location_type, types),
           name     = NA_character_,
           name_alt = NA_character_)
}

#' Query the Google Geocoding API.
#'
#' Returns a list with `status` and `candidates` (a tibble, one row per result,
#' empty when there are none). Errors that are the caller's fault -- a bad or
#' unauthorised key, a malformed request -- stop rather than being recorded as
#' an ordinary geocoding miss. The key is read only when a request has to go
#' out, so a cached run needs none.
geocode_google <- function(address, components, language = country_profile$language) {

  out <- cached_fetch("google", cache_key(address, components), function() {
    key <- provider_credential("google")
    throttle("google")
    response <- httr::RETRY(
      "GET", GOOGLE_GEOCODE_URL,
      query = list(
        address    = address,
        components = components,
        language   = language,
        key        = key
      ),
      times = 3,
      pause_base = 1,
      quiet = TRUE
    )

    if (httr::status_code(response) != 200) {
      stop("Google Geocoding API returned HTTP ", httr::status_code(response),
           " for address '", address, "'.", call. = FALSE)
    }

    body <- httr::content(response, as = "parsed", type = "application/json")

    # Distinguish "no match" from "your request was rejected".
    if (body$status %in% c("REQUEST_DENIED", "OVER_QUERY_LIMIT", "INVALID_REQUEST",
                           "UNKNOWN_ERROR")) {
      stop("Google Geocoding API status '", body$status, "' for address '", address,
           "'", if (!is.null(body$error_message)) paste0(": ", body$error_message) else "",
           call. = FALSE)
    }

    candidates <- if (body$status == "OK" && length(body$results) > 0) {
      map(body$results, parse_google_result) |> list_rbind()
    } else {
      empty_candidates() |> select(lat:locality)
    }

    list(status = body$status, n_results = nrow(candidates), candidates = candidates)
  })

  out$candidates <- complete_google_candidates(out$candidates)
  out
}

# ---------------------------------------------------------------------------
# OpenStreetMap: Nominatim and Photon
# ---------------------------------------------------------------------------

OSM_SETTLEMENTS <- c("city", "town", "village", "hamlet", "suburb", "neighbourhood",
                     "quarter", "locality", "isolated_dwelling")
OSM_AREAS       <- c("state", "province", "region", "county", "district",
                     "municipality", "country")
OSM_STOPS       <- c("station", "halt", "stop", "tram_stop")
OSM_BUILDINGS   <- c("amenity", "building", "office", "shop", "tourism",
                     "healthcare", "aeroway", "man_made", "leisure", "historic",
                     "craft", "emergency", "public_transport", "club")

#' What kind of place an OSM feature is, from its main tag (key=value).
#'
#' Health zones are mapped in the DRC as boundary=health polygons, and both
#' Nominatim and Photon return them for a health zone's name; the gate rejects
#' them as areas.
osm_kind <- function(key, value) {
  map2_chr(key, value, function(k, v) {
    k <- k %|na|% ""
    v <- v %|na|% ""
    if (k == "place" && v %in% OSM_SETTLEMENTS) return("settlement")
    if (k == "place" && v %in% OSM_AREAS)       return("area")
    if (k == "boundary")                        return("area")
    if (k %in% c("highway", "waterway"))        return("linear")
    if (k == "railway")                         return(if (v %in% OSM_STOPS) "establishment" else "linear")
    if (k %in% OSM_BUILDINGS)                   return("establishment")
    "other"
  })
}

#' Flatten one Nominatim result (format=jsonv2, addressdetails, namedetails).
parse_nominatim_result <- function(r) {
  addr  <- r$address %||% list()
  nd    <- r$namedetails %||% list()
  key   <- nz(r$category %||% r$class)
  value <- nz(r$type)
  alt   <- unique(unlist(nd[names(nd) %in% c("name:fr", "alt_name", "old_name",
                                             "official_name", "short_name")]))
  tibble(
    lat               = as.numeric(r$lat %||% NA),
    lon               = as.numeric(r$lon %||% NA),
    formatted_address = nz(r$display_name),
    location_type     = NA_character_,
    types             = paste0(key, "=", value),
    partial_match     = FALSE,
    place_id          = paste0("osm:", nz(r$osm_type), "/", nz(r$osm_id)),
    admin1            = nz(addr$state),
    admin2            = nz(addr$county),
    locality          = nz(addr$city %||% addr$town %||% addr$village %||% addr$hamlet),
    provider          = "nominatim",
    kind              = osm_kind(key, value),
    name              = nz(r$name %||% nd$name),
    name_alt          = if (length(alt) > 0) paste(alt, collapse = "|") else NA_character_
  )
}

#' Query Nominatim.
#'
#' A pinned rung is a structured query, which Nominatim does honour: the
#' settlement in city= (or an office in amenity=) and the province in state=.
#' A free rung is free text. Both are restricted to the country.
geocode_nominatim <- function(q, profile = country_profile) {
  params <- list(format = "jsonv2", addressdetails = 1, namedetails = 1,
                 `accept-language` = profile$language, limit = 10,
                 countrycodes = tolower(profile$country_code))
  if (isTRUE(q$pinned)) {
    params[[if (q$target == "settlement") "city" else "amenity"]] <- q$address
    params$state <- q$province
  } else {
    params$q <- q$address
  }

  cached_fetch("nominatim", query_key(params), function() {
    email <- Sys.getenv("NOMINATIM_EMAIL")
    if (nzchar(email)) params$email <- email
    body <- http_get_json(NOMINATIM_URL, params, "nominatim")
    as_response(map(body, parse_nominatim_result) |> list_rbind())
  })
}

#' Flatten one Photon GeoJSON feature.
#'
#' Photon has no display name, so one is assembled from the address parts.
parse_photon_feature <- function(f) {
  p    <- f$properties
  xy   <- unlist(f$geometry$coordinates)
  name <- nz(p$name)
  osm_types <- c(N = "node", W = "way", R = "relation")
  parts <- c(name, nz(p$district), nz(p$city), nz(p$county), nz(p$state), nz(p$country))
  tibble(
    lat               = as.numeric(xy[2]),
    lon               = as.numeric(xy[1]),
    formatted_address = paste(unique(parts[!is.na(parts)]), collapse = ", "),
    location_type     = NA_character_,
    types             = paste0(nz(p$osm_key), "=", nz(p$osm_value)),
    partial_match     = FALSE,
    place_id          = paste0("osm:", unname(osm_types[nz(p$osm_type)]) %|na|% nz(p$osm_type),
                               "/", nz(p$osm_id)),
    admin1            = nz(p$state),
    admin2            = nz(p$county),
    locality          = nz(p$city),
    provider          = "photon",
    kind              = osm_kind(nz(p$osm_key), nz(p$osm_value)),
    name              = name,
    name_alt          = NA_character_
  )
}

#' Query Photon.
#'
#' Photon has no province filter, so a pinned rung restricts it to the
#' province's bounding box instead; both kinds stay inside the country.
geocode_photon <- function(q, profile = country_profile) {
  params <- list(q = q$address, countrycode = profile$country_code,
                 lang = profile$language, limit = 10)
  if (isTRUE(q$pinned)) params$bbox <- paste(province_bbox(q$province), collapse = ",")

  cached_fetch("photon", query_key(params), function() {
    body <- http_get_json(PHOTON_URL, params, "photon")
    as_response(map(body$features, parse_photon_feature) |> list_rbind())
  })
}

# ---------------------------------------------------------------------------
# GeoNames
# ---------------------------------------------------------------------------

#' What kind of place a GeoNames feature is, from its feature class and code.
geonames_kind <- function(fcl, fcode) {
  map2_chr(fcl, fcode, function(cl, code) {
    cl   <- cl %|na|% ""
    code <- code %|na|% ""
    if (cl == "P") return("settlement")
    if (cl == "A") return("area")
    if (cl == "R") return("linear")
    if (cl == "H" && startsWith(code, "STM")) return("linear")
    if (cl == "S") return("establishment")
    "other"
  })
}

#' Flatten one GeoNames result (style=FULL).
#'
#' The province comes from adminCode1 through `geonames_admin1` in config.R,
#' because GeoNames names provinces in English. A code outside the table --
#' one of the pre-2015 provinces -- keeps GeoNames' own name, which the gate
#' then refuses.
parse_geonames_result <- function(g, codes = geonames_admin1) {
  code     <- nz(g$adminCode1)
  province <- names(codes)[match(code, codes)] %|na|% nz(g$adminName1)
  alt      <- map_chr(keep(g$alternateNames %||% list(),
                           \(a) (a$lang %||% "") %in% c("fr", "")),
                      \(a) nz(a$name))
  alt      <- unique(c(nz(g$toponymName), alt))
  alt      <- alt[!is.na(alt) & alt != nz(g$name)]
  parts    <- c(nz(g$name), nz(g$adminName2), province)
  tibble(
    lat               = as.numeric(g$lat %||% NA),
    lon               = as.numeric(g$lng %||% NA),
    formatted_address = paste(parts[!is.na(parts)], collapse = ", "),
    location_type     = NA_character_,
    types             = paste0(nz(g$fcl), ".", nz(g$fcode)),
    partial_match     = FALSE,
    place_id          = paste0("geonames:", nz(g$geonameId)),
    admin1            = province,
    admin2            = nz(g$adminName2),
    locality          = NA_character_,
    provider          = "geonames",
    kind              = geonames_kind(nz(g$fcl), nz(g$fcode)),
    name              = nz(g$name),
    name_alt          = if (length(alt) > 0) paste(alt, collapse = "|") else NA_character_
  )
}

#' Query GeoNames for populated places.
#'
#' A pinned rung searches place names within the province's admin1 code; a
#' free rung searches every field across the country.
geocode_geonames <- function(q, profile = country_profile, codes = geonames_admin1) {
  params <- list(country = profile$country_code, featureClass = "P",
                 style = "FULL", maxRows = 10, lang = profile$language)
  if (isTRUE(q$pinned)) {
    params$name       <- q$address
    params$adminCode1 <- unname(codes[match(normalise_name(q$province),
                                            normalise_name(names(codes)))])
  } else {
    params$q <- q$address
  }

  cached_fetch("geonames", query_key(params), function() {
    params$username <- provider_credential("geonames")
    body <- http_get_json(GEONAMES_URL, params, "geonames")
    if (!is.null(body$status)) {
      stop("GeoNames error ", body$status$value, ": ", body$status$message, call. = FALSE)
    }
    as_response(map(body$geonames, parse_geonames_result) |> list_rbind())
  })
}

# ---------------------------------------------------------------------------
# GRID3
# ---------------------------------------------------------------------------
#
# GRID3 is not a geocoder but a set of public tables, so whole tables are
# fetched once, cached, and matched locally:
#   - the health-zone central offices (BCZ), which stand in for a health zone's
#     chef-lieu, for rungs that look for a health zone;
#   - settlement names, one province at a time, for rungs that look for a
#     settlement.
# GRID3 settlements have no town or city type, and village names repeat:
# "Nyemba" in Tanganyika is five villages in three other health zones and not
# the town. A settlement is therefore matched only inside the health zone of
# the same name. A site whose health zone is named differently finds nothing
# here and falls through to the next provider.

GRID3_FACILITY_FIELDS   <- "OBJECTID,province,zonesante,zs_uid,airesante,localite,essnom1,esstype,lat,lon,precision_,grid3id"
GRID3_SETTLEMENT_FIELDS <- "OBJECTID,province,zonesante,zs_uid,airesante,localite,localite_alt,localitetype,lat,lon,precision_,grid3id,source_acronym"

#' Turn ArcGIS feature attributes into a tibble, one column per field.
parse_arcgis_rows <- function(rows) {
  if (length(rows) == 0) return(tibble())
  fields <- names(rows[[1]])
  map(fields, \(f) unlist(map(rows, \(r) r[[f]] %||% NA))) |>
    setNames(fields) |>
    as_tibble()
}

#' Every row of a GRID3 layer matching `where`, page by page.
grid3_query <- function(layer, where, out_fields, layers = grid3_layers) {
  url    <- paste(layers$service, layer, "FeatureServer/0/query", sep = "/")
  rows   <- list()
  offset <- 0
  repeat {
    body <- http_get_json(url, list(where = where, outFields = out_fields,
                                    returnGeometry = "false", orderByFields = "OBJECTID",
                                    resultOffset = offset, resultRecordCount = 2000,
                                    f = "json"), "grid3")
    if (!is.null(body$error)) stop("GRID3 query failed: ", body$error$message, call. = FALSE)
    rows <- c(rows, map(body$features, "attributes"))
    if (!isTRUE(body$exceededTransferLimit) || length(body$features) == 0) break
    offset <- offset + length(body$features)
  }
  parse_arcgis_rows(rows)
}

#' The BCZ of every health zone.
grid3_bcz_table <- function(layers = grid3_layers) {
  cached_fetch("grid3", "bcz", function() {
    list(table = grid3_query(layers$facilities,
                             sprintf("esstype='%s'", layers$bcz_type),
                             GRID3_FACILITY_FIELDS))
  })$table
}

#' GRID3's spelling of a province name.
grid3_province_name <- function(province, layers = grid3_layers) {
  known <- cached_fetch("grid3", "provinces", function() {
    url  <- paste(layers$service, layers$settlements, "FeatureServer/0/query", sep = "/")
    body <- http_get_json(url, list(where = "1=1", outFields = "province",
                                    returnDistinctValues = "true",
                                    returnGeometry = "false", f = "json"), "grid3")
    list(names = map_chr(body$features, \(f) f$attributes$province))
  })$names
  hit <- known[normalise_name(known) == normalise_name(province)]
  if (length(hit) == 0) stop("GRID3 has no province '", province, "'.", call. = FALSE)
  hit[[1]]
}

#' Every settlement in one province.
grid3_settlement_table <- function(province, layers = grid3_layers) {
  exact <- grid3_province_name(province, layers)
  cached_fetch("grid3", paste0("settlements|", exact), function() {
    list(table = grid3_query(layers$settlements,
                             sprintf("province='%s'", gsub("'", "''", exact)),
                             GRID3_SETTLEMENT_FIELDS))
  })$table
}

#' The BCZ of the health zones in `province` named like `name`, best first.
grid3_match_bcz <- function(name, province, table = grid3_bcz_table(),
                            floor = gate$similarity_floor) {
  rows <- table[normalise_name(table$province) == normalise_name(province), ]
  sim  <- whole_name_similarity(name, rows$zonesante)
  rows <- rows[sim >= floor, ][order(-sim[sim >= floor]), ]
  if (nrow(rows) == 0) return(empty_candidates())
  tibble(
    lat               = as.numeric(rows$lat),
    lon               = as.numeric(rows$lon),
    formatted_address = paste0(rows$essnom1, ", ", rows$localite, ", ZS ",
                               rows$zonesante, ", ", rows$province),
    location_type     = NA_character_,
    types             = paste0("esstype=", rows$esstype),
    partial_match     = FALSE,
    place_id          = paste0("grid3:", rows$grid3id),
    admin1            = rows$province,
    admin2            = rows$zonesante,        # the health zone
    locality          = rows$localite,
    provider          = "grid3",
    kind              = "establishment",
    name              = rows$zonesante,
    name_alt          = str_remove(rows$essnom1, "^BCZ\\s+")
  )
}

#' What kind of place a GRID3 settlement is, from its localitetype.
#'
#' A bloc is a block of an urban neighbourhood, so it counts as a settlement,
#' as Google's neighbourhoods do.
grid3_settlement_kind <- function(type) {
  type <- normalise_name(type)
  case_when(
    type %in% c("village", "hameau", "quartier", "bloc", "ilot", "campement",
                "ferme", "miniere") ~ "settlement",
    type == "avenue" ~ "linear",
    TRUE ~ "other"
  )
}

#' Settlements named `name` inside a health zone named like `name`, in
#' `province`, best first.
#'
#' The health zone may be spelled differently (`floor`), being one of a short
#' list. The settlement's own name must match cleanly (`clean`): a health zone
#' holds hundreds of villages, many with near-identical names, and a near
#' match is a different village -- Kalema for Kalima, Kabona for Katana, Iwela
#' for Ikela, each a few to 25 km from the town.
grid3_match_settlement <- function(name, province,
                                   table = grid3_settlement_table(province),
                                   floor = gate$similarity_floor,
                                   clean = gate$similarity_clean) {
  rows   <- table[normalise_name(table$province) == normalise_name(province), ]
  zs_sim <- whole_name_similarity(name, rows$zonesante)
  nm_sim <- pmax(whole_name_similarity(name, rows$localite),
                 whole_name_similarity(name, rows$localite_alt))
  keep   <- zs_sim >= floor & nm_sim >= clean
  rows   <- rows[keep, ][order(-nm_sim[keep], -zs_sim[keep]), ]
  if (nrow(rows) == 0) return(empty_candidates())
  tibble(
    lat               = as.numeric(rows$lat),
    lon               = as.numeric(rows$lon),
    formatted_address = paste0(rows$localite, ", AS ", rows$airesante, ", ZS ",
                               rows$zonesante, ", ", rows$province),
    location_type     = NA_character_,
    types             = paste0("localitetype=", rows$localitetype),
    partial_match     = FALSE,
    place_id          = paste0("grid3:", rows$grid3id),
    admin1            = rows$province,
    admin2            = rows$zonesante,        # the health zone
    locality          = rows$localite,
    provider          = "grid3",
    kind              = grid3_settlement_kind(rows$localitetype),
    name              = rows$localite,
    name_alt          = as.character(rows$localite_alt)
  )
}

#' Answer a query variant from the GRID3 tables.
#'
#' Only pinned rungs: every GRID3 row carries its province, so a country-wide
#' search would add nothing the gate would accept. A health zone is answered
#' with its BCZ; a settlement with a same-named settlement in the same-named
#' health zone; an office (a DPS) not at all, as GRID3 lists none.
geocode_grid3 <- function(q, profile = country_profile) {
  if (!isTRUE(q$pinned)) return(as_response(NULL))
  as_response(switch(q$target,
    health_zone = grid3_match_bcz(q$name, q$province),
    settlement  = grid3_match_settlement(q$name, q$province),
    NULL
  ))
}

# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

provider_fetchers <- list(
  google    = function(q, profile) geocode_google(q$address, q$components, profile$language),
  grid3     = geocode_grid3,
  nominatim = geocode_nominatim,
  geonames  = geocode_geonames,
  photon    = geocode_photon
)
