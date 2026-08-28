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

# File locations, relative to the pipeline/ directory
paths <- list(
  input     = "../input/drc_sentinel_sites_26.csv",
  overrides = "../input/manual_overrides.csv",
  cache     = "../cache/google_geocode_cache.rds",
  output    = "../output"
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
# Site name corrections
# ---------------------------------------------------------------------------
#
# Applied before query construction. Keys are matched case-insensitively
# against the raw `sentinel_site` value.

site_name_fixes <- c(
  "mwene-ditu" = "Mwene-Ditu"
)
