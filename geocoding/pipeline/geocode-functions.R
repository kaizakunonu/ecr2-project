# Geocoding functions for the DRC sentinel site pipeline.
#
# Providers: Google, GRID3, Nominatim, GeoNames and Photon. Each is an adapter
# in providers.R that returns its candidates in one schema -- the columns of
# parse_google_result() plus `provider`, `kind`, `name` and `name_alt`. This
# file holds everything that does not depend on the provider: the query
# ladder, the quality gate, the ladder walk, the provider chains and the
# cross-check between providers.
#
# Source config.R first and providers.R after this file.

library(dplyr)
library(purrr)
library(stringr)
library(tibble)
library(httr)
library(jsonlite)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

`%||%` <- function(x, y) if (is.null(x)) y else x
`%|na|%` <- function(x, y) if (length(x) == 0 || is.na(x[[1]])) y else x

#' A JSON field as a string, with absent and empty values as NA.
nz <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x[[1]]) || !nzchar(as.character(x[[1]]))) {
    return(NA_character_)
  }
  as.character(x[[1]])
}

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

#' Similarity between a site name and each of a place's own names, in [0, 1].
#'
#' name_similarity() scores a name found anywhere inside the other as 1, which
#' a Google formatted_address needs. Where a provider returns the place's own
#' name, that shortcut is wrong: Nominatim's answer for Nyanga in Kasaï was the
#' village of Bakwa-Nyanga, about 150 km from Nyanga, and it scored 1. Whole
#' names are compared instead. Vectorised over `b`.
whole_name_similarity <- function(a, b) {
  a <- normalise_name(a)
  b <- normalise_name(b)
  if (length(a) != 1 || is.na(a) || !nzchar(a)) return(rep(0, length(b)))
  out <- 1 - as.numeric(utils::adist(a, b)) / pmax(nchar(a), nchar(b))
  out[is.na(b) | !nzchar(b)] <- 0
  out
}

ROMAN_NUMERALS <- c(i = 1L, ii = 2L, iii = 3L, iv = 4L, v = 5L,
                    vi = 6L, vii = 7L, viii = 8L, ix = 9L, x = 10L)

#' The numbers in a name, roman numerals included: "Maluku I" -> 1.
number_tokens <- function(x) {
  tokens <- str_split(normalise_name(x), " ")[[1]]
  tokens <- tokens[!is.na(tokens)]
  c(as.integer(tokens[str_detect(tokens, "^[0-9]+$")]),
    unname(ROMAN_NUMERALS[tokens[tokens %in% names(ROMAN_NUMERALS)]]))
}

