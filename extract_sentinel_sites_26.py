#!/usr/bin/env python3
"""
Build the 26-site DRC malaria entomological sentinel network as a two-column CSV
(province, sentinel_site), harmonised onto the post-2015 26-province vocabulary.

Source blocks (sheet 'Metadata')
-------------------------------
  A3:B13   the original 11 sites (established 2003, operational 2005), labelled
           with PRE-2015 province names, 7 of which no longer exist.
  D3:E17   the 15 sites added November 2014 after the 11->26 decoupage.
           This block is a DELTA, not a full list: 11 + 15 = 26.
  G3:G28   used for PROVINCE SPELLINGS ONLY -- the workbook's own list of the
           26 post-2015 provinces. Its sentinel sites (the Oct 2021 / 52-site
           proposal) are deliberately NOT read.

Harmonisation
-------------
The two site blocks are written in different province vocabularies, so stacking
them verbatim yields 26 rows but only 25 distinct province strings -- 'Kasai
Oriental' would appear twice meaning two different geographies. Each of the
original 11 sites is therefore relabelled with the post-2015 province it sits in,
via CROSSWALK_2015 below.

CROSSWALK_2015 IS DERIVED FROM GEOGRAPHY, NOT FROM THE WORKBOOK. It is the one
piece of outside knowledge here, and it is what to review first. It is guarded by
a strong structural test: the 11 relabelled provinces must be disjoint from the
15 added provinces, and their union must equal the workbook's own 26. Any single
wrong assignment breaks closure (it creates a duplicate and a gap) and the script
exits non-zero.

Usage
-----
    python3 extract_sentinel_sites_26.py [--workbook X.xlsx] [--out Y.csv]
    python3 extract_sentinel_sites_26.py --audit     # show provenance per row

By default the CSV is written straight to geocoding/input/, where the geocoding
pipeline reads it. --audit output goes beside this script instead.
"""

from __future__ import annotations

import argparse
import csv
import sys
import unicodedata
from pathlib import Path

try:
    import openpyxl
except ImportError:  # pragma: no cover
    sys.exit("openpyxl is required: pip install openpyxl")

SHEET = "Metadata"

# (province col, site col, first row, last row, expected count, label)
BLOCK_11 = (1, 2, 3, 13, 11, "original 11 (2003/2005)")
BLOCK_15 = (4, 5, 3, 17, 15, "added Nov 2014")
CANON_COL, CANON_FIRST, CANON_LAST, CANON_N = 7, 3, 28, 26

# Post-2015 province for each of the original 11 sites, keyed by the site name as
# spelled in the workbook. Values MUST match the workbook's own G-column spelling.
# ---- REVIEW THIS TABLE FIRST: it is geographic inference, not sourced data. ----
CROSSWALK_2015 = {
    "Bolenge":    "Equateur",       # near Mbandaka; old Equateur -> new Equateur
    "Kabondo":    "Tshopo",         # health zone in Kisangani; old Province Orientale
    "Kalima":     "Maniema",        # province unchanged
    "Katana":     "Sud-Kivu",       # province unchanged
    "Kapolowe":   "Haut-Katanga",   # near Likasi; old Katanga
    "Kimpese":    "Kongo-Central",  # Bas Congo renamed, boundaries unchanged
    "Kingasani":  "Kinshasa",       # province unchanged
    "Mikalayi":   "Kasai-Central",  # near Kananga; old Kasai Occidental
    "Mwene-ditu": "Lomami",         # Mwene-Ditu city; old Kasai Oriental
    "Rutshuru":   "Nord-Kivu",      # province unchanged
    "Vanga":      "Kwilu",          # Bagata territory; old Bandundu
}

FIELDNAMES = ["province", "sentinel_site"]
AUDIT_FIELDNAMES = ["province", "sentinel_site", "province_source", "source_cells", "block"]


def collapse(value) -> str:
    return "" if value is None else " ".join(str(value).split())


def fold(text: str) -> str:
    """Accent-, case- and separator-insensitive key for matching province spellings."""
    stripped = "".join(
        ch for ch in unicodedata.normalize("NFKD", text) if not unicodedata.combining(ch)
    )
    return stripped.strip().lower().replace(" ", "-")


def read_grid(workbook: Path):
    wb = openpyxl.load_workbook(workbook, read_only=True, data_only=True)
    try:
        if SHEET not in wb.sheetnames:
            raise KeyError(f"sheet {SHEET!r} not found; workbook has {wb.sheetnames}")
        ws = wb[SHEET]
        grid = list(ws.iter_rows(min_row=1, max_row=CANON_LAST, max_col=CANON_COL,
                                values_only=True))
    finally:
        wb.close()
    if len(grid) < CANON_LAST:
        raise ValueError(f"sheet has {len(grid)} rows, need at least {CANON_LAST}")
    return grid


def read_canonical(grid) -> dict[str, str]:
    """The workbook's own 26 post-2015 province names, as {folded_key: spelling}."""
    names = [collapse(grid[r - 1][CANON_COL - 1])
             for r in range(CANON_FIRST, CANON_LAST + 1)]
    blanks = [CANON_FIRST + i for i, n in enumerate(names) if not n]
    if blanks:
        raise ValueError(f"blank province in canonical list at rows {blanks}")
    lookup = {fold(n): n for n in names}
    if len(lookup) != CANON_N:
        raise ValueError(
            f"canonical list has {len(lookup)} distinct provinces, expected {CANON_N}"
        )
    return lookup


