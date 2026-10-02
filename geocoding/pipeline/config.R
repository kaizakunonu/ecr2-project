# Country profile and reference data for the DRC sentinel site geocoding pipeline.
#
# Re-targeting to another country should be a matter of editing this file only.

# ---------------------------------------------------------------------------
# Country profile
# ---------------------------------------------------------------------------

country_profile <- list(
  name_en          = "Democratic Republic of the Congo",
  name_fr          = "Republique Democratique du Congo",
  country_code     = "CD",     # Google components=country:CD
  language         = "fr",     # Google language= parameter
  bbox             = list(
    lat_min = -13.5, lat_max = 5.4,
    lon_min =  12.0, lon_max = 31.4
  ),
  rate_delay       = 0.05,     # Google allows 50 requests/second
  site_col         = "sentinel_site",
  province_col     = "province",
  id_col           = "site_id",
  id_prefix        = "DRC"
)

# The DPS headquarters are a second point set, geocoded with the same gate.
# `dps` names the office; `province` is the post-2015 province its seat lies in,
# which is what the gate checks, even for a pre-2015 DPS such as Bandundu.
dps_profile <- modifyList(country_profile, list(
  site_col = "dps",
  id_col   = "dps_id"
))

# File locations, relative to the pipeline/ directory
paths <- list(
  input         = "../input/drc_sentinel_sites_26.csv",
  overrides     = "../input/manual_overrides.csv",
  dps_input     = "../input/drc_dps.csv",
  dps_overrides = "../input/dps_manual_overrides.csv",
  pairs         = "../input/drc_dps_site_pairs.csv",
  cache         = "../cache/google_geocode_cache.rds",
  output        = "../output"
)

# ---------------------------------------------------------------------------
# Provinces
# ---------------------------------------------------------------------------
#
# The 26 provinces created by the 2015 reorganisation, which is what the input
# uses and what Google's administrative data reflects. Used only to validate
# the input and catch typos -- comparison goes through normalise_name(), which
# folds accents, so the input's inconsistent spelling ("Kasai" but "Bas-Uele")
# needs no cleaning.

drc_provinces <- c(
  "Bas-Uele", "Equateur", "Haut-Katanga", "Haut-Lomami", "Haut-Uele", "Ituri",
  "Kasai", "Kasai-Central", "Kasai-Oriental", "Kinshasa", "Kongo-Central",
  "Kwango", "Kwilu", "Lomami", "Lualaba", "Mai-Ndombe", "Maniema", "Mongala",
  "Nord-Kivu", "Nord-Ubangi", "Sankuru", "Sud-Kivu", "Sud-Ubangi",
  "Tanganyika", "Tshopo", "Tshuapa"
)

# The 11 provinces of 1988-2015 and the current provinces each became in the
# July 2015 split (as in DPS_2015 of the 1988-2015 province shapefile). A pair
# named under an old province must have its DPS seat and its site inside these
# successors. Compared through normalise_name(), so "Kasaï Occidental" matches.
provinces_pre2015 <- list(
  "Bandundu"           = c("Kwango", "Kwilu", "Mai-Ndombe"),
  "Bas-Congo"          = c("Kongo-Central"),
  "Equateur"           = c("Equateur", "Mongala", "Nord-Ubangi", "Sud-Ubangi", "Tshuapa"),
  "Kasai-Occidental"   = c("Kasai", "Kasai-Central"),
  "Kasai-Oriental"     = c("Kasai-Oriental", "Lomami", "Sankuru"),
  "Katanga"            = c("Haut-Katanga", "Haut-Lomami", "Lualaba", "Tanganyika"),
  "Kinshasa"           = c("Kinshasa"),
  "Maniema"            = c("Maniema"),
  "Nord-Kivu"          = c("Nord-Kivu"),
  "Province Orientale" = c("Bas-Uele", "Haut-Uele", "Ituri", "Tshopo"),
  "Sud-Kivu"           = c("Sud-Kivu")
)

# ---------------------------------------------------------------------------
# Quality gate thresholds
# ---------------------------------------------------------------------------
#
# Calibrated against live API responses, where the separation between good and
# bad matches was unambiguous: every correct match scored a name similarity of
# 1.00, while the two wrong ones scored 0.56 (a street in Kinshasa returned for
# Kingasani) and 0.25 (a Kinshasa business returned for Mikalayi, some 700 km
# from Kasai).

gate <- list(
  similarity_floor = 0.60,  # below this, reject: the returned name is unrelated
  similarity_clean = 0.90   # at or above this, partial_match is not held against it
)

# ---------------------------------------------------------------------------
# Query ladders
# ---------------------------------------------------------------------------
#
# One ladder per point set. `{name}` is the point's name, `{province}` its
# province and `{country}` the French country name. Pinned rungs restrict
# Google's administrative_area component to the province.
#
# Keep rungs 1-2 pinned and 3-4 free text: confidence_tier() reads the rung
# number, and only rungs 1-2 can reach `high`.
#
# The DPS ladder asks for the office first but always matches the result
# against `{name}`, the chef-lieu, so a building in the wrong town is refused
# by the similarity rule. It cannot tell the office from another building in
# the right town -- the workflow sends every such hit to review.

ladders <- list(
  sentinel_site = data.frame(
    rung     = 1:4,
    label    = c("1: health zone + province ({province})",
                 "2: site + province ({province})",
                 "3: site, province, country (free text)",
                 "4: site name only, country-restricted"),
    template = c("Zone de Sante de {name}",
                 "{name}",
                 "{name}, {province}, {country}",
                 "{name}"),
    pinned   = c(TRUE, TRUE, FALSE, FALSE)
  ),
  dps = data.frame(
    rung     = 1:4,
    label    = c("1: DPS office + province ({province})",
                 "2: chef-lieu + province ({province})",
                 "3: chef-lieu, province, country (free text)",
                 "4: chef-lieu only, country-restricted"),
    template = c("Division Provinciale de la Sante {province}",
                 "{name}",
                 "{name}, {province}, {country}",
                 "{name}"),
    pinned   = c(TRUE, TRUE, FALSE, FALSE)
  )
)

# ---------------------------------------------------------------------------
# Site name corrections
# ---------------------------------------------------------------------------
#
# Applied before query construction. Keys are matched case-insensitively
# against the raw `sentinel_site` value.

site_name_fixes <- c(
  "mwene-ditu" = "Mwene-Ditu"
)
