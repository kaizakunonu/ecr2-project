# Sentinel Site Accessibility, DRC — Paper / Abstract Outline

**Status:** working outline, not for circulation yet
**Source:** Victoire's refined ideas, WhatsApp 26 Jul 2026 (three outputs), organised against `proposal.qmd` (MAP ECR proposal, 15 Jul 2026)
**Compiled:** 29 Jul 2026 · Kaiza Ilomo

---

## 0. What changed, and the one decision that blocks everything else

`proposal.qmd` is a **provincial** study: Kasaï-Central, 26 health zones, anchored on Victoire's PhD entomological dataset, with five objectives including two modelling extensions (building footprints, transmission-opportunity mapping).

The 26 Jul refinement is a **national** study: 26 provinces, three cartographic outputs, no entomological data.

These are not the same paper. Before anything else, settle:

> **Is the national three-output work (a) a replacement scope for the ECR study, (b) a companion Paper 1 with Kasaï-Central as Paper 2, or (c) the poster/conference output while the province paper remains the journal target?**

My read: **(b)**. The national work is cleaner, faster, and needs only open data — a good first paper and a strong poster. But it sacrifices the entomological dataset, which is the team's only genuinely non-replicable asset. Don't spend that advantage by dropping it; sequence it.

Recommended sequencing:

| | Paper | Scale | Anchor data | Why it works |
|---|---|---|---|---|
| **P1** | Sentinel network accessibility & representativeness | National, 26 provinces | Open geospatial only | Fast, no data-sharing dependency, directly answers an NMCP planning question |
| **P2** | Accessibility × vector density site optimisation | Kasaï-Central | Victoire's PhD entomology | Defensible novelty, uses the unique dataset, cites P1 as the national frame |

Everything below outlines **P1**.

---

## 1. Working titles

1. *Geographic accessibility and epidemiological representativeness of the national malaria entomological sentinel surveillance network in the Democratic Republic of the Congo*
2. *From 11 to 52 sentinel sites: does administrative expansion improve surveillance coverage in the DRC?*
3. *Seasonal travel time as an operational-burden metric for entomological sentinel surveillance in the DRC*

Title 2 is the best abstract/poster title — it poses a question with a real answer and states the scenario range up front.

---

## 2. Draft structured abstract

**Background.** DRC's NMCP conducts entomological sentinel surveillance through a network that expanded from 11 sites (one per pre-2010 province) to 26 (one per post-decentralisation Provincial Health Division, DPS), with a proposed further expansion to 52. Sites are intended to represent the country's epidemiological facies and climatic zones. Whether the network achieves that, and what it costs to operate across a country with sparse and seasonally impassable roads, has not been assessed.

**Methods.** We construct a national friction surface from land cover, road class, slope, and hydrology, and compute least-cost travel time under motorised and walking modes. We evaluate three network configurations (11, 26, 52 sites) on two metrics: (i) **operational burden** — travel time and travel distance from each DPS headquarters to its designated sentinel site(s); (ii) **coverage and representativeness** — the population and the climatic/transmission strata falling within defined travel-time bands of the nearest site. Travel time is stratified by dry and wet season. Straight-line distance is computed as a contrast to quantify the infrastructure penalty.

**Results.** [To generate.] Report: median and range of DPS→site travel time by mode and season; the wet-season penalty ratio; the ratio of travel time to Euclidean distance as an infrastructure-friction index; population within 1/2/4/8 h bands per configuration; and the proportion of climatic/transmission strata containing ≥1 site under each configuration.

**Conclusion.** [To generate.] Framed around whether the 26→52 expansion closes representativeness gaps or replicates administrative symmetry, and where a differently-placed 52-site network would perform better for the same operational cost.

---

## 3. Research questions, mapped to Victoire's outputs

| RQ | Question | Victoire's output | Unit of analysis |
|---|---|---|---|
| **RQ1** | How has the geographic distribution of sentinel sites changed across the 11 / 26 / 52 configurations? | Output 1 | Site points; province polygons |
| **RQ2** | What is the travel time from each DPS headquarters to its sentinel site, by motorised and walking mode, and how much does it change between dry and wet season? | Output 2 | 11 / 26 / 52 origin–destination pairs |
| **RQ3** | How does travel time compare with straight-line distance, and what does the gap reveal about infrastructure friction? | Output 3 | Same OD pairs |
| **RQ4** *(added)* | Do the three configurations cover DRC's population and climatic/transmission strata, and does expansion to 52 improve coverage? | — | ~8,500 health areas; gridded population; climate strata |

