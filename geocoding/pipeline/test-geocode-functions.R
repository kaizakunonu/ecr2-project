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

d <- build_query_variants("Kananga", "Kasaï-Central", ladder = ladders$dps)
ok("DPS ladder is 4 rungs",               nrow(d) == 4 && identical(d$rung, 1:4))
ok("DPS rung 1 asks for the office",      d$address[1] == "Division Provinciale de la Sante Kasaï-Central")
ok("DPS rung 2 falls back to the town",   d$address[2] == "Kananga")
ok("DPS rungs 1-2 pin the province",
   all(d$components[1:2] == "country:CD|administrative_area:Kasaï-Central"))
ok("DPS rungs 3-4 are country-only",      all(d$components[3:4] == "country:CD"))
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
