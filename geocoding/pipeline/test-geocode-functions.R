# Tests for the DRC geocoding pipeline.
#
# Run from this directory:   Rscript test-geocode-functions.R
#
# No API key and no network required -- every response used here was recorded
# from the live APIs, so the gate can be exercised against what the providers
# actually return rather than what we assume they return. Google responses are
# copied in as parsed rows (candidate() below); the open providers' raw
# response bodies are stored verbatim in fixtures/ and go through the real
# parsers.

suppressMessages({
  source("config.R")
  source("geocode-functions.R")
  source("providers.R")
  source("pairs-functions.R")
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

#' A recorded response body from fixtures/, as the adapters receive it.
fixture <- function(file) {
  jsonlite::read_json(file.path("fixtures", file), simplifyVector = FALSE)
}
nominatim_fixture <- function(file) map(fixture(file), parse_nominatim_result) |> list_rbind()
photon_fixture    <- function(file) map(fixture(file)$features, parse_photon_feature) |> list_rbind()
grid3_fixture     <- function(file) parse_arcgis_rows(map(fixture(file)$features, "attributes"))

#' Judge every candidate in a response; returns the list of assessments.
assess_each <- function(cands, site, province) {
  map(seq_len(nrow(cands)), \(j) assess_candidate(cands[j, ], site, province))
}

# ---------------------------------------------------------------------------
section("Helpers")
ok("normalise_name folds accents",        normalise_name("Kasaï-Central") == "kasai central")
ok("normalise_name handles Maï-Ndombe",   normalise_name("Maï-Ndombe") == "mai ndombe")
ok("fix_site_name corrects Mwene-ditu",   fix_site_name("Mwene-ditu") == "Mwene-Ditu")
ok("similarity: exact = 1",               name_similarity("Rutshuru", "Rutshuru") == 1)
ok("similarity: substring = 1",           name_similarity("Bolenge", "Bolenge, Republique democratique du Congo") == 1)
ok("similarity: NA scores 0",             name_similarity("Vanga", NA) == 0)

# Nominatim's answer for Nyanga, Kasaï was Bakwa-Nyanga, ~150 km from Nyanga.
ok("the substring rule scores Bakwa-Nyanga 1 for Nyanga",
   name_similarity("Nyanga", "Bakwa-Nyanga") == 1)
ok("...whole names put it below the floor",
   whole_name_similarity("Nyanga", "Bakwa-Nyanga") < gate$similarity_floor)
ok("whole names: GRID3's Mweneditu is clean",
   whole_name_similarity("Mwene-Ditu", "Mweneditu") >= gate$similarity_clean)
ok("whole names: vectorised, NA scores 0",
   identical(whole_name_similarity("Vanga", c("Vanga", NA)), c(1, 0)))
ok("number tokens read digits",           identical(number_tokens("Maluku 2"), 2L))
ok("...and roman numerals",               identical(number_tokens("Maluku I"), 1L))
ok("...and nothing else",                 length(number_tokens("Mwene-Ditu")) == 0)
ok("Maluku 1 and Maluku 2 conflict",      numbers_conflict("Maluku 1", "Maluku 2"))
ok("Maluku 1 and Maluku I do not",        !numbers_conflict("Maluku 1", "Maluku I"))
ok("an unnumbered name does not conflict", !numbers_conflict("Maluku 1", "Maluku"))

# ---------------------------------------------------------------------------
section("Province validation")
sites <- read.csv(paths$input[1], stringsAsFactors = FALSE)   # the 26-site input

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
section("The 2015 province split")
successors <- unlist(provinces_pre2015, use.names = FALSE)
ok("there are 11 pre-2015 provinces",     length(provinces_pre2015) == 11)
ok("the split covers all 26 provinces",
   setequal(normalise_name(successors), normalise_name(drc_provinces)))
ok("...each exactly once",                length(successors) == 26 && !anyDuplicated(successors))
ok("Kasaï Oriental became Lomami, among others",
   "Lomami" %in% successor_provinces("Kasaï Oriental"))
ok("Bas-Congo was only renamed",          identical(successor_provinces("Bas-Congo"), "Kongo-Central"))
ok("a current province maps to itself",   identical(successor_provinces("Lomami"), "Lomami"))
ok("an unknown name maps to NA",          is.na(successor_provinces("Atlantis")))

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

dps_in <- read.csv(paths$dps_input, stringsAsFactors = FALSE)
dps_ids <- ensure_site_id(dps_in, dps_profile)$dps_id
ok("DPS registry has 31 seats",           nrow(dps_in) == 31)
ok("it holds every current province's DPS",
   all(normalise_name(paste("DPS", drc_provinces)) %in% normalise_name(dps_in$dps)))
ok("DPS seats use current provinces",     !is.null(validate_provinces(dps_in)))
ok("every seat lies in what its DPS's province became",
   all(map2_lgl(dps_in$province, sub("^DPS ", "", dps_in$dps),
                \(p, n) normalise_name(p) %in% normalise_name(successor_provinces(n)))))
current_dps <- normalise_name(paste("DPS", drc_provinces))
ok("DPS registry lists the 5 pre-2015 seats first",
   !any(normalise_name(dps_in$dps[1:5]) %in% current_dps) &&
     all(normalise_name(dps_in$dps[6:31]) %in% current_dps))
ok("DPS Kasaï Oriental resolves to the DPS Kasaï-Oriental seat",
   make_id("DPS Kasaï Oriental") == make_id("DPS Kasaï-Oriental") &&
     make_id("DPS Kasaï Oriental") %in% dps_ids)
ok("dps_id is derived from the DPS name", "DRC-DPS-KASAI-CENTRAL" %in% dps_ids)
ok("dps_id folds accents",                "DRC-DPS-MAI-NDOMBE" %in% dps_ids)
ok("dps_ids never collide with site_ids",
   length(intersect(dps_ids, with_ids$site_id)) == 0)
ok("make_id agrees with ensure_site_id",  identical(make_id(sites$sentinel_site), with_ids$site_id))

sites_2021 <- read.csv(paths$input[2], stringsAsFactors = FALSE)
ok("2021 input has 25 rows",              nrow(sites_2021) == 25)
ok("...in 25 distinct provinces",         length(unique(normalise_name(sites_2021$province))) == 25)
ok("...all current province names",       !is.null(validate_provinces(sites_2021)))
ok("...none clashing with a 2014 site id",
   length(intersect(make_id(sites_2021$sentinel_site), with_ids$site_id)) == 0)

all_sites <- ensure_site_id(read_sites())
ok("read_sites joins every input",        nrow(all_sites) == 51)
ok("...into 51 unique site ids",          !anyDuplicated(all_sites$site_id))

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
ok("rung labels name the province",       v$rung_label[1] == "1: health zone + province (Kwilu)")
ok("rungs carry pinned for other providers", identical(v$pinned, c(TRUE, TRUE, FALSE, FALSE)))
ok("rung 1 looks for a health zone",      v$target[1] == "health_zone" && all(v$target[2:4] == "settlement"))
ok("rungs carry the fixed name and the province",
   all(build_query_variants("Mwene-ditu", "Lomami")$name == "Mwene-Ditu") &&
     all(v$province == "Kwilu"))

d <- build_query_variants("Kananga", "Kasaï-Central", ladder = ladders$dps)
ok("DPS ladder is 4 rungs",               nrow(d) == 4 && identical(d$rung, 1:4))
ok("DPS rung 1 asks for the office",      d$address[1] == "Division Provinciale de la Sante Kasaï-Central")
ok("DPS rung 2 falls back to the town",   d$address[2] == "Kananga")
ok("DPS rungs 1-2 pin the province",
   all(d$components[1:2] == "country:CD|administrative_area:Kasaï-Central"))
ok("DPS rungs 3-4 are country-only",      all(d$components[3:4] == "country:CD"))
ok("DPS rung 1 looks for an office",      d$target[1] == "office")
ok("apostrophes survive templating",
   build_query_variants("N'Gandajika", "Lomami")$address[1] == "Zone de Sante de N'Gandajika")

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
section("Point basis")
ok("a POI is an establishment",           point_basis(mikalayi_poi$types) == "establishment")
ok("a locality is a settlement",          point_basis(rutshuru$types) == "settlement")
ok("a sublocality is a settlement",       point_basis(bolenge$types) == "settlement")
ok("a province centroid is other",
   point_basis("administrative_area_level_1|political") == "other")
ok("a failed row has no basis",           is.na(point_basis(NA_character_)))
ok("point_basis is vectorised",
   identical(point_basis(c(rutshuru$types, kingasani$types)), c("settlement", "establishment")))

# Why every DPS office hit goes to review: the gate matches against the town,
# and the Kingasani street -- a real response -- is in the right town. As a
# "DPS Kinshasa" candidate it passes cleanly, whatever building it is.
a_dps_kin <- assess_candidate(kingasani, "Kinshasa", "Kinshasa", n_results = 1L)
ok("a building in the right town passes the gate", a_dps_kin$accepted)
ok("...at high confidence",               confidence_tier(a_dps_kin, 1) == "high")
ok("...so only its basis can flag it",    point_basis(kingasani$types) == "establishment")

# ---------------------------------------------------------------------------
section("DPS ladder: regressions from real API responses")

# Rung 1 for 24 of 26 DPS: Google has no DPS office and returns the province.
kc_office <- candidate("Kasaï-Central, République démocratique du Congo", "APPROXIMATE",
                       "administrative_area_level_1|political", TRUE, "Kasaï-Central",
                       lat = -6.2514921, lon = 22.2384017)
a_kc <- assess_candidate(kc_office, "Kananga", "Kasaï-Central", 1L)
ok("an office query's province centroid is REJECTED", !a_kc$accepted)
ok("...as an admin centroid",             grepl("administrative-area centroid", a_kc$reject_reason))

# Rung 1 for DPS Lualaba: a real village called Lualaba, in the right province,
# about 30 km from Kolwezi. It is a locality, so neither the centroid rule nor
# point_basis objects -- only matching against the chef-lieu refuses it.
lualaba <- candidate("Lualaba, République démocratique du Congo", "APPROXIMATE",
                     "locality|political", TRUE, "Lualaba", "Lualaba",
                     lat = -10.48087, lon = 25.634159)
a_lua <- assess_candidate(lualaba, "Kolwezi", "Lualaba", 1L)
ok("a same-province village named for the province is REJECTED", !a_lua$accepted)
ok("...on the name alone",
   grepl("unrelated", a_lua$reject_reason) && !grepl("centroid", a_lua$reject_reason))
ok("...which point_basis would not have caught", point_basis(lualaba$types) == "settlement")

# Rung 1 for DPS Kinshasa: the office query returns the city itself.
kin_office <- candidate("Kinshasa, République démocratique du Congo", "APPROXIMATE",
                        "locality|political", TRUE, "Kinshasa", "Kinshasa",
                        lat = -4.3032527, lon = 15.310528)
a_kin <- assess_candidate(kin_office, "Kinshasa", "Kinshasa", 1L)
ok("an office query answered by the town is accepted", a_kin$accepted)
ok("...at high confidence",               confidence_tier(a_kin, 1) == "high")
ok("...and labelled a settlement, not an office", point_basis(kin_office$types) == "settlement")

# Rung 2 for DPS Kasaï-Central: the chef-lieu fallback.
kananga <- candidate("Kananga, République démocratique du Congo", "APPROXIMATE",
                     "locality|political", FALSE, "Kasaï-Central", "Kananga",
                     lat = -5.897522, lon = 22.4172256)
a_kan <- assess_candidate(kananga, "Kananga", "Kasaï-Central", 1L)
ok("the chef-lieu fallback reaches HIGH", a_kan$accepted && confidence_tier(a_kan, 2) == "high")

# ---------------------------------------------------------------------------
section("2021 sites: regressions from real API responses")

# Maluku 1, rung 1: a street called Maluku in central Kinshasa, some 70 km from
# Maluku itself. Right province, so only the name check can refuse it.
maluku <- candidate("1 Maluku, Kinshasa, République démocratique du Congo",
                    "RANGE_INTERPOLATED", "street_address", TRUE, "Kinshasa", "Kinshasa",
                    lat = -4.3561391, lon = 15.3284166)
a_mal <- assess_candidate(maluku, "Maluku 1", "Kinshasa", n_results = 2L)
ok("a same-named street in the right province is REJECTED", !a_mal$accepted)
ok("...on the name",                      grepl("unrelated", a_mal$reject_reason))
ok("...and is not a settlement",          point_basis(maluku$types) == "other")

# Nyemba, rung 2: Google's "Niemba", probably the same place spelled another
# way. Scored against the whole address it falls below the floor, so it is
# refused and has to be pinned by hand -- the gate does not guess at spellings.
niemba <- candidate("Niemba, République démocratique du Congo", "APPROXIMATE",
                    "establishment|natural_feature", FALSE, "Tanganyika",
                    lat = -5.9497307, lon = 28.4309994)
ok("a spelling variant without a locality is REJECTED",
   !assess_candidate(niemba, "Nyemba", "Tanganyika", 1L)$accepted)
ok("...though the bare names are close",
   name_similarity("Nyemba", "Niemba") > gate$similarity_floor)

# Wanierukula, rung 1: Google spells it "Waine-Rukula". The locality carries the
# name, so it clears the floor but is held at low confidence for review.
waine <- candidate("Waine-Rukula, République démocratique du Congo", "APPROXIMATE",
                   "locality|political", TRUE, "Tshopo", "Waine-Rukula",
                   lat = 0.1983232, lon = 25.5266578)
a_wai <- assess_candidate(waine, "Wanierukula", "Tshopo", 1L)
ok("a transposed spelling is accepted",   a_wai$accepted)
ok("...but only at LOW confidence",       confidence_tier(a_wai, 1) == "low")

# ---------------------------------------------------------------------------
section("Google kind: every recorded Google response")

# The gate now rejects by kind. For Google, kind must reproduce exactly what
# the old rules decided on every response recorded above.
google_cases <- list(
  list(bolenge, "settlement"), list(rutshuru, "settlement"),
  list(mikalayi_poi, "establishment"), list(kingasani, "establishment"),
  list(kc_office, "area"), list(lualaba, "settlement"),
  list(kin_office, "settlement"), list(kananga, "settlement"),
  list(maluku, "other"), list(niemba, "establishment"), list(waine, "settlement")
)
ok("google_kind matches every recorded Google response",
   all(map_lgl(google_cases, \(x) google_kind(x[[1]]$location_type, x[[1]]$types) == x[[2]])))
ok("a province centroid is an area",
   google_kind("APPROXIMATE", "administrative_area_level_1|political") == "area")
ok("a non-APPROXIMATE admin result is not an area",
   google_kind("GEOMETRIC_CENTER", "administrative_area_level_2|political") != "area")
ok("a Google route is linear",            google_kind("GEOMETRIC_CENTER", "route") == "linear")
ok("Google candidates are completed with the new columns",
   identical(names(complete_google_candidates(bolenge)), names(empty_candidates())) &&
     complete_google_candidates(bolenge)$kind == "settlement")

# ---------------------------------------------------------------------------
section("Nominatim: regressions from real API responses")

mik_n <- nominatim_fixture("nominatim_mikalayi_structured.json")
ok("the parser fills the shared schema",  identical(names(mik_n), names(empty_candidates())))
ok("Mikalayi parses as a village in Kasaï-Central",
   mik_n$kind == "settlement" && mik_n$admin1 == "Kasaï-Central" && mik_n$name == "Mikalayi")
ok("an OSM id is prefixed, never a bare Google-like id", startsWith(mik_n$place_id, "osm:node/"))
a_mik_n <- assess_candidate(mik_n, "Mikalayi", "Kasaï-Central")
ok("Google's failure Mikalayi is found and accepted", a_mik_n$accepted)
ok("...at HIGH confidence on the pinned rung", confidence_tier(a_mik_n, 2) == "high")

mik_free <- nominatim_fixture("nominatim_mikalayi_free.json")
ok("OSM's Mikalayi health zone parses as an area", mik_free$kind[2] == "area")
ok("...and is REJECTED as a centroid",
   grepl("administrative-area centroid", assess_candidate(mik_free[2, ], "Mikalayi", "Kasaï-Central")$reject_reason))

# Structured query city=Nyanga, state=Kasaï: the village of Bakwa-Nyanga.
bakwa <- nominatim_fixture("nominatim_nyanga_structured.json")
a_bakwa <- assess_candidate(bakwa, "Nyanga", "Kasaï")
ok("Bakwa-Nyanga, in the right province, is REJECTED", bakwa$admin1 == "Kasaï" && !a_bakwa$accepted)
ok("...on the name",                      grepl("unrelated", a_bakwa$reject_reason))

nyanga_n <- nominatim_fixture("nominatim_nyanga_free.json")
ok("no free-text Nyanga is accepted for Kasaï",
   !any(map_lgl(assess_each(nyanga_n, "Nyanga", "Kasaï"), "accepted")))
ok("...its only Kasaï hit is the health-zone polygon",
   identical(nyanga_n$kind[normalise_name(nyanga_n$admin1) == "kasai"], "area"))

manika_n <- assess_each(nominatim_fixture("nominatim_manika_free.json"), "Manika", "Lualaba")
ok("Manika the Kalemie neighbourhood is REJECTED on the province",
   grepl("Tanganyika", manika_n[[1]]$reject_reason))
ok("Manika the Lualaba health zone is REJECTED as a centroid",
   grepl("centroid", manika_n[[2]]$reject_reason))

nyemba_n <- nominatim_fixture("nominatim_nyemba_free.json")
a_nye <- assess_each(nyemba_n, "Nyemba", "Tanganyika")
ok("Google's failure Nyemba is found as a town", a_nye[[1]]$accepted && nyemba_n$kind[1] == "settlement")
ok("the Nyemba river is REJECTED as linear, though name and province match",
   nyemba_n$kind[2] == "linear" && !a_nye[[2]]$accepted &&
     !grepl("unrelated|province", a_nye[[2]]$reject_reason))

mwene_n <- nominatim_fixture("nominatim_mwene_ditu_free.json")
a_mwe <- assess_each(mwene_n, "Mwene-ditu", "Lomami")
ok("Mwene-Ditu's health-zone polygons are REJECTED", !a_mwe[[1]]$accepted && !a_mwe[[2]]$accepted)
ok("the Kinshasa streets named Mwene Ditu are REJECTED",
   all(mwene_n$kind[3:4] == "linear") && !a_mwe[[3]]$accepted && !a_mwe[[4]]$accepted)
ok("the Mwene-Ditu railway station is accepted, as a building in the town",
   a_mwe[[5]]$accepted && mwene_n$kind[5] == "establishment")

kan_n <- nominatim_fixture("nominatim_kananga_structured.json")
ok("the DPS chef-lieu Kananga is a city, accepted",
   kan_n$kind == "settlement" && assess_candidate(kan_n, "Kananga", "Kasaï-Central")$accepted)

# ---------------------------------------------------------------------------
section("Photon: regressions from real API responses")

mik_p <- photon_fixture("photon_mikalayi.json")
a_mik_p <- assess_each(mik_p, "Mikalayi", "Kasaï-Central")
ok("the parser fills the shared schema",  identical(names(mik_p), names(empty_candidates())))
ok("Photon's 'Kasaï Central' passes the province check", mik_p$admin1[1] == "Kasaï Central" && a_mik_p[[1]]$province_match)
ok("Mikalayi village is accepted",        a_mik_p[[1]]$accepted)
ok("its health-zone polygon is REJECTED", mik_p$kind[2] == "area" && !a_mik_p[[2]]$accepted)
ok("a cathedral named after Mikalayi is REJECTED on the whole name",
   !a_mik_p[[3]]$accepted && grepl("unrelated", a_mik_p[[3]]$reject_reason))
ok("Photon's loose matches (Mitala, Mikala) are all REJECTED",
   !any(map_lgl(a_mik_p[4:8], "accepted")))
ok("Photon ids use OSM's element names", startsWith(mik_p$place_id[1], "osm:node/"))

nye_p <- photon_fixture("photon_nyemba.json")
a_nye_p <- assess_each(nye_p, "Nyemba", "Tanganyika")
ok("Nyemba town is accepted, and only it",
   identical(which(map_lgl(a_nye_p, "accepted")), 1L))
ok("...six river segments REJECTED as linear", sum(nye_p$kind == "linear") == 6)

mwe_p <- photon_fixture("photon_mwene_ditu.json")
ok("no Photon Mwene-Ditu is accepted: streets, polygons and the airport",
   !any(map_lgl(assess_each(mwe_p, "Mwene-ditu", "Lomami"), "accepted")))

# DPS rung 1, the office query, as Photon answered it for two provinces.
office_q <- \(p) build_query_variants("x", p, ladder = ladders$dps)$address[1]
hk_p <- photon_fixture("photon_dps_office_haut_katanga.json")
a_hk <- map(seq_len(nrow(hk_p)), \(j) assess_candidate(hk_p[j, ], "Lubumbashi", "Haut-Katanga",
                                                       office = office_q("Haut-Katanga")))
church <- which(hk_p$name == "Eglise catholique Sainte Elisabeth")
ok("a church in Lubumbashi passes on the town alone",
   assess_candidate(hk_p[church, ], "Lubumbashi", "Haut-Katanga")$accepted)
ok("...but is REJECTED as the answer to the office query",
   !a_hk[[church]]$accepted && grepl("not the office", a_hk[[church]]$reject_reason))
ok("no Haut-Katanga answer is taken for the DPS office", !any(map_lgl(a_hk, "accepted")))
nk_p <- photon_fixture("photon_dps_office_nord_kivu.json")
a_nk <- assess_candidate(nk_p, "Goma", "Nord-Kivu", office = office_q("Nord-Kivu"))
ok("Goma's 'Division Provinciale de la Santé' is accepted as the office",
   a_nk$accepted && nk_p$kind == "establishment")
ok("Google's unnamed buildings are not held to the office name",
   assess_candidate(kingasani, "Kinshasa", "Kinshasa", office = office_q("Kinshasa"))$accepted)

# ---------------------------------------------------------------------------
section("GRID3: regressions from real API responses")

bcz <- grid3_fixture("grid3_bcz_subset.json")
ok("the BCZ rows parse",                  nrow(bcz) == 5 && all(c("zonesante", "lat") %in% names(bcz)))

mik_g <- grid3_match_bcz("Mikalayi", "Kasaï-Central", bcz)
ok("Google's failure Mikalayi has a BCZ", nrow(mik_g) == 1 && mik_g$kind == "establishment")
ok("...accepted at HIGH on rung 1",
   confidence_tier(assess_candidate(mik_g, "Mikalayi", "Kasaï-Central"), 1) == "high")
ok("...about 1.5 km from OSM's Mikalayi village",
   abs(haversine_km(mik_g$lat, mik_g$lon, mik_n$lat, mik_n$lon) - 1.4) < 0.3)
ok("a BCZ in another province is not returned", nrow(grid3_match_bcz("Mikalayi", "Kasaï", bcz)) == 0)

mal_g <- grid3_match_bcz("Maluku 1", "Kinshasa", bcz)
a_mal_g <- assess_each(mal_g, "Maluku 1", "Kinshasa")
ok("Maluku 1 comes before Maluku 2",      identical(mal_g$name, c("Maluku 1", "Maluku 2")))
ok("BCZ Maluku 1 is accepted",            a_mal_g[[1]]$accepted)
ok("BCZ Maluku 2, 70 km away, is REJECTED on its number",
   !a_mal_g[[2]]$accepted && grepl("numbered name", a_mal_g[[2]]$reject_reason) &&
     haversine_km(mal_g$lat[1], mal_g$lon[1], mal_g$lat[2], mal_g$lon[2]) > 60)
ok("...though its similarity clears the floor", a_mal_g[[2]]$similarity >= gate$similarity_floor)

mwe_g <- grid3_match_bcz("Mwene-ditu", "Lomami", bcz)
ok("GRID3's 'Mweneditu' is found for Mwene-ditu", nrow(mwe_g) == 2)
ok("...its two rows 30 m apart are one place", count_distinct_places(mwe_g) == 1L)

nyemba_g <- grid3_fixture("grid3_settlements_tanganyika_nyemba.json")
ok("GRID3 has five Nyemba villages in Tanganyika (two numbered)",
   sum(str_detect(normalise_name(nyemba_g$localite), "^nyemba( [0-9]+)?$")) == 5)
ok("...none in health zone Nyemba, so none is returned",
   nrow(grid3_match_settlement("Nyemba", "Tanganyika", nyemba_g)) == 0)

vanga_g <- grid3_fixture("grid3_settlements_kwilu_vanga.json")
v_g <- grid3_match_settlement("Vanga", "Kwilu", vanga_g)
ok("Vanga is found inside health zone Vanga", nrow(v_g) == 1 && v_g$admin2 == "Vanga")
ok("...not the Vanga village of Idiofa",  !"Idiofa" %in% v_g$admin2)
ok("...nor Vanga Mission or Vanga Cité",  identical(v_g$name, "Vanga"))
ok("a GRID3 village or bloc is a settlement, an avenue linear",
   identical(grid3_settlement_kind(c("Village", "Quaŕtier", "Bloc", "Avenue", "Autre")),
             c("settlement", "settlement", "settlement", "linear", "other")))

# Health zone Kalima: its one "Kalima" is an avenue; the villages Kalema and
# Kalimu score 0.83 and are other places, several km from Kalima town.
kalima_g <- grid3_fixture("grid3_settlements_maniema_kalima.json")
k_g <- grid3_match_settlement("Kalima", "Maniema", kalima_g)
ok("near-named villages in the health zone are not returned",
   !any(c("Kalema", "Kalimu") %in% k_g$name) &&
     whole_name_similarity("Kalima", "Kalema") >= gate$similarity_floor)
ok("...only the exact name, here an avenue",  identical(k_g$name, "Kalima") && k_g$kind == "linear")
ok("...which the gate then refuses",          !assess_candidate(k_g, "Kalima", "Maniema")$accepted)

free_rung <- build_query_variants("Vanga", "Kwilu")[4, ]
ok("GRID3 answers no free-text rung",     geocode_grid3(free_rung)$n_results == 0)

# ---------------------------------------------------------------------------
section("Ladder walk, replaying recorded responses")

#' A provider that answers each rung with a recorded response, and remembers
#' which rungs it was asked.
replay <- function(by_rung) {
  asked <- integer(0)
  fetch <- function(q, profile) {
    asked <<- c(asked, q$rung)
    as_response(by_rung[[as.character(q$rung)]])
  }
  list(fetch = fetch, asked = function() asked)
}

nom_nyanga <- replay(list("2" = bakwa, "4" = nyanga_n))
r_nyanga <- geocode_site("DRC-NYANGA", "Nyanga", "Kasaï", provider = "nominatim",
                         fetch = nom_nyanga$fetch)
ok("Nominatim skips the health-zone rung", identical(nom_nyanga$asked(), c(2L, 3L, 4L)))
ok("Nyanga fails on Nominatim",           r_nyanga$result$geocode_status == "failed")
ok("...with the provider on the failed row", r_nyanga$result$provider == "nominatim")
ok("...and every candidate in the audit", nrow(r_nyanga$audit) == 1 + 1 + 5 &&
     all(r_nyanga$audit$provider == "nominatim"))
ok("...including why each was refused",
   any(grepl("unrelated", r_nyanga$audit$reject_reason)) &&
     any(grepl("centroid", r_nyanga$audit$reject_reason)))

nom_mik <- replay(list("2" = mik_n))
r_mik <- geocode_site("DRC-MIKALAYI", "Mikalayi", "Kasaï-Central", provider = "nominatim",
                      fetch = nom_mik$fetch)$result
ok("Mikalayi resolves on Nominatim's rung 2", r_mik$resolved_at_rung == 2 && r_mik$confidence == "high")
ok("...stamped with the provider",        r_mik$geocode_status == "nominatim" && r_mik$provider == "nominatim")
ok("...and its kind and own name",        r_mik$matched_kind == "settlement" && r_mik$matched_name == "Mikalayi")
ok("the ladder stops at the first acceptance", identical(nom_mik$asked(), 2L))

ggl <- replay(list())
geocode_site("DRC-MIKALAYI", "Mikalayi", "Kasaï-Central", provider = "google", fetch = ggl$fetch)
ok("Google runs all four rungs",          identical(ggl$asked(), 1:4))
grid_dps <- replay(list())
geocode_site("DRC-DPS-KWILU", "Bandundu", "Kwilu", point_set = "dps", provider = "grid3",
             fetch = grid_dps$fetch)
ok("GRID3 runs only the DPS chef-lieu rung", identical(grid_dps$asked(), 2L))

# GRID3 through its real adapter logic, on the recorded tables.
grid3_replay <- function(q, profile) {
  if (!isTRUE(q$pinned)) return(as_response(NULL))
  as_response(switch(q$target,
                     health_zone = grid3_match_bcz(q$name, q$province, bcz),
                     settlement  = grid3_match_settlement(q$name, q$province, vanga_g),
                     NULL))
}
r_mal <- geocode_site("DRC-MALUKU-1", "Maluku 1", "Kinshasa", provider = "grid3",
                      fetch = grid3_replay)$result
ok("Google's failure Maluku 1 resolves to its BCZ",
   r_mal$geocode_status == "grid3" && r_mal$resolved_at_rung == 1 &&
     abs(r_mal$latitude - -4.065825) < 1e-6)
r_mwe <- geocode_site("DRC-MWENE-DITU", "Mwene-ditu", "Lomami", provider = "grid3",
                      fetch = grid3_replay)$result
ok("a duplicated BCZ raises no ambiguity flag",
   r_mwe$n_results == 2 && r_mwe$confidence == "high" && !grepl("distinct", r_mwe$quality_flags))
r_van <- geocode_site("DRC-VANGA", "Vanga", "Kwilu", provider = "grid3", fetch = grid3_replay)$result
ok("Vanga, which has no BCZ here, resolves on the settlement rung", r_van$resolved_at_rung == 2)

both <- geocode_point_all("DRC-MIKALAYI", "Mikalayi", "Kasaï-Central",
                          use = c("google", "grid3", "nominatim"),
                          fetchers = list(google = replay(list())$fetch,
                                          grid3 = grid3_replay,
                                          nominatim = replay(list("2" = mik_n))$fetch))
ok("every provider answers every point",  identical(both$by_provider$provider, c("google", "grid3", "nominatim")))
ok("...independently",                    identical(both$by_provider$geocode_status, c("failed", "grid3", "nominatim")))
ok("the audit records which provider saw what", setequal(unique(both$audit$provider), c("google", "grid3", "nominatim")))

# ---------------------------------------------------------------------------
section("Provider chains and the cross-check")

# Mikalayi as the providers answered it, plus Photon's (same) village.
mik_photon <- both$by_provider[3, ] |> mutate(provider = "photon", geocode_status = "photon")
mik_all <- bind_rows(both$by_provider, mik_photon)

g_first <- select_chain(mik_all, chains$google_first)
o_first <- select_chain(mik_all, chains$open_first)
ok("google_first falls through Google's failure to GRID3", g_first$geocode_status == "grid3")
ok("open_first starts with GRID3",        o_first$geocode_status == "grid3")
ok("a chain keeps one row per point",     nrow(g_first) == 1)
osm_only <- select_chain(mik_all, c("photon", "nominatim"))
ok("a chain respects its own order",      osm_only$geocode_status == "photon")
ok("a point no provider in the chain resolved keeps a failed row, without a provider",
   select_chain(mik_all, "google")$geocode_status == "failed" &&
     is.na(select_chain(mik_all, "google")$provider))
ok("providers absent from the results are ignored", nrow(select_chain(mik_all, c("geonames", "grid3"))) == 1)

x_grid <- crosscheck_points(g_first, mik_all)
ok("GRID3 and OSM agree on Mikalayi",     x_grid$crosscheck == "agree")
ok("...Nominatim and Photon count as one family", x_grid$n_sources_agree == 1L)
ok("...the note lists every distance",    grepl("nominatim 1.4 km", x_grid$crosscheck_note) &&
     grepl("photon 1.4 km", x_grid$crosscheck_note))

x_osm <- crosscheck_points(select_chain(mik_all, c("nominatim")), mik_all |> filter(provider != "grid3"))
ok("Photon alone does not confirm Nominatim: single-source", x_osm$crosscheck == "single-source")
x_fail <- crosscheck_points(select_chain(mik_all, "google"), mik_all)
ok("a failed point has no cross-check",   is.na(x_fail$crosscheck))

# Disagreement: Nyemba town (Nominatim) against a point 80 km off, at the
# Kalemie village of the same name.
nye_rows <- tibble(site_id = "DRC-NYEMBA", provider = c("nominatim", "grid3"),
                   latitude = c(nyemba_n$lat[1], -5.942532), longitude = c(nyemba_n$lon[1], 29.177019),
                   geocode_status = c("nominatim", "grid3"))
x_dis <- crosscheck_points(select_chain(nye_rows, "nominatim"), nye_rows)
ok("an answer 80 km away is a disagreement", x_dis$crosscheck == "disagree" && x_dis$max_disagreement_km > 80)
ok("...which never touches confidence",   !"confidence" %in% setdiff(names(x_dis), names(nye_rows)))

pinned <- g_first |> mutate(geocode_status = "manual", confidence = "manual",
                            latitude = mik_n$lat, longitude = mik_n$lon)
x_pin <- crosscheck_points(pinned, mik_all)
ok("a manual pin is checked against every provider",
   x_pin$crosscheck == "agree" && x_pin$n_sources_agree == 2L)

ok("review: anything below high",         needs_review("medium", "agree"))
ok("review: a disagreement, even if high", needs_review("high", "disagree"))
ok("review: an unconfirmed point",        needs_review("high", "single-source"))
ok("review: not a confirmed high",        !needs_review("high", "agree"))
ok("review: not an uncontradicted pin",   !needs_review("manual", "single-source"))
ok("review: a contradicted pin",          needs_review("manual", "disagree"))
ok("review: a failure",                   needs_review("failed", NA))

# ---------------------------------------------------------------------------
section("Provider configuration")
ok("every provider has an adapter",       setequal(names(providers), names(provider_fetchers)))
ok("chains name only known providers",    all(unlist(chains) %in% names(providers)))
ok("both chains hold every provider",     all(map_lgl(chains, \(ch) setequal(ch, names(providers)))))
ok("open_first puts Google last",         tail(chains$open_first, 1) == "google")
ok("every provider says which rungs it skips, per point set",
   all(map_lgl(providers, \(p) setequal(names(p$skip_rungs), names(ladders)))))
ok("Nominatim and Photon are one family", provider_family("nominatim") == provider_family("photon"))
ok("a manual pin has no family",          is.na(provider_family("manual")))
ok("GeoNames is off until it has a username", !"geonames" %in% enabled_providers())
ok("the GeoNames table covers the 26 provinces",
   setequal(normalise_name(names(geonames_admin1)), normalise_name(drc_provinces)) &&
     !anyDuplicated(geonames_admin1))
ok("credential_status reports without stopping",
   is.data.frame(credential_status(c("google", "grid3"))) &&
     credential_status("grid3")$set)
ok("province_bbox gives a province's extent",
   all(abs(province_bbox("Bas-Uele", pad = 0) - c(22.45, 1.95, 27.70, 5.40)) < 1e-9))

# ---------------------------------------------------------------------------
section("Response cache")
tmp <- tempfile()
dir.create(tmp)
cache_load(tmp)
k <- cache_key("Vanga", "country:CD")
ok("the Google key is still address|components", k == "Vanga|country:CD")
ok("empty cache starts empty",            is.null(cache_get(k)))
cache_put(k, list(status = "OK", n_results = 1L))
ok("cache_get returns what was stored",   cache_get(k)$status == "OK")
ok("the key includes components",         is.null(cache_get(cache_key("Vanga", "country:CD|administrative_area:Kwilu"))))
ok("each provider has its own store",     is.null(cache_get(k, "nominatim")))
cache_save(); cache_load(tmp)
ok("cache survives save and reload",      cache_get(k)$n_results == 1L)
ok("...in one file per provider",         file.exists(file.path(tmp, "google_geocode_cache.rds")))
ok("only stores that changed are written", !file.exists(file.path(tmp, "photon_geocode_cache.rds")))

aged <- .geocode_cache$stores$google[[k]]
aged$cached_at <- Sys.time() - 31 * 86400
.geocode_cache$stores$google[[k]] <- aged
cache_put(k, list(status = "OK"), "nominatim")
.geocode_cache$stores$nominatim[[k]]$cached_at <- Sys.time() - 365 * 86400
ok("a Google answer older than 30 days has expired", is.null(cache_get(k, "google")))
ok("a year-old Nominatim answer has not", !is.null(cache_get(k, "nominatim")))

legacy <- file.path(tmp, "google_geocode_cache.rds")
saveRDS(list(old = list(status = "OK", n_results = 1L)), legacy)
Sys.setFileTime(legacy, Sys.time() - 40 * 86400)
cache_load(tmp)
ok("an entry without a timestamp takes the file's time",
   abs(as.numeric(difftime(.geocode_cache$stores$google$old$cached_at,
                           Sys.time() - 40 * 86400, units = "hours"))) < 1)
ok("...and so expires with it",           is.null(cache_get("old")))

n_fetch <- 0
fetch_once <- function() { n_fetch <<- n_fetch + 1; list(status = "OK") }
cached_fetch("photon", "q=Vanga", fetch_once); cached_fetch("photon", "q=Vanga", fetch_once)
ok("a cached answer is not fetched again", n_fetch == 1)
stats <- cache_stats()
ok("...and counts as a hit",              stats$cache_hits[stats$provider == "photon"] == 1)
ok("a provider without a credential needs none", is.na(provider_credential("photon")))
old_username <- Sys.getenv("GEONAMES_USERNAME", NA)
Sys.unsetenv("GEONAMES_USERNAME")
ok("a missing credential stops the request that needs it",
   inherits(try(provider_credential("geonames"), silent = TRUE), "try-error"))
if (!is.na(old_username)) Sys.setenv(GEONAMES_USERNAME = old_username)
unlink(tmp, recursive = TRUE)

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

dps_base <- base |> rename(dps_id = site_id) |>
  mutate(dps_id = c("DRC-DPS-KWILU", "DRC-DPS-KASAI-CENTRAL"))
dps_filled <- tempfile(fileext = ".csv")
writeLines(c("dps_id,latitude,longitude,note",
             "DRC-DPS-KASAI-CENTRAL,-5.89,22.42,office confirmed"), dps_filled)
dps_res <- apply_manual_overrides(dps_base, dps_filled, id_col = "dps_id")
ok("overrides can key on dps_id",         dps_res$latitude[2] == -5.89 && dps_res$confidence[2] == "manual")
ok("a dps_id override leaves others",     dps_res$latitude[1] == -4.4)
unlink(c(empty, filled, dps_filled))

# ---------------------------------------------------------------------------
section("Pairs")
ok("haversine: same point is 0 km",       haversine_km(-4, 18, -4, 18) == 0)
ok("haversine: 1 degree of latitude",     abs(haversine_km(0, 20, 1, 20) - 111.19) < 0.01)

reg_dps <- tibble(dps_id = c("DRC-DPS-BAS-UELE", "DRC-DPS-KASAI-CENTRAL"),
                  dps = c("DPS Bas-Uele", "DPS Kasaï-Central"),
                  province = c("Bas-Uele", "Kasaï-Central"),
                  chef_lieu = c("Buta", "Kananga"),
                  latitude = c(2.8045317, -5.9), longitude = c(24.7499112, 22.4),
                  confidence = "high", point_basis = "settlement")
reg_sites <- tibble(site_id = c("DRC-BUTA", "DRC-MIKALAYI"),
                    sentinel_site = c("Buta", "Mikalayi"),
                    province = c("Bas-Uele", "Kasaï-Central"),
                    latitude = c(2.8045317, NA), longitude = c(24.7499112, NA),
                    confidence = c("high", "failed"))
pair_in <- tibble(network = "2014", province = c("Bas-Uele", "Kasaï-Central"),
                  dps = c("DPS Bas-Uele", "DPS Kasai-Central"),
                  sentinel_site = c("Buta", "Mikalayi"))
pp <- build_pairs(pair_in, reg_dps, reg_sites)
ok("pairs resolve names to both ids",     identical(pp$dps_id, reg_dps$dps_id))
ok("a town site is co-located with its DPS", pp$co_located[1] && pp$straight_line_km[1] == 0)
ok("a site without coordinates is incomplete", !pp$complete[2] && !pp$co_located[2])
ok("an incomplete pair is kept, not dropped", nrow(pp) == 2)
ok("matching provinces raise no mismatch", !any(pp$province_mismatch))
ok("an unknown site stops the build",
   inherits(try(build_pairs(tibble(network = "2021", province = "Bas-Uele",
                                   dps = "DPS Bas-Uele", sentinel_site = "Bondo"),
                            reg_dps, reg_sites), silent = TRUE), "try-error"))
ok("a site paired twice in a network stops the build",
   inherits(try(build_pairs(bind_rows(pair_in, pair_in), reg_dps, reg_sites),
                silent = TRUE), "try-error"))
ok("the same pair in two networks is fine",
   nrow(build_pairs(bind_rows(pair_in, mutate(pair_in, network = "2003_2005")),
                    reg_dps, reg_sites)) == 4)

# Chronological order whatever the input order: 2014 rows given first, and the
# 2003_2005 rows in reverse, which must survive.
mixed <- bind_rows(pair_in, mutate(pair_in[2:1, ], network = "2003_2005"))
ordered <- build_pairs(mixed, reg_dps, reg_sites)
ok("networks come out in chronological order",
   identical(ordered$network, c("2003_2005", "2003_2005", "2014", "2014")))
ok("rows keep their input order within a network",
   identical(ordered$sentinel_site[1:2], c("Mikalayi", "Buta")))
ok("a network name without a leading year stops the build",
   inherits(try(build_pairs(mutate(pair_in, network = "baseline"), reg_dps, reg_sites),
                silent = TRUE), "try-error"))

# Mwene-Ditu in 2003-2005: its DPS seat (Mbuji-Mayi) stayed in Kasaï-Oriental
# while the site went to Lomami in the 2015 split.
reg_dps2 <- bind_rows(reg_dps, tibble(
  dps_id = "DRC-DPS-KASAI-ORIENTAL", dps = "DPS Kasaï-Oriental", province = "Kasaï-Oriental",
  chef_lieu = "Mbuji-Mayi", latitude = -6.1307, longitude = 23.5967,
  confidence = "high", point_basis = "settlement"))
reg_sites2 <- bind_rows(reg_sites, tibble(
  site_id = "DRC-MWENE-DITU", sentinel_site = "Mwene-ditu", province = "Lomami",
  latitude = -7.0093377, longitude = 23.4504358, confidence = "high"))
mwene <- build_pairs(tibble(network = "2003_2005", province = "Kasaï Oriental",
                            dps = "DPS Kasaï Oriental", sentinel_site = "Mwene-Ditu"),
                     reg_dps2, reg_sites2)
ok("an old-province pair across the 2015 split is accepted", nrow(mwene) == 1 && mwene$complete)
ok("...flagged as a province mismatch",   mwene$province_mismatch)
ok("...and keeps its old province name",  mwene$network_province == "Kasaï Oriental")
ok("...and its old DPS name, not the shared seat's", mwene$dps == "DPS Kasaï Oriental")

ok("an unrecognised province stops the build",
   inherits(try(build_pairs(mutate(pair_in, province = "Atlantis"), reg_dps, reg_sites),
                silent = TRUE), "try-error"))
outside <- try(build_pairs(tibble(network = "2003_2005", province = "Bandundu",
                                  dps = "DPS Bas-Uele", sentinel_site = "Buta"),
                           reg_dps, reg_sites), silent = TRUE)
ok("a pair outside its old province stops the build", inherits(outside, "try-error"))
ok("...naming the pair",                  grepl("Bandundu: DPS Bas-Uele", outside))

pairs_in <- read.csv(paths$pairs, stringsAsFactors = FALSE)
ok("pairs input has 26 rows for 2014",    sum(pairs_in$network == "2014") == 26)
ok("pairs input has 11 rows for 2003_2005", sum(pairs_in$network == "2003_2005") == 11)
ok("pairs input has 25 rows for 2021_expansion", sum(pairs_in$network == "2021_expansion") == 25)
ok("pairs input lists 2003_2005 first",
   pairs_in$network[1] == "2003_2005" && !is.unsorted(pairs_in$network))
ok("every pair's province is recognised",
   !anyNA(unlist(lapply(pairs_in$province, successor_provinces))))
ok("every pair's DPS is in the registry",
   all(make_id(pairs_in$dps) %in% dps_ids))
ok("every pair's site is in the inputs",
   all(make_id(pairs_in$sentinel_site) %in% all_sites$site_id))

# ---------------------------------------------------------------------------
cat("\n=====================================\n")
cat(sprintf("PASSED: %d   FAILED: %d\n", pass, fail))
cat("=====================================\n")
if (fail > 0) quit(status = 1)
