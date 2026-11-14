// Layout and helper elements of the Musicus technical documentation.

#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#let accent = rgb("#2f5bd3")

#let project(title: "", subtitle: "", version: "", body) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (x: 2.2cm, y: 2.4cm),
    numbering: "1",
    header: context {
      if counter(page).get().first() > 2 {
        set text(8pt, fill: luma(110))
        [#title #h(1fr) #version]
      }
    },
  )
  set text(size: 10.5pt, lang: "en")
  set par(justify: true, leading: 0.62em)
  set heading(numbering: "1.1")
  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    v(0.4em)
    text(19pt, fill: accent, it)
    v(0.5em)
  }
  show heading.where(level: 2): it => { v(0.4em); it; v(0.15em) }
  show raw.where(block: false): box.with(fill: luma(240), inset: (x: 2pt), outset: (y: 2.5pt), radius: 2pt)
  show raw.where(block: true): block.with(fill: luma(246), inset: 8pt, radius: 3pt, width: 100%)
  set raw(theme: none)
  set table(stroke: 0.5pt + luma(185), inset: 5.5pt)
  show table.cell.where(y: 0): set text(weight: "bold")
  show figure.caption: set text(9pt, fill: luma(80))
  show figure.where(kind: image): set text(8.5pt)
  show link: set text(fill: accent)

  // Title page
  page(numbering: none, header: none)[
    #v(1fr)
    #text(32pt, weight: "bold", fill: accent)[#title]
    #v(0.3em)
    #text(15pt)[#subtitle]
    #v(1.5em)
    #text(10pt, fill: luma(90))[#version]
    #v(2fr)
  ]
  page(numbering: none, header: none, outline(depth: 2, indent: auto))
  counter(page).update(1)
  body
}

/// Box explaining *why* something is done the way it is, next to the
/// component it concerns. Long-form reasoning lives in the Decisions chapter.
#let why(body) = block(
  fill: rgb("#fff8e6"),
  stroke: (left: 3pt + rgb("#d99a00")),
  inset: (x: 10pt, y: 8pt),
  width: 100%,
  breakable: true,
)[#text(weight: "bold")[Why?] #body]

/// A neutral hint box.
#let note(body) = block(
  fill: rgb("#eef3ff"),
  stroke: (left: 3pt + accent),
  inset: (x: 10pt, y: 8pt),
  width: 100%,
  breakable: true,
)[#body]

/// One architecture decision record.
#let decision(situation, choice, reasons, consequences) = {
  table(
    columns: (7.5em, 1fr),
    stroke: none,
    inset: (x: 0pt, y: 4pt),
    [*Context*], situation,
    [*Decision*], choice,
    [*Why*], reasons,
    [*Consequences*], consequences,
  )
}

// Shared node style for diagrams.
#let box-node(pos, label, fill: luma(248), ..args) = node(
  pos, label, stroke: 0.7pt + luma(90), fill: fill, corner-radius: 3pt, inset: 7pt, ..args,
)
