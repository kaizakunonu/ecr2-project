# Country profile and reference data for the DRC sentinel site geocoding pipeline.
#
# Re-targeting to another country should be a matter of editing this file only.

# ---------------------------------------------------------------------------
# Country profile
# ---------------------------------------------------------------------------

country_profile <- list(
  name_en          = "Democratic Republic of the Congo",
  name_fr          = "Republique Democratique du Congo",
  country_code     = "CD",     # components=country:CD, countrycodes=cd, country=CD
  language         = "fr",     # language= / accept-language= / lang=
  bbox             = list(
    lat_min = -13.5, lat_max = 5.4,
    lon_min =  12.0, lon_max = 31.4
  ),
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
  # Sentinel site inputs, read together by read_sites() as one registry: the
  # 26 sites from extract_sentinel_sites_26.py and the 25 selected in 2021.
  input         = c("../input/drc_sentinel_sites_26.csv",
                    "../input/drc_sentinel_sites_2021_expansion.csv"),
  overrides     = "../input/manual_overrides.csv",
  dps_input     = "../input/drc_dps.csv",
  dps_overrides = "../input/dps_manual_overrides.csv",
  pairs         = "../input/drc_dps_site_pairs.csv",
  provinces     = "../reference/drc_provinces.csv",
  cache_dir     = "../cache",       # one {provider}_geocode_cache.rds per provider
  output        = "../output"
)

# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------
#
# Every enabled provider geocodes every point on every run, so each point can
# be cross-checked; the chains below only decide which answer is kept.
#
# `family` is the underlying data source. Nominatim and Photon both serve
# OpenStreetMap, so their agreement is not independent confirmation, and the
# cross-check counts families, not providers.
#
# `env` names the credential an uncached request needs (NA: none). A provider
# whose credential is missing stops the run at its first uncached request, so
# disable it here instead.
#
# `rate_delay` is the minimum gap, in seconds, between two network requests to
# the provider; cached answers are not delayed. `cache_days` is how long a
# cached answer stays valid: Google's terms allow 30 days for coordinates;
# Nominatim's policy asks for caching; GRID3 and GeoNames are CC BY 4.0.
#
# `skip_rungs` lists, per point set, the ladder rungs a provider does not run:
#   - OSM and GeoNames have no notion of a health zone or a DPS office, and
#     OSM's health-zone polygons are rejected as areas in any case.
#   - GRID3 is matched within the province only (see geocode_grid3()).

providers <- list(
  google = list(
    family = "google", enabled = TRUE, env = "GOOGLE_MAPS_API_KEY",
    rate_delay = 0.05,                 # Google allows 50 requests/second
    cache_days = 30,
    skip_rungs = list(sentinel_site = integer(0), dps = integer(0))
  ),
  grid3 = list(
    family = "grid3", enabled = TRUE, env = NA_character_,
    rate_delay = 0.2,
    cache_days = Inf,
    skip_rungs = list(sentinel_site = 3:4, dps = c(1L, 3L, 4L))
  ),
  nominatim = list(
    family = "osm", enabled = TRUE, env = NA_character_,  # NOMINATIM_EMAIL is optional
    rate_delay = 1.1,                  # policy: at most 1 request/second
    cache_days = Inf,
    skip_rungs = list(sentinel_site = 1L, dps = integer(0))
  ),
  geonames = list(
    # Off until a free account exists: register at geonames.org, enable its
    # web services, export GEONAMES_USERNAME, then set enabled = TRUE.
    family = "geonames", enabled = FALSE, env = "GEONAMES_USERNAME",
    rate_delay = 0.5,                  # free tier: 1000 credits/hour
    cache_days = Inf,
    skip_rungs = list(sentinel_site = 1L, dps = 1L)
  ),
  photon = list(
    family = "osm", enabled = TRUE, env = NA_character_,
    rate_delay = 1,                    # public instance: fair use, no stated limit
    cache_days = Inf,
    skip_rungs = list(sentinel_site = 1L, dps = integer(0))
  )
)

# The two coordinate sets written side by side. google_first is the original
# setup with open sources filling Google's gaps; open_first can be published,
# except for the rows Google had to fill (geocode_status == "google").
#
# Checked against every order in the benchmark's chain simulation (2026-10-05,
# GeoNames not yet running): open_first is the best order that takes nothing
# from Google (11 of 82 points to review), and google_first ties for the best
# order led by Google. GRID3 first suits health zones, whose central office it
# knows; Photon last, as its looser matches put 18 points at medium.
# GeoNames' place in both is a guess until it has run.
chains <- list(
  google_first = c("google", "grid3", "nominatim", "geonames", "photon"),
  open_first   = c("grid3", "nominatim", "geonames", "photon", "google")
)

# Two accepted points closer than this are taken to be the same place.
# Calibrated on the benchmark (2026-10-05): independent high-confidence answers
# for the same place lie a median 0.9 km apart (sentinel sites) and 1.5 km
# (DPS seats), 95% within 4.3 and 3.9 km. The only pairs above 5 km were
# Kapolowe's, where Google stands 11 km from three open sources that agree.
crosscheck <- list(agree_km = 5)

# GRID3 publishes the DRC's health-system geography as public ArcGIS layers
# (CC BY 4.0). The health-zone central offices (BCZ) stand in for a health
# zone's chef-lieu; settlement names carry their health zone.
grid3_layers <- list(
  service     = "https://services3.arcgis.com/BU6Aadhn6tbBEdyk/arcgis/rest/services",
  facilities  = "GRID3_COD_health_facilities_v9_0",
  settlements = "GRID3_COD_settlement_names_v9_0",
  bcz_type    = "Bureau Central de la Zone de Santé"
)

# GeoNames admin1 codes (admin1CodesASCII.txt). GeoNames names provinces in
# English ("South Kivu", "Bas-Congo"), so the code, not the name, is what maps
# a result onto the 26 provinces.
geonames_admin1 <- c(
  "Bas-Uele" = "13", "Equateur" = "02", "Haut-Katanga" = "14",
  "Haut-Lomami" = "15", "Haut-Uele" = "16", "Ituri" = "17", "Kasai" = "18",
  "Kasai-Central" = "23", "Kasai-Oriental" = "04", "Kinshasa" = "06",
  "Kongo-Central" = "08", "Kwango" = "19", "Kwilu" = "20", "Lomami" = "21",
  "Lualaba" = "22", "Mai-Ndombe" = "24", "Maniema" = "10", "Mongala" = "25",
  "Nord-Kivu" = "11", "Nord-Ubangi" = "26", "Sankuru" = "27", "Sud-Kivu" = "12",
  "Sud-Ubangi" = "28", "Tanganyika" = "29", "Tshopo" = "30", "Tshuapa" = "31"
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
# province and `{country}` the French country name. Pinned rungs restrict the
# query to the province, each provider in its own way (Google's
# administrative_area component, Nominatim's state=, a Photon bounding box, a
# GeoNames adminCode1, GRID3's province field). `target` says what the rung is
# looking for, so a provider can route it: GRID3 answers a health zone with its
# central office, Nominatim sends an office to amenity= and a settlement to city=.
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
    pinned   = c(TRUE, TRUE, FALSE, FALSE),
    target   = c("health_zone", "settlement", "settlement", "settlement")
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
    pinned   = c(TRUE, TRUE, FALSE, FALSE),
    target   = c("office", "settlement", "settlement", "settlement")
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
