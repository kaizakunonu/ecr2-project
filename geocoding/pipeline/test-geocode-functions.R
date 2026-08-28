# Tests for the DRC geocoding pipeline.
#
# Run from this directory:   Rscript test-geocode-functions.R
#
# No API key and no network required -- every Google response used here is a
# verbatim fixture recorded from the live API, so the gate can be exercised
# against what the API actually returns rather than what we assume it returns.

suppressMessages({
  source("config.R")
  source("geocode-functions.R")
})

pass <- 0; fail <- 0
ok <- function(label, cond) {
  if (isTRUE(cond)) { pass <<- pass + 1; cat("  PASS  ", label, "\n") }
  else              { fail <<- fail + 1; cat("  FAIL  ", label, "\n") }
}
section <- function(x) cat("\n== ", x, " ==\n", sep = "")

#' Build a candidate row exactly as parse_google_result() would.
candidate <- function(formatted_address, location_type, types, partial_match,
                      admin1, locality = NA_character_, lat = -2, lon = 25) {
  tibble(
    lat = lat, lon = lon, formatted_address = formatted_address,
    location_type = location_type, types = types,
    partial_match = partial_match, place_id = "ChIJfixture",
    admin1 = admin1, admin2 = NA_character_, locality = locality
  )
}

# ---------------------------------------------------------------------------
section("Helpers")
ok("normalise_name folds accents",        normalise_name("Kasaï-Central") == "kasai central")
ok("normalise_name handles Maï-Ndombe",   normalise_name("Maï-Ndombe") == "mai ndombe")
ok("fix_site_name corrects Mwene-ditu",   fix_site_name("Mwene-ditu") == "Mwene-Ditu")
ok("similarity: exact = 1",               name_similarity("Rutshuru", "Rutshuru") == 1)
ok("similarity: substring = 1",           name_similarity("Bolenge", "Bolenge, Republique democratique du Congo") == 1)
ok("similarity: NA scores 0",             name_similarity("Vanga", NA) == 0)

# ---------------------------------------------------------------------------
section("Province validation")
sites <- read.csv(paths$input, stringsAsFactors = FALSE)

ok("input has 26 rows",                   nrow(sites) == 26)
ok("input has 26 distinct provinces",     length(unique(sites$province)) == 26)
ok("every input province is recognised",  !is.null(validate_provinces(sites)))
ok("canonical list has 26 entries",       length(drc_provinces) == 26)

bad <- data.frame(province = c("Bandundu", "Katanga"), sentinel_site = c("a", "b"))
ok("pre-2015 names are rejected",
   inherits(try(validate_provinces(bad), silent = TRUE), "try-error"))
ok("rejection names the offenders",
   grepl("Bandundu", attr(try(validate_provinces(bad), silent = TRUE), "condition")$message))

# ---------------------------------------------------------------------------
section("Site identifiers")
with_ids <- ensure_site_id(sites)
ok("site_id is derived",                  all(!is.na(with_ids$site_id)))
ok("site_ids are unique",                 length(unique(with_ids$site_id)) == 26)
ok("site_id is a readable slug",          "DRC-VANGA" %in% with_ids$site_id)
ok("site_id keeps hyphens",               "DRC-MWENE-DITU" %in% with_ids$site_id)

preexisting <- data.frame(site_id = "KEEP-ME", province = "Kwilu", sentinel_site = "Vanga")
ok("an existing site_id is left alone",   ensure_site_id(preexisting)$site_id == "KEEP-ME")

dupes <- data.frame(province = c("Kwilu", "Lomami"), sentinel_site = c("Vanga", "Vanga"))
ok("duplicate site names are refused",
   inherits(try(ensure_site_id(dupes), silent = TRUE), "try-error"))

