# Lessons

- **Typst's own bibliography is unreliable here.** Quarto 1.9.38 escapes underscores in the `.bib` path (`ecr\_final\_report.bib`, file not found), and Hayagriva prints BibTeX `and others` as "others". Fix: for Typst output use `citeproc: true` with a CSL file, as `ecr_poster.qmd` does.
- **Vancouver lowercases unprotected proper nouns** in BibTeX titles (Pandoc sentence-cases them). Brace-protect them in the `.bib`; braces leave the report's Chicago output unchanged.
- **CSL styles repo raw URLs can 404.** Fetch styles from `https://www.zotero.org/styles/<name>` instead.
- **The scratchpad is cleared when a session restarts.** A chained `cp` from it failed, and the check that followed read the wrong PDF. Keep anything worth comparing at the repo root with a suffix (`ecr_poster_portrait_3col.pdf`), and check which file a check reads.