def read_block(grid, block) -> list[dict]:
    prov_col, site_col, first, last, expected, label = block
    rows, problems = [], []
    for r in range(first, last + 1):
        province = collapse(grid[r - 1][prov_col - 1])
        site = collapse(grid[r - 1][site_col - 1])
        if not province and not site:
            problems.append(f"row {r}: both cells blank")
        elif not province:
            problems.append(f"row {r}: blank province (site {site!r})")
        elif not site:
            problems.append(f"row {r}: blank sentinel site (province {province!r})")
        else:
            rows.append({
                "province_source": province,
                "sentinel_site": site,
                "source_cells": f"{chr(64 + prov_col)}{r}:{chr(64 + site_col)}{r}",
                "block": label,
            })
    if problems:
        raise ValueError(f"{label} block has gaps:\n  - " + "\n  - ".join(problems))
    if len(rows) != expected:
        raise ValueError(f"{label} block: expected {expected} rows, read {len(rows)}")
    return rows


def harmonise(rows_11, rows_15, canon: dict[str, str]) -> list[dict]:
    errors = []

    for row in rows_11:
        site = row["sentinel_site"]
        target = CROSSWALK_2015.get(site)
        if target is None:
            errors.append(f"no CROSSWALK_2015 entry for original site {site!r} "
                          f"({row['province_source']!r}, {row['source_cells']})")
            continue
        match = canon.get(fold(target))
        if match is None:
            errors.append(f"CROSSWALK_2015 maps {site!r} to {target!r}, which is not "
                          f"one of the workbook's 26 provinces")
            continue
        row["province"] = match

    extra = sorted(set(CROSSWALK_2015) - {r["sentinel_site"] for r in rows_11})
    if extra:
        errors.append(f"CROSSWALK_2015 has entries for sites absent from the "
                      f"11-block: {extra}")

    for row in rows_15:
        match = canon.get(fold(row["province_source"]))
        if match is None:
            errors.append(f"added-site province {row['province_source']!r} "
                          f"({row['source_cells']}) is not one of the workbook's 26")
            continue
        row["province"] = match

    if errors:
        raise ValueError("harmonisation failed:\n  - " + "\n  - ".join(errors))
    return rows_11 + rows_15


def validate(rows: list[dict], canon: dict[str, str], n_original: int) -> None:
    errors = []
    provinces = [r["province"] for r in rows]

    if len(rows) != CANON_N:
        errors.append(f"expected {CANON_N} rows, built {len(rows)}")

    dupes = sorted({p for p in provinces if provinces.count(p) > 1})
    if dupes:
        errors.append(f"province appears more than once (breaks 1 site/province): {dupes}")

    canonical = set(canon.values())
    missing = sorted(canonical - set(provinces))
    unexpected = sorted(set(provinces) - canonical)
    if missing:
        errors.append(f"provinces from the workbook's 26 with no site: {missing}")
    if unexpected:
        errors.append(f"provinces not in the workbook's 26: {unexpected}")

    # Structural guard on CROSSWALK_2015: the two blocks must not collide.
    overlap = sorted(set(provinces[:n_original]) & set(provinces[n_original:]))
    if overlap:
        errors.append(f"relabelled original sites collide with added sites in: "
                      f"{overlap} -- a CROSSWALK_2015 assignment is wrong")

    sites = [r["sentinel_site"] for r in rows]
    dupe_sites = sorted({s for s in sites if sites.count(s) > 1})
    if dupe_sites:
        errors.append(f"duplicate sentinel site names: {dupe_sites}")

    if errors:
        raise ValueError("validation failed:\n  - " + "\n  - ".join(errors))


def main() -> int:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workbook", type=Path,
                    default=here / "DRC_Health_Zones_Sentinel_Sites.xlsx")
    ap.add_argument("--out", type=Path,
                    help="default: the geocoding pipeline's input CSV; with "
                         "--audit, drc_sentinel_sites_26_audit.csv beside this script")
    ap.add_argument("--audit", action="store_true",
                    help="also emit province_source / source_cells / block columns")
    args = ap.parse_args()

    # Audit columns must never land in the pipeline input by default.
    if args.out is None:
        args.out = (here / "drc_sentinel_sites_26_audit.csv" if args.audit
                    else here / "geocoding" / "input" / "drc_sentinel_sites_26.csv")

    if not args.workbook.is_file():
        print(f"ERROR: workbook not found: {args.workbook}", file=sys.stderr)
        return 2

    try:
        grid = read_grid(args.workbook)
        canon = read_canonical(grid)
        rows_11 = read_block(grid, BLOCK_11)
        rows_15 = read_block(grid, BLOCK_15)
        rows = harmonise(rows_11, rows_15, canon)
        validate(rows, canon, len(rows_11))
    except (ValueError, KeyError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    rows.sort(key=lambda r: (fold(r["province"]), fold(r["sentinel_site"])))
    fields = AUDIT_FIELDNAMES if args.audit else FIELDNAMES

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore",
                                quoting=csv.QUOTE_MINIMAL)
        writer.writeheader()
        writer.writerows(rows)

    print(f"OK  {len(rows)} sites -> {args.out}")
    print(f"    {len(rows_11)} original + {len(rows_15)} added Nov 2014")
    print(f"    {len(set(r['province'] for r in rows))} distinct provinces, "
          f"set-equal to the workbook's own 26; blocks disjoint")
    return 0


if __name__ == "__main__":
    sys.exit(main())
