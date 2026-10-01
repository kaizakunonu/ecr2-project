# Geocoding functions for the DRC sentinel site pipeline.
#
# Provider: Google Maps Geocoding API, called directly over REST with httr.
# The REST response is used rather than a wrapper package because the quality
# gate depends on fields most wrappers discard: partial_match, location_type,
# types, and the number of results returned.

library(dplyr)
library(purrr)
library(stringr)
library(tibble)
library(httr)
library(jsonlite)

GOOGLE_GEOCODE_URL <- "https://maps.googleapis.com/maps/api/geocode/json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

`%||%` <- function(x, y) if (is.null(x)) y else x

#' Strip accents and punctuation so names can be compared across spellings
#' ("Kasai-Central" vs "Kasaï-Central", "Mwene-ditu" vs "Mwene-Ditu").
normalise_name <- function(x) {
  x |>
    as.character() |>
    iconv(to = "ASCII//TRANSLIT", sub = "") |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]+", " ") |>
    str_squish()
}

#' Apply the manual site-name corrections from config.R.
fix_site_name <- function(site, fixes = site_name_fixes) {
  key <- str_to_lower(str_trim(site))
  if (key %in% names(fixes)) fixes[[key]] else str_trim(site)
}

#' Similarity in [0, 1] between two names, using base R's edit distance.
#'
#' Google omits `locality` from many rural results, so NA inputs are ordinary
#' here and must score 0 rather than error.
name_similarity <- function(a, b) {
  a <- normalise_name(a)
  b <- normalise_name(b)
  if (length(a) != 1 || length(b) != 1) return(0)
  if (is.na(a) || is.na(b) || !nzchar(a) || !nzchar(b)) return(0)
  # A short site name inside a long formatted_address should still score high.
  if (str_detect(b, fixed(a)) || str_detect(a, fixed(b))) return(1)
  1 - (as.numeric(utils::adist(a, b)) / max(nchar(a), nchar(b)))
}

#' Check that every province in the input is one of the current 26.
#'
#' Catches typos and any lapse back into pre-2015 province names, either of
#' which would silently weaken the province constraint on every query.
validate_provinces <- function(sites, provinces = drc_provinces,
                               profile = country_profile) {
  found   <- unique(sites[[profile$province_col]])
  unknown <- found[!(normalise_name(found) %in% normalise_name(provinces))]

  if (length(unknown) > 0) {
    stop("Unrecognised province(s): ", paste(unknown, collapse = ", "),
         ".\nThe input must use the current 26-province names.", call. = FALSE)
  }
  invisible(found)
}

#' Ensure every row carries a stable identifier.
#'
#' The 26-province input has no `site_id`, yet it is the key that joins results
#' back to the input and matches rows in manual_overrides.csv. Derive one from
#' the site name rather than the row number, so an override survives the file
#' being re-sorted in a spreadsheet.
ensure_site_id <- function(sites, profile = country_profile) {
  if (!is.null(sites[[profile$id_col]])) return(sites)

  ids <- make_id(sites[[profile$site_col]], profile$id_prefix)

  if (anyDuplicated(ids)) {
    stop("Site names are not unique, so they cannot form a stable site_id: ",
         paste(unique(ids[duplicated(ids)]), collapse = ", "), call. = FALSE)
  }

  sites[[profile$id_col]] <- ids
  sites
}

#' The identifier for a name: "Mwene-ditu" -> "DRC-MWENE-DITU".
#'
#' Separate from ensure_site_id() so that a pairs table, where the same DPS
#' recurs across networks, can derive the same keys without the uniqueness check.
make_id <- function(x, prefix = country_profile$id_prefix) {
  slug <- normalise_name(x) |>
    str_replace_all(" ", "-") |>
    str_to_upper()
  paste0(prefix, "-", slug)
}

# ---------------------------------------------------------------------------
# Response cache
# ---------------------------------------------------------------------------
#
# Keyed on address + components, so re-rendering the document costs zero API
# calls and yields identical coordinates.
#
# Note: Google Maps Platform terms allow only limited temporary caching of
# geocoding results (place IDs excepted). Treat this as a short-lived local
# convenience for iteration, not as a permanent store -- delete the file to
# force a fresh set of lookups.

.geocode_cache <- new.env(parent = emptyenv())

cache_key <- function(address, components) paste0(address, "|", components)

cache_load <- function(path = paths$cache) {
  .geocode_cache$store <- if (file.exists(path)) readRDS(path) else list()
  .geocode_cache$path  <- path
  .geocode_cache$hits  <- 0L
  .geocode_cache$calls <- 0L
  invisible(length(.geocode_cache$store))
}

