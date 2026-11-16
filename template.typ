// Layout of the Musicus technical documentation. One source, two outputs;
// the PDF is the primary format, the HTML page is a convenient second one:
//   typst compile --font-path fonts main.typ musicus-technical.pdf
//   typst compile --features html --font-path fonts main.typ musicus-technical.html
// Same visual language as the user guide (fonts, colours, callouts), tuned
// for reading on paper: justified text, running headers, decision cards.

#import "@preview/fletcher:0.5.8" as fletcher: node, edge

#let accent = rgb("#2f5bd3")
#let accent-soft = rgb("#eef3ff")
#let navy = rgb("#1b2a55")
#let ink = rgb("#1d2433")
#let muted = rgb("#5d6677")
#let rule = luma(218)
#let why-color = rgb("#b7791f")
#let mono = "DejaVu Sans Mono"  // embedded in typst, so the PDF looks the same everywhere

#let is-html() = target() == "html"

// True on the title and contents pages (no header, footer or page number).
#let front-matter = state("front-matter", true)

// --- Diagrams --------------------------------------------------------------------

/// fletcher's `diagram`; in HTML it is embedded as an SVG frame.
/// In the PDF a diagram wider than the text column is scaled down to fit.
#let diagram(..args) = context {
  let d = fletcher.diagram(..args)
  if is-html() { html.frame(d) } else {
    layout(region => {
      let w = measure(d).width
      if w > region.width { scale(region.width / w * 100%, reflow: true, d) } else { d }
    })
  }
}

/// Shared node style for diagrams.
#let box-node(pos, label, fill: white, ..args) = node(
  pos,
  label,
  stroke: 0.7pt + navy.lighten(35%),
  fill: fill,
  corner-radius: 4pt,
  inset: 7pt,
  ..args,
)

// --- Callouts ----------------------------------------------------------------------

#let callout-style = (
  why: (title: "Why?", color: why-color, symbol: "?"),
  note: (title: "Note", color: accent, symbol: "i"),
)

#let callout(kind, body, title: none) = context {
  let s = callout-style.at(kind)
  let heading = if title == none { s.title } else { title }
  if is-html() {
    html.elem("div", attrs: (class: "callout callout-" + kind))[
      #html.elem("p", attrs: (class: "callout-title"))[#heading]
      #body
    ]
  } else {
    block(
      width: 100%,
      fill: s.color.lighten(92%),
      stroke: (left: 2.5pt + s.color),
      radius: (right: 4pt),
      inset: (x: 11pt, y: 9pt),
      above: 1.1em,
      below: 1.1em,
      breakable: true,
    )[
      #set par(justify: false)
      #grid(
        columns: (15pt, 1fr),
        column-gutter: 8pt,
        align(center, circle(
          radius: 7pt,
          fill: s.color,
          align(center + horizon, text(fill: white, weight: "bold", size: 8.5pt, s.symbol)),
        )),
        [#text(weight: "bold", fill: s.color.darken(25%), heading) \ #body],
      )
    ]
  }
}

/// Explains *why* something is done the way it is, next to the component it
/// concerns. Long-form reasoning lives in the Decisions chapter.
#let why(body) = callout("why", body)

/// A neutral hint.
#let note(body) = callout("note", body)

/// One architecture decision record.
#let decision(situation, choice, reasons, consequences) = context {
  let rows = (
    ("Context", situation),
    ("Decision", choice),
    ("Why", reasons),
    ("Consequences", consequences),
  )
  if is-html() {
    html.elem("div", attrs: (class: "decision"))[
      #for (label, body) in rows {
        html.elem("div", attrs: (class: "decision-row" + if label == "Decision" { " chosen" } else { "" }))[
          #html.elem("p", attrs: (class: "decision-label"))[#label]
          #html.elem("div", attrs: (class: "decision-body"))[#body]
        ]
      }
    ]
  } else {
    block(
      width: 100%,
      stroke: 0.6pt + rule,
      radius: 5pt,
      clip: true,
      // A record reads as one unit; all of them fit on half a page.
      breakable: false,
      above: 0.8em,
      below: 1.4em,
    )[
      #set par(justify: false)
      #for (i, (label, body)) in rows.enumerate() {
        let chosen = label == "Decision"
        block(
          width: 100%,
          fill: if chosen { accent-soft } else { white },
          stroke: if i > 0 { (top: 0.6pt + rule) } else { none },
          inset: (x: 10pt, y: 7pt),
          above: 0pt,
          below: 0pt,
          breakable: true,
          grid(
            columns: (7.4em, 1fr),
            column-gutter: 8pt,
            text(size: 7.5pt, weight: "bold", tracking: 0.06em, hyphenate: false, fill: if chosen { accent } else { muted }, upper(label)),
            body,
          ),
        )
      }
    ]
  }
}