# ---------------------------------------------------------------------------
section("Query ladder")
v <- build_query_variants("Vanga", "Kwilu")
ok("ladder is exactly 4 rungs",           nrow(v) == 4)
ok("rungs are ordered 1..4",              identical(v$rung, c(1L, 2L, 3L, 4L)))
ok("rung 1 uses health-zone phrasing",    v$address[1] == "Zone de Sante de Vanga")
ok("rungs 1-2 pin the province",          all(grepl("administrative_area:Kwilu", v$components[1:2])))
ok("rungs 3-4 do not pin a province",     !any(grepl("administrative_area", v$components[3:4])))
ok("every rung restricts country:CD",     all(grepl("country:CD", v$components)))
ok("rung 3 is the legacy free-text form",
   v$address[3] == "Vanga, Kwilu, Republique Democratique du Congo")
ok("rung 4 is the bare site name",        v$address[4] == "Vanga")
ok("site-name fix flows into queries",
   all(grepl("Mwene-Ditu", build_query_variants("Mwene-ditu", "Lomami")$address)))
ok("accented provinces pass through",
   grepl("administrative_area:Kasaï", build_query_variants("Mikalayi", "Kasaï")$components[1]))

# ---------------------------------------------------------------------------
section("Quality gate: regressions from real API responses")

# Bolenge, rung 1. partial_match is TRUE only because the result does not
# contain the literal "Zone de Sante de " prefix. This must still reach `high`.
bolenge <- candidate("Bolenge, République démocratique du Congo", "APPROXIMATE",
                     "political|sublocality|sublocality_level_1", TRUE, "Équateur")
a_bol <- assess_candidate(bolenge, "Bolenge", "Equateur", n_results = 1L)
ok("Bolenge is accepted",                 a_bol$accepted)
ok("Bolenge scores similarity 1.0",       a_bol$similarity == 1)
ok("partial_match alone raises no flag",  a_bol$n_flags == 0)
ok("Bolenge reaches HIGH confidence",     confidence_tier(a_bol, 1) == "high")

# Rutshuru, rung 1 -- a clean locality match.
rutshuru <- candidate("Rutshuru, République démocratique du Congo", "APPROXIMATE",
                      "locality|political", TRUE, "Nord-Kivu", "Rutshuru")
ok("Rutshuru reaches HIGH confidence",
   confidence_tier(assess_candidate(rutshuru, "Rutshuru", "Nord-Kivu", 1L), 1) == "high")

# Mikalayi, rung 1: pinned to Kasai, Google returned a Kinshasa business ~700km
# away. The old gate accepted this. It must now be rejected on the province.
mikalayi_poi <- candidate(
  "00243 Avenue TP numéro 3C Quartier Funa, Industriel, 1ère Rue, Kinshasa, République démocratique du Congo",
  "GEOMETRIC_CENTER", "establishment|point_of_interest", TRUE, "Kinshasa", "Kinshasa",
  lat = -4.3412376, lon = 15.3299341)
a_mik <- assess_candidate(mikalayi_poi, "Mikalayi", "Kasaï-Central", n_results = 2L)
ok("Mikalayi's Kinshasa POI is REJECTED", !a_mik$accepted)
ok("rejection names the wrong province",  grepl("Kinshasa", a_mik$reject_reason))
ok("rejection cites the expected one",    grepl("Kasaï-Central", a_mik$reject_reason))
ok("rejected candidate is tier failed",   confidence_tier(a_mik, 1) == "failed")

# Kingasani, rung 1: right province, but a street rather than the health zone.
kingasani <- candidate("HCV5+QMQ, Rue Ma Soeur, Kinshasa, République démocratique du Congo",
                       "ROOFTOP", "establishment|point_of_interest", FALSE,
                       "Kinshasa", "Kinshasa", lat = -4.4055287, lon = 15.4092263)
a_king <- assess_candidate(kingasani, "Kingasani", "Kinshasa", n_results = 1L)
ok("Kingasani's street match is REJECTED", !a_king$accepted)
ok("rejection cites the unrelated name",   grepl("unrelated", a_king$reject_reason))
ok("its similarity sits below the floor",  a_king$similarity < gate$similarity_floor)

# The province centroids that the original gate already handled correctly.
for (p in c("Kasaï-Central", "Kasaï")) {
  cen <- candidate(paste0(p, ", République démocratique du Congo"), "APPROXIMATE",
                   "administrative_area_level_1|political", TRUE, p)
  a <- assess_candidate(cen, "Mikalayi", "Kasaï-Central", 1L)
  ok(paste0("province centroid '", p, "' is REJECTED"), !a$accepted)
  ok(paste0("'", p, "' cited as an admin centroid"),
     grepl("administrative-area centroid", a$reject_reason))
}