**Why RQ4 matters.** RQ1–RQ3 as originally framed give you **n = 26 origin–destination pairs**. That supports description and cartography but not inference — a reviewer will ask what the statistical claim is. RQ4 raises the denominator to the national population and the full set of health areas, and it tests a **claim the programme itself has published** (that sites represent epidemiological facies and climatic zones; Mukomena Sompwe et al. 2024). You are auditing a stated design criterion, not inventing one. That is the strongest available framing and it is squarely aligned with the climate–epidemiology remit.

Elevate the seasonal stratification out of "if we have time" and into the core design. It is the part that makes this an MDDA paper rather than a generic accessibility paper.

---

## 4. Prior art: the novelty claim needs rewording

The claim "never done before in DRC" will not survive review as stated. What already exists:

- **National-scale DRC travel-time modelling is published.** Mbunga et al. (2024, *Vaccines*) ran AccessMod 5 walking travel-time across rural DRC against zero-dose vaccination.
- **Subnational DRC accessibility is published.** Pu et al. (2020, *Applied Geography*) modelled off-road walking accessibility and optimal facility siting in North Kivu.
- **The 11→26 expansion narrative is already in print.** Mukomena Sompwe et al. (2024) documents it explicitly, including the one-site-per-DPS logic. A map of that history is a *figure*, not a finding.
- **Seasonal travel-time modelling is a mature method.** Makanga et al. (2017, Mozambique); Ouma, Ray, Ebener et al. (2020); a Côte d'Ivoire national wet/dry analysis (2023 preprint).

What is defensibly new:

1. **The measured object.** Every existing DRC study measures *population → nearest facility*. Nothing measures *DPS headquarters → its designated sentinel site* as a surveillance-operations metric. This is the novel contribution — but you must argue explicitly why it is decision-relevant, or reviewers will ask why you didn't map population→site instead. (RQ4 covers that flank.)
2. **The prospective 52-site scenario**, which is undocumented in any public source.
3. **Bridging two literatures that barely touch** — geographic accessibility modelling and sentinel-network representativeness/optimisation.

Suggested replacement for the novelty sentence:

> First assessment of the operational feasibility and epidemiological representativeness of the DRC's entomological sentinel surveillance network, using seasonally-stratified travel time from each Provincial Health Division to its sentinel site as an operational-burden metric, and evaluating whether the 11→26→52 expansion improves coverage of the country's climatic and transmission strata.

---

## 5. Data inputs

| Layer | Source | Status / risk |
|---|---|---|
| Sentinel site locations + establishment year | **NMCP / PNLP** | **Binding constraint.** Need geocoded coordinates and dates for all three configurations. The proposed 52 may not exist as a georeferenced list yet — may need to be constructed with NMCP. |
| DPS headquarters locations | Provincial capitals; GRID3 / OSM | Straightforward; confirm HQ ≠ provincial capital in any province |
| Health zone / health area boundaries | GRID3 DRC | **GRID3 v01 covers only 5 provinces** (Haut-Katanga, Kinshasa, Kasaï, Kasaï-Oriental, Lomami). A 26-province analysis needs a blended or alternative source — state which and its completeness |
| Road network + surface type | OpenStreetMap | Coverage is uneven across DRC and has improved over time — see §7 on the time-series problem |
| Navigable waterways | HydroSHEDS; national/OSM waterway data | **Do not omit.** River transport dominates in parts of the Congo Basin; ignoring it will distort results badly |
| Land cover | ESA WorldCover / Copernicus Global Land Cover | Drives off-road walking speeds |
| Terrain (slope) | SRTM or MERIT DEM | For Tobler's hiking function |
| Gridded population | WorldPop | For RQ4 coverage bands |
| Rainfall / seasonality | CHIRPS; ERA5-Land | Defines dry vs wet season windows; consider flood extents (Sentinel-1, Global Flood Database) |
| Benchmark friction surface | MAP / Weiss et al. 2020 (motorised + walking) | Use as a **comparator**, not the primary input. Nominal 2019 vintage; no seasonal component; some Earth Engine assets deprecated |
| Climatic / transmission strata | NMCP facies definitions; Köppen or bioclimatic zones; MAP *Pf* prevalence | Needed for RQ4. **Get NMCP's own facies definition** — auditing their criterion requires their categories |

---

## 6. Methods

**Friction surface.** Reclassify land cover, road class/surface, slope, and hydrology into per-pixel traversal costs; separate surfaces for motorised and walking modes. Apply Tobler's hiking function for slope-corrected walking. Include waterway crossings and ferry/pirogue segments explicitly.

**Seasonal variants.** Two surfaces per mode — dry and wet — differing in the traversal cost of unpaved roads and in flood-affected pixels. **This is your assumption, not observed data.** Parameterise it transparently, sensitivity-test the penalty multipliers, and report results as a range rather than a point estimate.

