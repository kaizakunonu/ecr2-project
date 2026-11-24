# Lessons

- **Typst's own bibliography is unreliable here.** Quarto 1.9.38 escapes underscores in the `.bib` path (`ecr\_final\_report.bib`, file not found), and Hayagriva prints BibTeX `and others` as "others". Fix: for Typst output use `citeproc: true` with a CSL file, as `ecr_poster.qmd` does.
- **Vancouver lowercases unprotected proper nouns** in BibTeX titles (Pandoc sentence-cases them). Brace-protect them in the `.bib`; braces leave the report's Chicago output unchanged.
- **CSL styles repo raw URLs can 404.** Fetch styles from `https://www.zotero.org/styles/<name>` instead.
- **Quote `#| code: !expr` values that contain `#` or `: `.** Unquoted, YAML reads ` #` as a comment (the chunk silently shows the truncated call) and `: ` as a mapping (render error). Fix: wrap the whole expression in single quotes, `#| code: !expr 'f("a: b", "# c")'`.
- **Quarto 1.9.38's *Show All Code* opens nothing.** Its handler selects `.cell > details > .sourceCode`, but every fold now wraps the code in `.code-copy-outer-scaffold` (and in `.code-with-filename` with `filename:`). Fix: a small `include-after-body` script that toggles all `details.code-fold`, as in `workflow_demo.qmd`.
- **`quarto render x.qmd --output-dir D` moves the output, it doesn't copy it.** It renders beside the source, then moves the file to `D`, so a tracked `ecr_poster.pdf` vanished from the repo. Fix: back up first, then restore it after a test render (or `git checkout` it).
- **The scratchpad is cleared when a session restarts.** A chained `cp` from it failed, and the check that followed read the wrong PDF. Keep anything worth comparing at the repo root with a suffix (`ecr_poster_portrait_3col.pdf`), and check which file a check reads.