# ---------------------------------------------------------------------------
section("Quality gate: other rules")
outside <- candidate("Kampala, Uganda", "APPROXIMATE", "locality|political",
                     FALSE, "Kinshasa", "Kampala", lat = 0.3476, lon = 32.5825)
ok("out-of-bbox is REJECTED",
   !assess_candidate(outside, "Kampala", "Kinshasa", 1L)$accepted)

unverifiable <- candidate("Kalima, République démocratique du Congo", "APPROXIMATE",
                          "locality|political", FALSE, NA_character_, "Kalima")
a_unv <- assess_candidate(unverifiable, "Kalima", "Maniema", 1L)
ok("missing admin1 does not reject",      a_unv$accepted)
ok("missing admin1 is flagged",           grepl("could not be verified", a_unv$flags))

multi <- assess_candidate(rutshuru, "Rutshuru", "Nord-Kivu", n_results = 3L)
ok("multiple results are flagged",        grepl("3 results returned", multi$flags))
ok("multiple results drop it to medium",  confidence_tier(multi, 1) == "medium")

# ---------------------------------------------------------------------------
section("Confidence tiers")
clean <- list(accepted = TRUE, n_flags = 0L)
ok("rung 1, 0 flags -> high",             confidence_tier(clean, 1) == "high")
ok("rung 3, 0 flags -> medium",           confidence_tier(clean, 3) == "medium")
ok("rung 4, 0 flags -> low",              confidence_tier(clean, 4) == "low")
ok("rung 1, 2 flags -> low",              confidence_tier(list(accepted = TRUE, n_flags = 2L), 1) == "low")

# ---------------------------------------------------------------------------
section("Response cache")
tmp <- tempfile(fileext = ".rds")
cache_load(tmp)
ok("empty cache starts empty",            is.null(cache_get("Vanga", "country:CD")))
cache_put("Vanga", "country:CD", list(status = "OK", n_results = 1L))
ok("cache_get returns what was stored",   cache_get("Vanga", "country:CD")$status == "OK")
ok("the key includes components",         is.null(cache_get("Vanga", "country:CD|administrative_area:Kwilu")))
cache_save(); cache_load(tmp)
ok("cache survives save and reload",      cache_get("Vanga", "country:CD")$n_results == 1L)
unlink(tmp)

# ---------------------------------------------------------------------------
section("Manual overrides")
base <- tibble(site_id = c("DRC-VANGA", "DRC-MIKALAYI"),
               latitude = c(-4.4, NA_real_), longitude = c(18.4, NA_real_),
               geocode_status = c("google", "failed"),
               confidence = c("high", "failed"),
               quality_flags = c(NA_character_, NA_character_))

empty <- tempfile(fileext = ".csv")
writeLines("site_id,latitude,longitude,note", empty)
ok("an empty override file is a no-op",   identical(apply_manual_overrides(base, empty), base))
ok("a missing override file is a no-op",
   identical(apply_manual_overrides(base, tempfile(fileext = ".csv")), base))

filled <- tempfile(fileext = ".csv")
writeLines(c("site_id,latitude,longitude,note",
             "DRC-MIKALAYI,-6.05,22.32,pinned from field GPS"), filled)
res <- apply_manual_overrides(base, filled)
ok("override fills the failed site",      res$latitude[2] == -6.05 && res$longitude[2] == 22.32)
ok("override stamps status manual",       res$geocode_status[2] == "manual")
ok("override carries the note",           res$quality_flags[2] == "pinned from field GPS")
ok("override leaves other rows alone",    res$latitude[1] == -4.4)
ok("override preserves the column set",   setequal(names(res), names(base)))
unlink(c(empty, filled))

# ---------------------------------------------------------------------------
cat("\n=====================================\n")
cat(sprintf("PASSED: %d   FAILED: %d\n", pass, fail))
cat("=====================================\n")
if (fail > 0) quit(status = 1)