#' Do two names carry different numbers? "Maluku 1" and "Maluku 2" do.
#'
#' Edit distance cannot see it: the two differ by one character and score
#' 0.875, yet GRID3 puts their central offices 70 km apart.
numbers_conflict <- function(a, b) {
  na <- number_tokens(a)
  nb <- number_tokens(b)
  length(na) > 0 && length(nb) > 0 && !setequal(na, nb)
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

#' Read every sentinel site input into one table.
#'
#' Each network's new sites live in their own file; ensure_site_id() then
#' refuses a name that appears in more than one.
read_sites <- function(files = paths$input) {
  files |>
    map(\(f) read.csv(f, stringsAsFactors = FALSE)) |>
    list_rbind()
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

#' Great-circle distance in kilometres.
#'
#' A straight line, not a travel distance: it is here to catch blunders (a pair
#' hundreds of km apart within one province), co-located pairs, and providers
#' that disagree about where a place is.
haversine_km <- function(lat1, lon1, lat2, lon2, radius = 6371) {
  rad  <- pi / 180
  dlat <- (lat2 - lat1) * rad
  dlon <- (lon2 - lon1) * rad
  a <- sin(dlat / 2)^2 + cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2)^2
  2 * radius * asin(pmin(1, sqrt(a)))
}

# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------

#' The providers switched on in config.R, in config order.
enabled_providers <- function(config = providers) {
  names(config)[map_lgl(config, \(p) isTRUE(p$enabled))]
}

#' The data source behind each provider ("osm" for Nominatim and Photon).
#' NA for anything that is not a provider, such as "manual".
provider_family <- function(provider, config = providers) {
  map_chr(provider, \(p) config[[p]]$family %||% NA_character_)
}

#' The credential a provider needs for an uncached request.
#'
#' Called only when a request has to go out, so a fully cached run needs no
#' credentials at all.
provider_credential <- function(provider, config = providers) {
  env <- config[[provider]]$env
  if (is.null(env) || is.na(env)) return(NA_character_)
  value <- Sys.getenv(env)
  if (!nzchar(value)) {
    stop(env, " is not set, and ", provider, " has an uncached request to make. ",
         "Export it, or set providers$", provider, "$enabled <- FALSE in config.R.",
         call. = FALSE)
  }
  value
}

#' Which credentials the enabled providers use, and whether each is set.
credential_status <- function(use = enabled_providers(), config = providers) {
  env <- map_chr(use, \(p) config[[p]]$env %||% NA_character_)
  tibble(
    provider   = use,
    credential = if_else(is.na(env), "none needed", env),
    set        = map_lgl(env, \(e) is.na(e) || nzchar(Sys.getenv(e)))
  )
}

# ---------------------------------------------------------------------------
# Response cache
# ---------------------------------------------------------------------------
#
# One store per provider, saved as {provider}_geocode_cache.rds in
# paths$cache_dir, so re-rendering costs zero requests and yields identical
# coordinates.
#
# Every entry carries `cached_at`, and an entry older than the provider's
# `cache_days` is fetched again. Google Maps Platform terms allow latitude and
# longitude to be cached for 30 days (place IDs indefinitely). Nominatim's
# usage policy requires results to be cached; GRID3 and GeoNames data are
# CC BY 4.0.

.geocode_cache <- new.env(parent = emptyenv())

cache_key <- function(address, components) paste0(address, "|", components)

cache_path <- function(provider, dir = .geocode_cache$dir %||% paths$cache_dir) {
  file.path(dir, paste0(provider, "_geocode_cache.rds"))
}

#' Load every provider's cache from `dir` and reset the request counters.
#'
#' Entries written before caches carried a timestamp are stamped with the
#' file's modification time, the latest moment they can have been fetched.
cache_load <- function(dir = paths$cache_dir, provider_names = names(providers)) {
  .geocode_cache$dir       <- dir
  .geocode_cache$stores    <- list()
  .geocode_cache$calls     <- setNames(integer(length(provider_names)), provider_names)
  .geocode_cache$hits      <- setNames(integer(length(provider_names)), provider_names)
  .geocode_cache$last_call <- list()
  .geocode_cache$changed   <- character(0)

  for (p in provider_names) {
    path  <- cache_path(p, dir)
    store <- if (file.exists(path)) readRDS(path) else list()
    stamp <- if (file.exists(path)) file.mtime(path) else Sys.time()
    .geocode_cache$stores[[p]] <- map(store, function(entry) {
      if (is.null(entry$cached_at)) entry$cached_at <- stamp
      entry
    })
  }
  invisible(map_int(.geocode_cache$stores, length))
}

cache_ready <- function() {
  if (is.null(.geocode_cache$stores)) cache_load()
  invisible(TRUE)
}

#' A cached entry, or NULL when there is none or it has expired.
cache_get <- function(key, provider = "google", config = providers) {
  cache_ready()
  entry <- .geocode_cache$stores[[provider]][[key]]
  if (is.null(entry)) return(NULL)
  age <- as.numeric(difftime(Sys.time(), entry$cached_at, units = "days"))
  if (age > (config[[provider]]$cache_days %||% Inf)) return(NULL)
  entry
}

cache_put <- function(key, value, provider = "google") {
  cache_ready()
  value$cached_at <- Sys.time()
  if (is.null(.geocode_cache$stores[[provider]])) .geocode_cache$stores[[provider]] <- list()
  .geocode_cache$stores[[provider]][[key]] <- value
  .geocode_cache$changed <- union(.geocode_cache$changed, provider)
  invisible(value)
}

#' Write the stores that changed since they were loaded or last saved.
#'
#' Cheap enough to call after every point, so an interrupted run keeps what it
#' has already fetched.
cache_save <- function(dir = .geocode_cache$dir) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  for (p in .geocode_cache$changed) {
    saveRDS(.geocode_cache$stores[[p]], cache_path(p, dir))
  }
  .geocode_cache$changed <- character(0)
  invisible(dir)
}

#' Requests made and answers served from the cache, per provider.
cache_stats <- function() {
  cache_ready()
  p <- union(names(.geocode_cache$calls), names(.geocode_cache$hits))
  count <- \(field) map_int(p, \(x) .geocode_cache[[field]][x] %|na|% 0L)
  tibble(provider = p, requests = count("calls"), cache_hits = count("hits"))
}

