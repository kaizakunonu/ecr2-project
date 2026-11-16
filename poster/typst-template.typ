// Poster layout for Quarto's Typst format, used by ecr_poster.qmd.
// Tested with Quarto 1.9.38 (Typst 0.14).
//
// Size, orientation and column count come from the `poster:` block in the qmd.
// Every length below is multiplied by `s` (paper size relative to A0), so the
// design keeps its proportions at any paper size.

#let poster-paper = (
  a0: (841mm, 1189mm),
  a1: (594mm, 841mm),
  a2: (420mm, 594mm),
  a3: (297mm, 420mm),
  a4: (210mm, 297mm),
)

// MAP palette, taken from the MAP slide template.
#let poster-gold = rgb("#EBBC40")
#let poster-ink = rgb("#1F1F1F")
#let poster-dark = rgb("#383838")
#let poster-tint = rgb("#F3F4F2")
#let poster-accent = rgb("#E64823")

// A row of headline numbers. Sized in em, so it scales with the poster.
//   #key-stats(title: [...], ("10.3%", [11 sites]), ("22.9%", [26 sites]))
#let key-stats(title: none, ..items) = block(
  width: 100%,
  fill: poster-tint,
  inset: (x: 0.8em, y: 0.75em),
  radius: 0.25em,
  breakable: false,
  {
    if title != none {
      block(below: 0.9em, text(weight: "bold", title))
    }
    grid(
      columns: (1fr,) * items.pos().len(),
      column-gutter: 0.6em,
      row-gutter: 0.55em,
      align: center,
      ..items.pos().map(((value, label)) => text(size: 2.3em, weight: "bold", value)),
      ..items.pos().map(((value, label)) => text(size: 0.8em, label)),
    )
  },
)

// Start a new column here, but only when the poster has `cols` columns, so one
// qmd can carry breaks for several layouts:
//   ```{=typst}
//   #poster-colbreak(3)
//   ```
#let poster-ncols = state("poster-ncols", none)
#let poster-colbreak(cols) = context {
  if poster-ncols.get() == cols { colbreak() }
}

// Logos are scaled to a common area, so wide wordmarks and square seals carry
// similar visual weight.
#let poster-logo(path, area, max-height) = context {
  let natural = measure(image(path))
  let aspect = natural.width / natural.height
  let h = calc.min(calc.sqrt(area / aspect), max-height / 1mm) * 1mm
  image(path, height: h)
}