**Least-cost accumulation.** Anisotropic cumulative-cost from origins to destinations. AccessMod 5 is the WHO-endorsed route and gives reviewer comfort; `terra`/`gdistance` in R or the `traveltime` package give more control and reproducibility. Pick one and justify it — a lean, scripted pipeline you can re-run is worth more here than GUI output you cannot version.

**RQ2/RQ3 computation.** OD matrix is small and within-province (each DPS → its own site(s)), so 11, 26, and 52 pairs respectively. Report travel time, network distance, Euclidean distance, and the **friction ratio** (travel time per straight-line km) — that ratio is a better figure than raw distance and turns Output 3 from a standalone objective into an interpretive contrast.

**RQ4 computation.** For each configuration, compute travel time from every populated pixel to the nearest sentinel site; summarise population within 1/2/4/8 h bands; cross-tabulate strata against site presence. Report which strata are unrepresented under each configuration.

**Validation.** Collect even 20–30 reported real trip durations from DPS supervision staff and compare against modelled times. Accessibility papers are routinely criticised for being unvalidated; a small ground-truth set materially strengthens the manuscript for very little effort.

---

## 7. The time-series trap — read before building Output 1

Computing the 11-site configuration on a 2026 road network is anachronistic: the network, OSM's coverage of it, and land cover have all changed since 2010. A genuine historical time series would need contemporaneous friction surfaces, which do not exist for DRC.

**Fix:** hold the friction surface constant and vary only site configuration. Then 11 / 26 / 52 are **counterfactual scenarios on a common baseline**, not a historical trend. Say this explicitly in the Methods. It is defensible, it is arguably more interpretable, and it pre-empts the reviewer comment that would otherwise force a major revision.

---

## 8. Planned figures and tables

| # | Content | Serves |
|---|---|---|
| Fig 1 | DRC provinces with 11 / 26 / 52 site configurations, three panels | RQ1 |
| Fig 2 | National travel-time surface to nearest sentinel site — motorised and walking × dry and wet, 4 panels | RQ2 |
| Fig 3 | DPS→site travel time by province: dumbbell or slope plot, dry vs wet | RQ2 |
| Fig 4 | Friction ratio (travel time per Euclidean km) by province, mapped | RQ3 |
| Fig 5 | Cumulative population coverage curves by travel time, one line per configuration × season | RQ4 |
| Fig 6 | Strata × configuration heatmap showing represented / unrepresented strata | RQ4 |
| Table 1 | Per-province: DPS, site name, coordinates, year established, travel time and distance by mode and season | RQ1–RQ3 |
| Table 2 | Configuration summary: n sites, median travel time, % population within bands, n strata covered | RQ4 |

Fig 5 and Fig 6 are the ones that make this a paper. Fig 1 alone is a poster.

---

## 9. Limitations to state up front

- Modelled travel times are unvalidated except against a small convenience sample; they represent feasible, not observed, journeys.
- Seasonal penalties are assumption-driven; no DRC-specific calibration exists for wet-season road impassability or river navigability.
- OSM road completeness varies geographically across DRC; coverage gaps bias travel times upward in under-mapped areas.
- Configurations are counterfactual scenarios on a fixed 2026 friction surface, not a historical time series (§7).
- One sentinel site per DPS is a coarse instrument in a country with 516 health zones and multiple transmission facies per province; the representativeness analysis quantifies this limitation rather than resolving it.
- n = 26 origin–destination pairs precludes inferential statistics on RQ2/RQ3; those results are descriptive.

---

## 10. Target outlets

**Journals** — in rough order of fit:

- *International Journal of Health Geographics* — the natural home; publishes AccessMod and DRC accessibility work
- *Malaria Journal* — right audience if the entomological framing leads
- *PLOS Global Public Health* / *BMJ Global Health* — if the surveillance-policy framing leads
- *Geospatial Health* — faster, lower barrier, reasonable fallback
- *PLOS Neglected Tropical Diseases* — where the closest methodological precedent sits (Longbottom et al. 2020)

**Conferences:** MIM Pan-African Malaria Conference; ASTMH; ECTMIH. Fig 1 + Fig 5 + Fig 6 make a coherent poster well before the manuscript is ready.

---

## 11. Assumptions to pressure-test before sharing

**Resolved:**

- ~~"NCMP"~~ → **NMCP** (National Malaria Control Programme / PNLP). `proposal.qmd` uses NMCP correctly; the WhatsApp spelling is a transposition. Standardise on NMCP throughout.

**Open — with Victoire:**