bump_counter <- function(field, provider) {
  counts <- .geocode_cache[[field]]
  counts[provider] <- (if (provider %in% names(counts)) counts[[provider]] else 0L) + 1L
  .geocode_cache[[field]] <- counts
}

#' Serve `key` from the provider's cache, or run `fetch()` and cache its value.
cached_fetch <- function(provider, key, fetch) {
  hit <- cache_get(key, provider)
  if (!is.null(hit)) {
    bump_counter("hits", provider)
    return(hit)
  }
  cache_put(key, fetch(), provider)
}

#' Space out a provider's network requests and count them.
#'
#' Only real requests wait, so a cached re-render of a 1 request/second
#' provider is not slowed down.
throttle <- function(provider, config = providers) {
  cache_ready()
  delay <- config[[provider]]$rate_delay %||% 0
  last  <- .geocode_cache$last_call[[provider]]
  if (!is.null(last)) {
    wait <- delay - as.numeric(difftime(Sys.time(), last, units = "secs"))
    if (wait > 0) Sys.sleep(wait)
  }
  .geocode_cache$last_call[[provider]] <- Sys.time()
  bump_counter("calls", provider)
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# Query construction
# ---------------------------------------------------------------------------

#' Build the ordered ladder of query variants for one site.
#'
#' Rungs 1-2 pin the query to the site's province. For Google that is the
#' `administrative_area` component filter, which is advisory rather than
#' binding -- a live run returned a Kinshasa business for a query pinned to
#' Kasai -- so the province is also verified against the response in
#' assess_candidate(). Rungs 3-4 are free-text fallbacks for sites the
#' province-constrained queries miss, still restricted to the country.
#'
#' The rung wording comes from `ladder` (see `ladders` in config.R), so another
#' point set -- the DPS headquarters -- reuses the ladder walk and the gate with
#' its own queries. `components` is Google's form of the constraint; the other
#' providers read `pinned`, `target`, `name` and `province`.
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
    components = if_else(ladder$pinned, pinned, cc),
    pinned     = ladder$pinned,
    target     = ladder$target %||% rep("settlement", nrow(ladder)),
    name       = site,
    province   = province
  )
}

# ---------------------------------------------------------------------------
# Candidate assessment
# ---------------------------------------------------------------------------

ADMIN_LEVEL_TYPES <- c("administrative_area_level_1",
                       "administrative_area_level_2",
                       "country")

#' What kind of place a Google result is: "area", "linear", or point_basis().
#'
#' An APPROXIMATE result typed as an administrative area is the centroid of
#' that area, which is what the gate has always rejected.
google_kind <- function(location_type, types) {
  map2_chr(location_type, types, function(lt, ty) {
    t <- str_split(ty, fixed("|"))[[1]]
    if (identical(lt, "APPROXIMATE") && any(t %in% ADMIN_LEVEL_TYPES)) return("area")
    if ("route" %in% t) return("linear")
    point_basis(ty)
  })
}

