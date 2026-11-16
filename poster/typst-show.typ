#show: doc => poster(
$if(title)$
  title: [$title$],
$endif$
$if(by-author)$
  authors: (
$for(by-author)$
    (name: [$it.name.literal$], marks: ($for(it.affiliations)$"$it.number$", $endfor$)),
$endfor$
  ),
$endif$
$if(affiliations)$
  affiliations: (
$for(affiliations)$
    (mark: "$it.number$", name: [$it.name$]),
$endfor$
  ),
$endif$
$if(poster.programme)$
  programme: [$poster.programme$],
$endif$
$if(poster.key-message)$
  key-message: [$poster.key-message$],
$endif$
$if(poster.logo)$
  logo: "$poster.logo$",
$endif$
$if(poster.footer)$
  footer: (
$for(poster.footer)$
    (label: [$it.label$], logos: ($for(it.logos)$"$it$", $endfor$)),
$endfor$
  ),
$endif$
$if(poster.references-size)$
  references-size: $poster.references-size$,
$endif$
$if(poster.contact)$
  contact: [$poster.contact$],
$endif$
$if(poster.width)$
  width: $poster.width$,
$endif$
$if(poster.height)$
  height: $poster.height$,
$endif$
$if(poster.size)$
  size: "$poster.size$",
$endif$
$if(poster.orientation)$
  orientation: "$poster.orientation$",
$endif$
$if(poster.columns)$
  cols: $poster.columns$,
$endif$
$if(mainfont)$
  font: ("$mainfont$",),
$endif$
$if(lang)$
  lang: "$lang$",
$endif$
$if(region)$
  region: "$region$",
$endif$
  doc,
)