// --- HTML stylesheet -----------------------------------------------------------------

#let css = ```
:root {
  --accent: #2f5bd3; --accent-soft: #eef3ff; --ink: #1d2433; --muted: #5d6677;
  --bg: #f6f7f9; --surface: #ffffff; --border: #dde1e8; --code: #f0f2f5;
  --why: #b7791f; --note: #2f5bd3;
  color-scheme: light;
}
@media (prefers-color-scheme: dark) {
  :root {
    --accent: #8fb0ff; --accent-soft: #1c2640; --ink: #e6e9ee; --muted: #a2abba;
    --bg: #12151a; --surface: #1a1e25; --border: #2e3540; --code: #232933;
    --why: #f0b75e; --note: #8fb0ff;
    color-scheme: dark;
  }
  /* Diagrams are drawn for a light background. */
  figure svg { background: #fff; border-radius: 10px; }
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; scroll-padding-top: 1.5rem; }
body {
  margin: 0; background: var(--bg); color: var(--ink);
  font: 16.5px/1.65 "Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
.layout { display: grid; grid-template-columns: 19rem minmax(0, 1fr); min-height: 100vh; }
aside {
  position: sticky; top: 0; height: 100vh; overflow-y: auto; padding: 1.6rem 1.2rem 2rem;
  background: var(--surface); border-right: 1px solid var(--border); font-size: 0.88rem;
}
aside .brand { font-weight: 800; font-size: 1.2rem; color: var(--accent); margin: 0; }
aside .brand-sub { color: var(--muted); font-size: 0.8rem; margin: 0 0 1rem; }
aside nav h2 { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); margin: 0 0 0.6rem; border: none; padding: 0; }
aside nav ol { padding-left: 0.2rem; margin: 0; list-style: none; }
aside nav ol ol { padding-left: 1.1rem; margin: 0.15rem 0 0.4rem; }
aside nav li { margin: 0.15rem 0; }
aside nav a { color: var(--ink); text-decoration: none; display: block; padding: 0.1rem 0.4rem; border-radius: 6px; }
aside nav a:hover { background: var(--accent-soft); color: var(--accent); }
aside nav .prefix { color: var(--muted); margin-right: 0.35rem; font-variant-numeric: tabular-nums; }
main { padding: 0 3rem 6rem; max-width: 62rem; margin: 0 auto; width: 100%; }
.hero {
  margin: 0 -3rem 2.5rem; padding: 3.2rem 3rem 2.6rem; color: #fff;
  background:
    radial-gradient(rgba(255,255,255,0.12) 1px, transparent 1.2px) 0 0 / 18px 18px,
    linear-gradient(135deg, #16224a, #2f5bd3);
}
.hero .eyebrow { font-size: 0.85rem; letter-spacing: 0.15em; text-transform: uppercase; margin: 0; opacity: 0.8; }
.hero .title { font-size: 2.6rem; font-weight: 800; margin: 0.3rem 0 0.2rem; letter-spacing: -0.02em; }
.hero .subtitle { font-size: 1.15rem; margin: 0; opacity: 0.92; }
.hero .version { font-size: 0.88rem; margin: 1rem 0 0; opacity: 0.75; }
h2 { font-size: 1.85rem; margin: 3.2rem 0 0.8rem; letter-spacing: -0.01em; padding-top: 1.2rem; border-top: 1px solid var(--border); }
h3 { font-size: 1.28rem; margin: 2.2rem 0 0.5rem; }
h4 { font-size: 1.05rem; margin: 1.6rem 0 0.4rem; }
a { color: var(--accent); }
p { margin: 0.6rem 0; }
code { background: var(--code); padding: 0.1em 0.35em; border-radius: 4px; font-size: 0.86em; font-family: ui-monospace, "DejaVu Sans Mono", monospace; }
pre { background: #1d2433; color: #e8ecf3; padding: 1rem 1.2rem; border-radius: 10px; overflow-x: auto; font-size: 0.84rem; line-height: 1.5; }
pre code { background: none; padding: 0; color: inherit; }
ol, ul { padding-left: 1.5rem; }
li { margin: 0.25rem 0; }
table { border-collapse: collapse; width: 100%; margin: 1rem 0; font-size: 0.9rem; background: var(--surface); border-radius: 10px; overflow: hidden; box-shadow: 0 0 0 1px var(--border); }
th, td { text-align: left; padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--border); vertical-align: top; }
tr:first-child td { font-weight: 700; background: var(--accent-soft); }
tr:last-child td { border-bottom: none; }
figure { margin: 1.8rem 0; text-align: center; }
figure svg { max-width: 100% !important; height: auto !important; padding: 0.6rem; }
figcaption { color: var(--muted); font-size: 0.86rem; margin-top: 0.6rem; }
.callout { margin: 1.3rem 0; padding: 0.85rem 1.1rem 0.85rem 1.2rem; border-radius: 10px; border-left: 4px solid; background: var(--surface); box-shadow: 0 0 0 1px var(--border); }
.callout-title { font-weight: 700; margin: 0 0 0.25rem; }
.callout-why { border-color: var(--why); } .callout-why .callout-title { color: var(--why); }
.callout-note { border-color: var(--note); } .callout-note .callout-title { color: var(--note); }
.callout > :last-child { margin-bottom: 0; }
.decision { margin: 1rem 0 1.8rem; border: 1px solid var(--border); border-radius: 10px; overflow: hidden; background: var(--surface); }
.decision-row { display: grid; grid-template-columns: 9rem minmax(0, 1fr); gap: 1rem; padding: 0.6rem 1rem; border-top: 1px solid var(--border); }
.decision-row:first-child { border-top: none; }
.decision-row.chosen { background: var(--accent-soft); }
.decision-label { margin: 0.15rem 0 0; font-size: 0.72rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }
.decision-row.chosen .decision-label { color: var(--accent); }
.decision-body > :first-child { margin-top: 0; } .decision-body > :last-child { margin-bottom: 0; }
@media (max-width: 980px) {
  .layout { display: block; }
  aside { position: static; height: auto; border-right: none; border-bottom: 1px solid var(--border); padding: 1rem 1.2rem; }
  aside nav ol ol { display: none; }
  main { padding: 0 1.2rem 4rem; }
  .hero { margin: 0 -1.2rem 2rem; padding: 2.4rem 1.2rem 2rem; }
  .decision-row { grid-template-columns: 1fr; gap: 0.2rem; }
}
@media print { aside { display: none; } .layout { display: block; } }
.license { margin: 4rem 0 0; padding-top: 1.2rem; border-top: 1px solid var(--border); color: var(--muted); font-size: 0.85rem; }
```

// --- Document setup --------------------------------------------------------------------

// --- License notice (PDF title page and end of the HTML page) -------------------

#let doc-license-url = "https://creativecommons.org/licenses/by-sa/4.0/"
#let app-license-url = "https://www.gnu.org/licenses/agpl-3.0.html"
#let source-url = "https://github.com/Musicus-Sheets/Musicus"
#let license-notice(kind) = [
  © 2026 the Musicus contributors.
  This #kind is licensed under the
  #link(doc-license-url)[Creative Commons Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0)].
  Musicus itself is free software, licensed under the
  #link(app-license-url)[GNU Affero General Public License, version 3 (AGPL-3.0)].
  Source code: #box(link(source-url, source-url.trim("https://", at: start))).
]

#let project(title: "", subtitle: "", version: "", body) = {
  set document(title: title + " – technical documentation")
  set text(font: ("Inter", "Noto Sans", "DejaVu Sans"), size: 10pt, fill: ink, lang: "en")
  set heading(numbering: "1.1")
  show link: set text(fill: accent)
  show ref: set text(fill: accent)
  set list(marker: text(fill: accent, "•"), indent: 0.3em)
  set enum(numbering: n => text(fill: accent, weight: "bold", str(n) + "."), indent: 0.2em)
  set raw(theme: none)
  // Typst shrinks raw text to 0.8em; bring it back close to the body size.
  show raw: set text(font: mono, size: 1.1em)
  show raw.where(block: true): it => context {
    if is-html() { it } else {
      block(
        width: 100%,
        fill: rgb("#1d2433"),
        radius: 5pt,
        inset: (x: 11pt, y: 9pt),
        above: 1em,
        below: 1em,
        text(fill: rgb("#e8ecf3"), size: 8pt, it),
      )
    }
  }
  show raw.where(block: false): it => context {
    if is-html() { it } else {
      box(fill: luma(240), inset: (x: 2.5pt), outset: (y: 2.2pt), radius: 2.5pt, it)
    }
  }
  set table(
    stroke: none,
    inset: (x: 7pt, y: 5.5pt),
    fill: (_, y) => if y == 0 { accent-soft } else if calc.odd(y) { white } else { luma(248.5) },
  )
  show table.cell.where(y: 0): set text(weight: "bold")
  show figure.caption: it => context {
    if is-html() { it } else {
      text(size: 8.5pt, fill: muted)[#text(weight: "bold", fill: ink)[#it.supplement #context it.counter.display(it.numbering)]#it.separator#it.body]
    }
  }

  context if is-html() {
    html.elem("style", css.text)
    html.elem("div", attrs: (class: "layout"))[
      #html.elem("aside")[
        #html.elem("p", attrs: (class: "brand"))[𝄞 Musicus]
        #html.elem("p", attrs: (class: "brand-sub"))[Technical documentation]
        #outline(title: [Contents], depth: 2)
      ]
      #html.elem("main")[
        #html.elem("header", attrs: (class: "hero"))[
          #html.elem("p", attrs: (class: "eyebrow"))[Technical documentation]
          #html.elem("p", attrs: (class: "title"))[#title]
          #html.elem("p", attrs: (class: "subtitle"))[#subtitle]
          #html.elem("p", attrs: (class: "version"))[#version]
        ]
        #body
        #html.elem("footer", attrs: (class: "license"))[#license-notice("documentation")]
      ]
    ]
  } else {
    set par(justify: true, leading: 0.68em, spacing: 1em)
    set text(hyphenate: true)
    // Short tables stay on one page; long ones may break.
    show table: it => if it.children.len() <= 40 { block(breakable: false, it) } else { it }
    show table: set par(justify: false)
    show figure: set block(above: 1.4em, below: 1.4em)
    show figure.where(kind: image): it => {
      set par(justify: false)
      it
    }

    set page(
      paper: "a4",
      margin: (inside: 2.4cm, outside: 2.1cm, top: 2.5cm, bottom: 2.3cm),
      header: context {
        // No header in the front matter and on pages where a chapter starts.
        let starts = query(heading.where(level: 1)).any(h => h.location().page() == here().page())
        if not front-matter.get() and not starts {
          set text(7.5pt, fill: muted)
          let chapter = query(selector(heading.where(level: 1)).before(here()))
          let name = if chapter.len() > 0 {
            let c = chapter.last()
            if c.numbering != none { numbering("1", ..counter(heading).at(c.location())) + h(5pt) }
            c.body
          }
          let left = [#text(fill: accent, weight: "bold", "𝄞 Musicus") #h(4pt) Technical documentation]
          grid(columns: (1fr, auto), left, name)
          v(-4pt)
          line(length: 100%, stroke: 0.4pt + rule)
        }
      },
      footer: context {
        if not front-matter.get() {
          set text(8pt, fill: muted)
          let n = counter(page).get().first()
          let total = counter(page).final().first()
          align(center)[#text(weight: "bold", fill: ink, str(n)) #h(2pt) / #h(2pt) #total]
        }
      },
    )

    show heading.where(level: 1): it => {
      pagebreak(weak: true)
      v(1.1cm)
      block(below: 1.2em, width: 100%)[
        #set par(justify: false)
        #if it.numbering != none {
          text(size: 10pt, weight: "bold", fill: accent, tracking: 0.14em, upper("Chapter " + counter(heading).display("1")))
          linebreak()
        }
        #text(size: 25pt, weight: "extrabold", fill: ink, it.body)
        #v(-0.35em)
        #line(length: 3cm, stroke: 3pt + accent)
      ]
    }
    show heading.where(level: 2): it => block(above: 1.9em, below: 0.8em, sticky: true)[
      #set par(justify: false)
      #text(size: 13.5pt, weight: "bold", fill: navy)[
        #text(fill: accent)[#counter(heading).display(it.numbering)] #h(5pt) #it.body
      ]
    ]
    show heading.where(level: 3): it => block(above: 1.5em, below: 0.6em, sticky: true, text(size: 11pt, weight: "bold", it))

    // Title page
    page(margin: 0pt, header: none, footer: none)[
      #set par(justify: false)
      #set text(hyphenate: false)
      #place(top, rect(width: 100%, height: 64%, fill: gradient.linear(rgb("#16224a"), accent, angle: 35deg)))
      // Dot grid, like graph paper.
      #place(top, dx: 0pt, dy: 0pt, block(width: 100%, height: 64%, clip: true, {
        for row in range(0, 44) {
          for col in range(0, 32) {
            place(dx: col * 0.68cm + 0.3cm, dy: row * 0.68cm + 0.3cm, circle(radius: 0.6pt, fill: white.transparentize(84%)))
          }
        }
      }))
      #place(top + right, dx: -1.6cm, dy: 2.2cm, text(size: 150pt, fill: white.transparentize(84%), "𝄞"))
      #place(top + left, dx: 2.4cm, dy: 7.4cm)[
        #text(size: 12pt, fill: white.transparentize(20%), weight: "medium", tracking: 0.16em, "TECHNICAL DOCUMENTATION")
        #v(0.2cm)
        #text(size: 54pt, weight: "extrabold", fill: white, title)
        #v(0.1cm)
        #block(width: 13cm, text(size: 15pt, fill: white.transparentize(10%), subtitle))
      ]
      #place(bottom + left, dx: 2.4cm, dy: -3cm)[
        #set text(fill: muted)
        #let chip(name) = box(
          stroke: 0.6pt + navy.lighten(40%),
          fill: accent-soft,
          inset: (x: 6pt, y: 3.5pt),
          radius: 4pt,
          text(font: mono, size: 9pt, fill: navy, name),
        )
        #grid(columns: 3, column-gutter: 7pt, chip("musicus-api"), chip("musicus-server"), chip("musicus-web"))
        #v(0.45cm)
        #text(size: 10pt, version)
      ]
      #place(bottom + left, dx: 2.4cm, dy: -1.2cm, block(width: 100% - 2 * 2.4cm, text(size: 7.5pt, fill: muted, license-notice("documentation"))))
    ]
    // Contents (may span several pages)
    [
      #text(size: 22pt, weight: "extrabold")[Contents]
      #v(0.2cm)
      #line(length: 3cm, stroke: 3pt + accent)
      #v(0.5cm)
      #set par(justify: false)
      #show outline.entry.where(level: 1): it => {
        v(0.75em)
        text(weight: "bold", it)
      }
      #outline(title: none, depth: 2, indent: 1.6em)
    ]
    pagebreak()
    front-matter.update(false)
    counter(page).update(1)
    body
  }
}