#' Judge a single candidate.
#'
#' Hard rejections are failures of kind -- the candidate is discarded and the
#' ladder keeps walking. Soft flags are doubts that lower confidence but keep
#' the candidate.
#'
#' Two of the rejections come from a live run that reported 11/11 success
#' while quietly accepting a Kinshasa business as the location of Mikalayi, a
#' health zone some 700 km away in Kasai. Google's administrative_area filter
#' did not prevent it, so the province is verified against the response, and a
#' returned name bearing no resemblance to the site is refused outright.
#'
#' The others come from the open providers' live responses: OSM's health-zone
#' polygons, rivers and streets named after towns, and GRID3's "Maluku 2" for
#' Maluku 1.
#'
#' Note what is deliberately absent: no blacklist on `establishment` or
#' `point_of_interest` types. Both bad results carried them, but so would a
#' legitimate match on "Centre de Sante de ...". The province and similarity
#' checks catch the real failures without that false positive.
#'
#' `ambiguity` words the flag raised when `n_results` > 1: Google's raw count
#' of results, or, for a provider that always returns a ranked list, the
#' number of distinct places that pass the hard gate.
#'
#' `office` is the query of a rung that looks for an office (the DPS ladder's
#' rung 1). A named building returned for it must be named like the office.
assess_candidate <- function(candidate, site, expected_provinces,
                             n_results = 1L, profile = country_profile,
                             thresholds = gate, ambiguity = "results returned",
                             office = NA_character_) {

  kind   <- candidate[["kind"]] %||% google_kind(candidate$location_type, candidate$types)
  reject <- character(0)
  flags  <- character(0)

  # An area result is the centroid of the enclosing area rather than the site
  # itself: a province from Google, a health zone's polygon from OSM.
  if (identical(kind, "area")) {
    reject <- c(reject, "administrative-area centroid, not a settlement")
  }

  # Streets and rivers are often named after towns: OSM has an Avenue
  # Mwene-Ditu in Kinshasa and a Nyemba river in Tanganyika.
  if (identical(kind, "linear")) {
    reject <- c(reject, "a street, river or railway, not a settlement")
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

  # A provider that names the place itself is matched on whole names (its own
  # name, alternatives, and the settlement containing it); Google, which often
  # names nothing but the address, on the address as before.
  own_names <- c(candidate[["name"]] %||% NA_character_,
                 str_split(candidate[["name_alt"]] %||% NA_character_, fixed("|"))[[1]])
  own_names <- own_names[!is.na(own_names) & nzchar(own_names)]

  if (length(own_names) > 0) {
    compared   <- c(own_names, candidate$locality)
    sims       <- whole_name_similarity(site, compared)
    similarity <- max(sims)
    matched    <- compared[which.max(sims)]
  } else {
    similarity <- max(
      name_similarity(site, candidate$locality),
      name_similarity(site, candidate$formatted_address)
    )
    matched <- candidate$locality
  }

  if (similarity < thresholds$similarity_floor) {
    reject <- c(reject, sprintf("returned name is unrelated to the site (similarity %.2f)",
                                similarity))
  }

  if (numbers_conflict(site, matched)) {
    reject <- c(reject, paste0("numbered name '", matched, "' is not '", site, "'"))
  }

  # Matching the town alone accepts any building in it. Google names none, so
  # its buildings go to review; the open providers do, so an office query is
  # held to the office: Photon's answer for DPS Haut-Katanga was a church in
  # Lubumbashi.
  if (!is.na(office) && length(own_names) > 0 && identical(kind, "establishment") &&
      max(whole_name_similarity(office, own_names)) < thresholds$similarity_floor) {
    reject <- c(reject, paste0("a building in the town, but not the office ('",
                               own_names[1], "')"))
  }

  # partial_match fires on every rung-1 query simply because the result does
  # not contain the literal "Zone de Sante de " prefix. It is only meaningful
  # when the returned name is also a weak match.
  if (isTRUE(candidate$partial_match) && similarity < thresholds$similarity_clean) {
    flags <- c(flags, "partial name match")
  }
  if (n_results > 1)  flags <- c(flags, paste0(n_results, " ", ambiguity))
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
    similarity     = similarity,
    kind           = kind,
    matched_name   = if (length(matched) == 1) matched else NA_character_
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

#' What kind of place a Google result is: "establishment", "settlement" or "other".
#'
#' Not part of the gate. A settlement is a town or neighbourhood centroid; an
#' establishment is a building. The Geocoding API returns no establishment
#' name, so an establishment in the right town passes the gate whichever
#' building it is. The DPS workflow uses this, through `matched_kind`, to send
#' such hits to review.
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

#' How many distinct places a set of candidates covers.
#'
#' GRID3 lists the Mwene-Ditu central office twice, 30 m apart; that is one
#' place, not an ambiguity.
count_distinct_places <- function(cands, within_km = crosscheck$agree_km) {
  if (nrow(cands) == 0) return(0L)
  lat <- cands$lat[1]
  lon <- cands$lon[1]
  for (j in seq_len(nrow(cands))[-1]) {
    if (all(haversine_km(cands$lat[j], cands$lon[j], lat, lon) > within_km)) {
      lat <- c(lat, cands$lat[j])
      lon <- c(lon, cands$lon[j])
    }
  }
  length(lat)
}

# ---------------------------------------------------------------------------
# Per-site resolution
# ---------------------------------------------------------------------------

#' Walk the query ladder for one site with one provider, stopping at the first
#' accepted candidate.
#'
#' Returns a list of `result` (single row) and `audit` (every candidate seen at
#' every rung, accepted or not). `fetch` answers one query variant; it is the
#' provider's adapter unless a test replays recorded responses through it.
geocode_site <- function(site_id, site, province, profile = country_profile,
                         point_set = "sentinel_site", ladder = ladders[[point_set]],
                         provider = "google", fetch = provider_fetchers[[provider]]) {

  variants <- build_query_variants(site, province, profile, ladder)
  skip     <- providers[[provider]]$skip_rungs[[point_set]] %||% integer(0)
  variants <- variants[!variants$rung %in% skip, ]
  expected <- province
  audit    <- list()
  resolved <- NULL

  for (i in seq_len(nrow(variants))) {
    v <- variants[i, ]
    response <- fetch(v, profile)
    cands    <- response$candidates

    query <- tibble(
      site_id = site_id, name = site, provider = provider,
      rung = v$rung, rung_label = v$rung_label,
      address = v$address, components = v$components,
      api_status = response$status, n_results = response$n_results
    )

    if (nrow(cands) == 0) {
      audit[[length(audit) + 1]] <- query |> mutate(
        lat = NA_real_, lon = NA_real_, formatted_address = NA_character_,
        location_type = NA_character_, types = NA_character_,
        partial_match = NA, place_id = NA_character_,
        admin1 = NA_character_, admin2 = NA_character_, locality = NA_character_,
        place_name = NA_character_, place_name_alt = NA_character_, kind = NA_character_,
        accepted = FALSE, reject_reason = "no results", flags = NA_character_,
        similarity = NA_real_
      )
      next
    }

    office <- if (identical(v$target, "office")) v$address else NA_character_
    assess_all <- function(n, ambiguity = "results returned") {
      map(seq_len(nrow(cands)), \(j) assess_candidate(cands[j, ], site, expected,
                                                      n, profile, ambiguity = ambiguity,
                                                      office = office))
    }
    assessments <- assess_all(response$n_results)

    # The open providers always return a ranked list, so their result count
    # says nothing about ambiguity; the number of distinct places that pass
    # the hard gate does.
    if (provider != "google") {
      passing <- cands[map_lgl(assessments, "accepted"), ]
      assessments <- assess_all(count_distinct_places(passing), "distinct matching places")
    }

    audit[[length(audit) + 1]] <- bind_cols(
      query[rep(1, nrow(cands)), ],
      cands |>
        select(lat, lon, formatted_address, location_type, types, partial_match,
               place_id, admin1, admin2, locality,
               place_name = name, place_name_alt = name_alt, kind),
      tibble(accepted      = map_lgl(assessments, "accepted"),
             reject_reason = map_chr(assessments, "reject_reason"),
             flags         = map_chr(assessments, "flags"),
             similarity    = map_dbl(assessments, "similarity"))
    )

    j <- detect_index(assessments, "accepted")
    if (j > 0) {
      cand <- cands[j, ]
      a    <- assessments[[j]]
      resolved <- tibble(
        site_id           = site_id,
        provider          = provider,
        latitude          = cand$lat,
        longitude         = cand$lon,
        geocode_status    = provider,
        confidence        = confidence_tier(a, v$rung),
        resolved_at_rung  = v$rung,
        rung_label        = v$rung_label,
        query_address     = v$address,
        query_components  = v$components,
        matched_address   = cand$formatted_address,
        matched_name      = a$matched_name,
        matched_admin1    = cand$admin1,
        matched_admin2    = cand$admin2,
        matched_locality  = cand$locality,
        matched_kind      = a$kind,
        location_type     = cand$location_type,
        matched_types     = cand$types,
        partial_match     = cand$partial_match,
        place_id          = cand$place_id,
        n_results         = response$n_results,
        quality_flags     = a$flags,
        name_similarity   = a$similarity
      )
      break
    }
  }

  if (is.null(resolved)) {
    resolved <- tibble(
      site_id = site_id, provider = provider, latitude = NA_real_, longitude = NA_real_,
      geocode_status = "failed", confidence = "failed",
      resolved_at_rung = NA_integer_, rung_label = NA_character_,
      query_address = NA_character_, query_components = NA_character_,
      matched_address = NA_character_, matched_name = NA_character_,
      matched_admin1 = NA_character_, matched_admin2 = NA_character_,
      matched_locality = NA_character_, matched_kind = NA_character_,
      location_type = NA_character_, matched_types = NA_character_,
      partial_match = NA, place_id = NA_character_,
      n_results = 0L, quality_flags = NA_character_, name_similarity = NA_real_
    )
  }

  list(result = resolved, audit = bind_rows(audit))
}

#' Geocode one point with every enabled provider.
#'
#' Each provider walks its own ladder until it accepts a candidate, so every
#' point gets an independent answer from every source -- what the chains
#' choose from and the cross-check compares. Returns `by_provider` (one row
#' per provider) and `audit`.
geocode_point_all <- function(site_id, site, province, profile = country_profile,
                              point_set = "sentinel_site", ladder = ladders[[point_set]],
                              use = enabled_providers(), fetchers = provider_fetchers) {
  outs <- map(use, \(p) geocode_site(site_id, site, province, profile, point_set,
                                     ladder, provider = p, fetch = fetchers[[p]]))
  list(by_provider = map(outs, "result") |> list_rbind(),
       audit       = map(outs, "audit") |> list_rbind())
}

# ---------------------------------------------------------------------------
# Provider chains and the cross-check
# ---------------------------------------------------------------------------

#' Keep, for each point, the answer of the first provider in `chain` that
#' resolved it.
#'
#' A point no provider in the chain resolved keeps a failed row with no
#' provider. Points stay in the order of `by_provider`.
select_chain <- function(by_provider, chain, id_col = "site_id") {
  chain <- chain[chain %in% by_provider$provider]
  by_provider |>
    filter(provider %in% chain) |>
    mutate(.order = match(.data[[id_col]], unique(.data[[id_col]])),
           .rank  = match(provider, chain)) |>
    arrange(.order, geocode_status == "failed", .rank) |>
    filter(!duplicated(.data[[id_col]])) |>
    mutate(provider = if_else(geocode_status == "failed", NA_character_, provider)) |>
    select(-.order, -.rank)
}

#' Compare each selected point with every other provider's answer for it.
#'
#' Adds `crosscheck`:
#'   - "agree": another source family put the point within `agree_km`, and no
#'     provider put it further away.
#'   - "disagree": some provider put it more than `agree_km` away.
#'   - "single-source": no other family found it.
#' Plus `n_sources_agree` (other families within `agree_km`),
#' `max_disagreement_km` and `crosscheck_note`, which lists every distance.
#'
#' Families, not providers, are counted, because Nominatim and Photon serve the
#' same OpenStreetMap data. The cross-check never rejects a point and does not
#' touch `confidence`, which stays the gate's verdict; the workflows send
#' anything short of "agree" to review. Run it after apply_manual_overrides(),
#' so a pinned point is checked against every provider.
crosscheck_points <- function(selected, by_provider, agree_km = crosscheck$agree_km,
                              id_col = "site_id") {
  accepted <- by_provider |> filter(geocode_status != "failed")

  checks <- map(seq_len(nrow(selected)), function(i) {
    s <- selected[i, ]
    if (is.na(s$latitude)) {
      return(tibble(crosscheck = NA_character_, n_sources_agree = NA_integer_,
                    max_disagreement_km = NA_real_, crosscheck_note = NA_character_))
    }
    others <- accepted[accepted[[id_col]] == s[[id_col]] &
                         accepted$provider != s$geocode_status, ]
    if (nrow(others) == 0) {
      return(tibble(crosscheck = "single-source", n_sources_agree = 0L,
                    max_disagreement_km = NA_real_,
                    crosscheck_note = "no other provider resolved it"))
    }

    d     <- haversine_km(s$latitude, s$longitude, others$latitude, others$longitude)
    fam   <- provider_family(others$provider)
    own   <- provider_family(s$geocode_status)
    agree <- unique(fam[d <= agree_km & (is.na(own) | fam != own)])

    tibble(
      crosscheck = if (any(d > agree_km)) "disagree"
                   else if (length(agree) > 0) "agree"
                   else "single-source",
      n_sources_agree     = length(agree),
      max_disagreement_km = max(d),
      crosscheck_note     = paste(sprintf("%s %.1f km", others$provider, d), collapse = "; ")
    )
  })

  bind_cols(selected, list_rbind(checks))
}

#' Points that need a person to look at them.
#'
#' Anything short of a clean high-confidence match, and any point the other
#' providers do not confirm -- unless it was pinned by hand and nothing
#' contradicts the pin.
needs_review <- function(confidence, crosscheck) {
  crosscheck <- coalesce(crosscheck, "none")
  (!confidence %in% c("high", "manual")) |
    crosscheck == "disagree" |
    (crosscheck == "single-source" & confidence != "manual")
}

# ---------------------------------------------------------------------------
# Manual overrides
# ---------------------------------------------------------------------------

#' Apply human-curated coordinates, which take precedence over any API result.
#'
#' `id_col` names the key column in both `results` and the override file, so
#' the DPS overrides can be keyed on `dps_id`. `provider` is left as the API
#' answer the override replaced.
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