1. **Scope.** National three-output study vs the Kasaï-Central proposal — replacement, companion, or poster? (§0) Nothing else can be planned until this is settled.
2. **Why DPS as origin?** Is DPS→site travel time actually decision-relevant, or is supervision delegated in practice to health-zone level (BCZS)? If the latter, the origin should change and the whole OD matrix changes with it. Ask what a real supervision visit looks like.
3. **What flows along this route?** Supervision visits, specimen transport to INRB, or data/reporting? Each implies a different metric, a different frequency, and a different cost model. Name it.
4. **Does the 52-site list exist?** Georeferenced, or only as intent? If 52 = 2 per DPS, that is administrative symmetry, and the paper's most useful contribution becomes proposing an alternative 52 chosen for strata coverage rather than for tidiness.
5. **Whose strata definition?** Auditing the programme's representativeness claim requires the programme's own facies categories. Obtain them, don't substitute Köppen zones and hope.
6. **Season definition.** Dry/wet windows vary substantially across DRC's latitudinal span — a single national calendar will be wrong. Define per-province from CHIRPS climatology.

**Open — with NMCP:**

7. **Data sharing and authorship.** Sentinel site coordinates and establishment dates come from NMCP. Agree access terms and authorship expectations before analysis, not after.
8. **Ethics.** Confirm whether a secondary-data geospatial analysis requires INRB/ethics clearance; a validation survey of DPS staff trip times probably does.

**Open — technical:**

9. **GRID3 coverage gap.** v01 covers 5 of 26 provinces. Identify the blended national source for health-area boundaries and facilities, and report its completeness honestly.
10. **Waterways.** Confirm whether the friction surface will include river transport. Omitting it is a substantive error in the Congo Basin, not a rounding issue.

**Corrections needed in existing project files:**

11. `references.bib` — `alegana2020accessibility` is **misattributed**. The correct citation is Longbottom J, Krause A, Torr SJ, Stanton MC (2020), *PLOS Neglected Tropical Diseases* 14(3):e0008096, doi:10.1371/journal.pntd.0008096 — published, not a 2019 bioRxiv preprint. Fix before any circulation.
12. `proposal.qmd` §Study setting — internal inconsistencies: text says **25** health zones, Table 1 lists **26** (summing correctly to 442 health areas), Fig 2 caption says **466** health areas. Reconcile.
13. `proposal.qmd` — three instances of "the Victoire's" (find-replace artifact from "the candidate's"), and mixed gender reference ("his PhD"). Fix before sharing.

---

## 12. Immediate next actions

1. Settle §0 scope with Victoire — one call, before any analysis.
2. Request the georeferenced sentinel site register (all three configurations + establishment years) and the NMCP facies definitions.
3. Build a single-province proof of concept end to end — one DPS, one site, motorised + walking, dry + wet — to expose the pipeline's real problems cheaply.
4. Fix the three file corrections in §11 (11–13).
5. Draft Fig 1 from whatever site coordinates already exist; it is the cheapest possible check that the data will support the story.

---

## References cited in this outline

- Longbottom J, Krause A, Torr SJ, Stanton MC (2020). Quantifying geographic accessibility to improve efficiency of entomological monitoring. *PLOS Negl Trop Dis* 14(3):e0008096.
- Mbunga BK, Liu PY, Bangelesa F, et al. (2024). Predicting zero-dose children in the DRC using geospatial accessibility. *Vaccines* 12(6):617.
- Pu Q, Yoo E-H, Rothstein DH, Cairo S, Malemo L (2020). Improving the spatial accessibility of healthcare in North Kivu, DRC. *Applied Geography* 121:102281.
- Mukomena Sompwe E, et al. (2024). Complexity of vector control and entomological surveillance in endemic sentinel sites of the NMCP in the DRC. IntechOpen.
- Makanga PT, Schuurman N, Sacoor C, et al. (2017). Seasonal variation in geographical access to maternal health services. *Int J Health Geogr* 16:1.
- Ouma P, Ray N, Ebener S, et al. (2020). Improving geographical accessibility modeling for operational use by local health actors. *Int J Health Geogr* 19:1.
- Weiss DJ, Nelson A, Vargas-Ruiz CA, et al. (2020). Global maps of travel time to healthcare facilities. *Nat Med* 26:1835–1838.
- Ray N, Ebener S (2008). AccessMod 3.0. *Int J Health Geogr* 7:63.
- Polgreen PM, et al. (2013). How many suffice? Sizing sentinel surveillance networks. *Int J Health Geogr* 12:56.
- Geldsetzer P, Reinmuth M, Ouma PO, et al. (2020). Mapping physical access to healthcare in sub-Saharan Africa. *Lancet Healthy Longev* 1(1):e32–e42.