cache_get <- function(address, components) {
  .geocode_cache$store[[cache_key(address, components)]]
}

cache_put <- function(address, components, value) {
  .geocode_cache$store[[cache_key(address, components)]] <- value
  invisible(value)
}

cache_save <- function(path = .geocode_cache$path) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(.geocode_cache$store, path)
  invisible(path)
}

# ---------------------------------------------------------------------------
# Provider: Google Geocoding API
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

#' Query the Google Geocoding API.
#'
#' Returns a list with `status` and `candidates` (a tibble, one row per result,
#' empty when there are none). Errors that are the caller's fault -- a bad or
#' unauthorised key, a malformed request -- stop rather than being recorded as
#' an ordinary geocoding miss.
geocode_google <- function(address,
                           components,
                           language = country_profile$language,
                           key      = Sys.getenv("GOOGLE_MAPS_API_KEY"),
                           use_cache = TRUE) {

  if (!nzchar(key)) {
    stop("GOOGLE_MAPS_API_KEY is not set. Export it before running the pipeline.",
         call. = FALSE)
  }

  if (use_cache) {
    cached <- cache_get(address, components)
    if (!is.null(cached)) {
      .geocode_cache$hits <- .geocode_cache$hits + 1L
      return(cached)
    }
  }

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
  .geocode_cache$calls <- .geocode_cache$calls + 1L

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
    parse_google_result_empty()
  }

  out <- list(
    status     = body$status,
    n_results  = nrow(candidates),
    candidates = candidates
  )

  if (use_cache) cache_put(address, components, out)
  out
}

parse_google_result_empty <- function() {
  tibble(
    lat = numeric(0), lon = numeric(0), formatted_address = character(0),
    location_type = character(0), types = character(0),
    partial_match = logical(0), place_id = character(0),
    admin1 = character(0), admin2 = character(0), locality = character(0)
  )
}

# ---------------------------------------------------------------------------
# Query construction
# ---------------------------------------------------------------------------

#' Build the ordered ladder of query variants for one site.
#'
#' Rungs 1-2 pin Google's `administrative_area` component filter to the site's
#' province. That filter is advisory rather than binding -- a live run returned
#' a Kinshasa business for a query pinned to Kasai -- so the province is also
#' verified against the response in assess_candidate(). Rungs 3-4 are free-text
#' fallbacks for sites the province-constrained queries miss, still restricted
#' to the country.
#'
#' The rung wording comes from `ladder` (see `ladders` in config.R), so another
#' point set -- the DPS headquarters -- reuses the ladder walk and the gate with
#' its own queries.
build_query_variants <- function(site, province, profile = country_profile,
                                 ladder = ladders$sentinel_site) {

  site <- fix_site_name(site)
  cc   <- paste0("country:", profile$country_code)
  pinned <- paste0(cc, "|administrative_area:", province)

  fill <- function(template) {
    template |>
      str_replace_all(fixed("{name}"), site) |>
      str_replace_all(fixed("{province}"), province) |>
      str_replace_all(fixed("{country}"), profile$name_fr)
  }

  tibble(
    rung       = as.integer(ladder$rung),
    rung_label = fill(ladder$label),
    address    = fill(ladder$template),
    components = if_else(ladder$pinned, pinned, cc)
  )
}

# ---------------------------------------------------------------------------
# Candidate assessment
# ---------------------------------------------------------------------------

ADMIN_LEVEL_TYPES <- c("administrative_area_level_1",
                       "administrative_area_level_2",
                       "country")