#let poster(
  title: none,
  authors: (),
  affiliations: (),
  programme: none,
  key-message: none,
  logo: none,
  footer: (),
  contact: none,
  size: "a0",
  orientation: "portrait",
  width: none,
  height: none,
  cols: auto,
  font: ("Liberation Sans", "Arial"),
  lang: "en",
  region: "GB",
  references-size: 0.9em,
  doc,
) = {
  // ---- page geometry -------------------------------------------------------
  let dims = if width != none and height != none {
    (width, height)
  } else {
    assert(
      size in poster-paper,
      message: "poster.size must be one of " + poster-paper.keys().join(", ")
        + ", or set poster.width and poster.height",
    )
    poster-paper.at(size)
  }
  assert(
    orientation in ("portrait", "landscape"),
    message: "poster.orientation must be portrait or landscape",
  )
  let short = calc.min(..dims)
  let long = calc.max(..dims)
  let (pw, ph) = if orientation == "landscape" { (long, short) } else { (short, long) }
  // Scale to the largest A-series proportions that fit, so squarer papers
  // (36 x 48 in, say) get slightly smaller type and never a shorter column.
  let s = calc.min(short / 841mm, long / 1189mm)
  let mm = 1mm * s
  let pt = 1pt * s
  let ncols = if cols == auto { if pw > ph { 4 } else { 2 } } else { cols }

  // ---- footer: labelled logo groups and a contact line ---------------------
  let has-footer = footer.len() > 0 or contact != none
  let foot-height = if has-footer { 50 * mm } else { 0mm }
  let foot = if has-footer {
    set text(size: 18 * pt)
    line(length: 100%, stroke: 1.2 * pt + poster-gold)
    v(5 * mm, weak: true)
    grid(
      columns: footer.map(_ => auto) + (1fr,),
      column-gutter: 20 * mm,
      align: top,
      ..footer.map(group => {
        text(fill: poster-accent, group.label)
        v(4 * mm, weak: true)
        grid(
          columns: group.logos.len(),
          column-gutter: 10 * mm,
          align: horizon,
          ..group.logos.map(p => poster-logo(p, 1150 * s * s, 30 * mm))
        )
      }),
      align(right, if contact != none {
        text(fill: poster-accent)[Contact]
        v(4 * mm, weak: true)
        contact
      }),
    )
  }

  set document(title: title, author: authors.map(a => content-to-string(a.name)))
  set page(
    width: pw,
    height: ph,
    margin: (x: 30 * mm, top: 28 * mm, bottom: 26 * mm + foot-height),
    footer-descent: 9 * mm,
    footer: foot,
  )
  set text(font: font, size: 26 * pt, fill: poster-ink, lang: lang, region: region)
  set par(leading: 0.6em, spacing: 0.95em, justify: false)

  // ---- element styles ------------------------------------------------------
  show heading.where(level: 1): it => block(
    width: 100%,
    fill: poster-gold,
    inset: (x: 7 * mm, y: 4.5 * mm),
    above: 11 * mm,
    below: 7 * mm,
    sticky: true,
    text(size: 33 * pt, weight: "bold", it.body),
  )
  show heading.where(level: 2): it => block(
    above: 8 * mm,
    below: 5 * mm,
    sticky: true,
    text(size: 28 * pt, weight: "bold", it.body),
  )
  set list(indent: 0pt, body-indent: 0.55em, spacing: 0.75em, marker: box(
    baseline: -0.22em,
    square(size: 0.34em, fill: poster-dark),
  ))
  set enum(indent: 0pt, body-indent: 0.55em, spacing: 0.75em)
  set figure(gap: 0.55em)
  show figure: set block(breakable: false)
  show figure.caption: it => align(left, text(size: 0.74em, it))
  // Reference list: the qmd's ::: {#refs} div, filled by Pandoc's citeproc.
  show <refs>: set text(size: references-size)
  show <refs>: set par(leading: 0.5em, spacing: 0.8em)

  // ---- header: gold title block, logo on the right -------------------------
  let title-block = block(
    width: 100%,
    fill: poster-gold,
    inset: (x: 13 * mm, y: 12 * mm),
    {
      block(below: 13 * mm, {
        set par(leading: 25 * pt)
        text(size: 66 * pt, weight: "bold", title)
      })
      if authors.len() > 0 {
        block(below: 7 * mm, text(size: 34 * pt, weight: "bold", authors
          .map(a => a.name + if a.marks.len() > 0 { super(a.marks.join(",")) })
          .join(", ")))
      }
      if affiliations.len() > 0 {
        set text(size: 21 * pt)
        set par(leading: 9 * pt)
        block(affiliations.map(a => super(a.mark) + [ ] + a.name).join(linebreak()))
      }
    },
  )
  let side = align(horizon, {
    if logo != none {
      image(logo, width: 100%)
    }
    if programme != none {
      v(7 * mm, weak: true)
      set text(size: 23 * pt)
      set par(leading: 0.5em)
      programme
    }
  })
  if logo != none or programme != none {
    grid(
      columns: (1fr, 200 * mm),
      column-gutter: 16 * mm,
      title-block, side,
    )
  } else {
    title-block
  }

  if key-message != none {
    v(8 * mm, weak: true)
    block(
      width: 100%,
      fill: poster-dark,
      inset: (x: 13 * mm, y: 9 * mm),
      text(size: 34 * pt, weight: "bold", fill: white, key-message),
    )
  }

  v(4 * mm, weak: true)
  poster-ncols.update(ncols)
  columns(ncols, gutter: 24 * mm, doc)
}