#' Judge a single candidate.
#'
#' Hard rejections are failures of kind -- the candidate is discarded and the
#' ladder keeps walking. Soft flags are doubts that lower confidence but keep
#' the candidate.
#'
#' Two of the four rejections come from a live run that reported 11/11 success
#' while quietly accepting a Kinshasa business as the location of Mikalayi, a
#' health zone some 700 km away in Kasai. Google's administrative_area filter
#' did not prevent it, so the province is verified against the response, and a
#' returned name bearing no resemblance to the site is refused outright.
#'
#' Note what is deliberately absent: no blacklist on `establishment` or
#' `point_of_interest` types. Both bad results carried them, but so would a
#' legitimate match on "Centre de Sante de ...". The province and similarity
#' checks catch the real failures without that false positive.
assess_candidate <- function(candidate, site, expected_provinces,
                             n_results = 1L, profile = country_profile,
                             thresholds = gate) {

  types <- str_split(candidate$types, fixed("|"))[[1]]
  reject <- character(0)
  flags  <- character(0)

  # A province-level APPROXIMATE hit means the query resolved to the enclosing
  # administrative area rather than to the site itself.
  if (identical(candidate$location_type, "APPROXIMATE") &&
      any(types %in% ADMIN_LEVEL_TYPES)) {
    reject <- c(reject, "administrative-area centroid, not a settlement")
  }

  bb <- profile$bbox
  if (is.na(candidate$lat) || is.na(candidate$lon) ||
      candidate$lat < bb$lat_min || candidate$lat > bb$lat_max ||
      candidate$lon < bb$lon_min || candidate$lon > bb$lon_max) {
    reject <- c(reject, "coordinates outside country bounding box")
  }

  province_known <- length(expected_provinces) > 0 && !is.na(candidate$admin1)
  province_match <- province_known &&
    normalise_name(candidate$admin1) %in% normalise_name(expected_provinces)

  # The component filter is advisory. If Google names a different province than
  # the one requested, the constraint did not hold and the point is worthless.
  if (province_known && !province_match) {
    reject <- c(reject, paste0("returned province '", candidate$admin1,
                               "' is not ", paste(expected_provinces, collapse = "/")))
  }

  similarity <- max(
    name_similarity(site, candidate$locality),
    name_similarity(site, candidate$formatted_address)
  )

  if (similarity < thresholds$similarity_floor) {
    reject <- c(reject, sprintf("returned name is unrelated to the site (similarity %.2f)",
                                similarity))
  }

  # partial_match fires on every rung-1 query simply because the result does
  # not contain the literal "Zone de Sante de " prefix. It is only meaningful
  # when the returned name is also a weak match.
  if (isTRUE(candidate$partial_match) && similarity < thresholds$similarity_clean) {
    flags <- c(flags, "partial name match")
  }
  if (n_results > 1)  flags <- c(flags, paste0(n_results, " results returned"))
  if (!province_known) flags <- c(flags, "province could not be verified")
  if (similarity < thresholds$similarity_clean) {
    flags <- c(flags, sprintf("imperfect name match (%.2f)", similarity))
  }

  list(
    accepted       = length(reject) == 0,
    reject_reason  = paste(reject, collapse = "; "),
    flags          = paste(flags, collapse = "; "),
    n_flags        = length(flags),
    province_match = province_match,
    similarity     = similarity
  )
}

#' Map an accepted candidate onto a confidence tier.
confidence_tier <- function(assessment, rung) {
  if (!assessment$accepted)                        return("failed")
  if (assessment$n_flags == 0 && rung <= 2)        return("high")
  if (assessment$n_flags <= 1 && rung <= 3)        return("medium")
  "low"
}

ESTABLISHMENT_TYPES <- c("establishment", "point_of_interest", "premise",
                         "subpremise", "health", "hospital",
                         "local_government_office")
SETTLEMENT_TYPES    <- c("locality", "sublocality", "neighborhood",
                         "colloquial_area", "administrative_area_level_3",
                         "administrative_area_level_4")

#' What kind of place a result is: "establishment", "settlement" or "other".
#'
#' Not part of the gate. A settlement is a town or neighbourhood centroid; an
#' establishment is a building. The Geocoding API returns no establishment
#' name, so an establishment in the right town passes the gate whichever
#' building it is. The DPS workflow uses this to send such hits to review.
point_basis <- function(types) {
  map_chr(str_split(types, fixed("|")), function(t) {
    t <- t[!is.na(t)]
    if (length(t) == 0)                         return(NA_character_)
    if (any(t %in% ESTABLISHMENT_TYPES))        return("establishment")
    if (any(t %in% SETTLEMENT_TYPES) ||
        any(startsWith(t, "sublocality")))      return("settlement")
    "other"
  })
}

# ---------------------------------------------------------------------------
# Per-site resolution
# ---------------------------------------------------------------------------

#' Walk the query ladder for one site, stopping at the first accepted candidate.
#'
#' Returns a list of `result` (single row) and `audit` (every candidate seen at
#' every rung, accepted or not).
geocode_site <- function(site_id, site, province, profile = country_profile,
                         ladder = ladders$sentinel_site) {

  variants  <- build_query_variants(site, province, profile, ladder)
  expected  <- province
  audit     <- list()
  resolved  <- NULL

  for (i in seq_len(nrow(variants))) {
    v <- variants[i, ]
    response <- geocode_google(v$address, v$components)
    Sys.sleep(profile$rate_delay)

    if (response$n_results == 0) {
      audit[[length(audit) + 1]] <- tibble(
        site_id = site_id, name = site,
        rung = v$rung, rung_label = v$rung_label,
        address = v$address, components = v$components,
        api_status = response$status, n_results = 0L,
        lat = NA_real_, lon = NA_real_, formatted_address = NA_character_,
        location_type = NA_character_, types = NA_character_,
        partial_match = NA, place_id = NA_character_,
        admin1 = NA_character_, admin2 = NA_character_, locality = NA_character_,
        accepted = FALSE, reject_reason = "no results", flags = NA_character_,
        similarity = NA_real_
      )
      next
    }

    for (j in seq_len(nrow(response$candidates))) {
      cand <- response$candidates[j, ]
      a <- assess_candidate(cand, site, expected, response$n_results, profile)

      audit[[length(audit) + 1]] <- tibble(
        site_id = site_id, name = site,
        rung = v$rung, rung_label = v$rung_label,
        address = v$address, components = v$components,
        api_status = response$status, n_results = response$n_results,
        lat = cand$lat, lon = cand$lon,
        formatted_address = cand$formatted_address,
        location_type = cand$location_type, types = cand$types,
        partial_match = cand$partial_match, place_id = cand$place_id,
        admin1 = cand$admin1, admin2 = cand$admin2, locality = cand$locality,
        accepted = a$accepted, reject_reason = a$reject_reason,
        flags = a$flags, similarity = a$similarity
      )

      if (a$accepted && is.null(resolved)) {
        resolved <- tibble(
          site_id           = site_id,
          latitude          = cand$lat,
          longitude         = cand$lon,
          geocode_status    = "google",
          confidence        = confidence_tier(a, v$rung),
          resolved_at_rung  = v$rung,
          rung_label        = v$rung_label,
          query_address     = v$address,
          query_components  = v$components,
          matched_address   = cand$formatted_address,
          matched_admin1    = cand$admin1,
          matched_admin2    = cand$admin2,
          matched_locality  = cand$locality,
          location_type     = cand$location_type,
          matched_types     = cand$types,
          partial_match     = cand$partial_match,
          place_id          = cand$place_id,
          n_results         = response$n_results,
          quality_flags     = a$flags,
          name_similarity   = a$similarity
        )
      }
    }

    if (!is.null(resolved)) break
  }

  if (is.null(resolved)) {
    resolved <- tibble(
      site_id = site_id, latitude = NA_real_, longitude = NA_real_,
      geocode_status = "failed", confidence = "failed",
      resolved_at_rung = NA_integer_, rung_label = NA_character_,
      query_address = NA_character_, query_components = NA_character_,
      matched_address = NA_character_, matched_admin1 = NA_character_,
      matched_admin2 = NA_character_, matched_locality = NA_character_,
      location_type = NA_character_, matched_types = NA_character_,
      partial_match = NA, place_id = NA_character_,
      n_results = 0L, quality_flags = NA_character_, name_similarity = NA_real_
    )
  }

  list(result = resolved, audit = bind_rows(audit))
}

# ---------------------------------------------------------------------------
# Manual overrides
# ---------------------------------------------------------------------------

#' Apply human-curated coordinates, which take precedence over any API result.
#'
#' `id_col` names the key column in both `results` and the override file, so
#' the DPS overrides can be keyed on `dps_id`.
apply_manual_overrides <- function(results, path = paths$overrides,
                                   id_col = "site_id") {
  if (!file.exists(path)) return(results)

  overrides <- read.csv(path, stringsAsFactors = FALSE)
  if (!"note" %in% names(overrides)) overrides$note <- NA_character_

  overrides <- overrides |>
    mutate(
      latitude  = suppressWarnings(as.numeric(latitude)),
      longitude = suppressWarnings(as.numeric(longitude)),
      note      = as.character(note)
    ) |>
    filter(!is.na(latitude), !is.na(longitude))

  if (nrow(overrides) == 0) return(results)

  results |>
    left_join(
      overrides |> select(all_of(id_col), ov_lat = latitude, ov_lon = longitude,
                          ov_note = note),
      by = id_col
    ) |>
    mutate(
      overridden      = !is.na(ov_lat),
      latitude        = if_else(overridden, ov_lat, latitude),
      longitude       = if_else(overridden, ov_lon, longitude),
      geocode_status  = if_else(overridden, "manual", geocode_status),
      confidence      = if_else(overridden, "manual", confidence),
      quality_flags   = if_else(overridden, ov_note, quality_flags)
    ) |>
    select(-ov_lat, -ov_lon, -ov_note, -overridden)
}
