#import "../template.typ": *

= System view <system-view>

*Purpose:* on a small tablet a whole A4 page shrinks the staves to 2--4 mm.
The system view shows instead as many *whole music systems* as fit at a
minimum staff height chosen by the musician, cropped to the width of the
music, and continues across page boundaries: a view may show the end of
page 1 and the beginning of page 2. A system is never cut. Requirements:
F-READ-003, R-READ-010 to R-READ-019, R-PERF-008; decision
@d-system-layout.

The work is split in three places:

#table(
  columns: (auto, 1fr),
  [Unit], [Purpose],
  [`musicus-server::layout`], [Detects staves, systems and cut lines on every page of an uploaded PDF, once per file, in a background worker (`detect`, `worker`, `analyse_pdf`).],
  [`musicus-api::layout`], [The layout types sent to clients, the reading sequence (`reading_items`) and the view planner (`plan_views`), shared by server tests and the web client.],
  [`musicus-web` reader], [Plans the views for its screen, renders only the needed crops with pdf.js, draws the annotation layers on each crop, turns views.],
)

#figure(
  diagram(
    spacing: (9mm, 8mm),
    box-node((0, 0), [upload \ (`store_upload`)], name: <up>),
    box-node((2, 0), [layout worker \ one file at a time], name: <worker>, fill: rgb("#eef3ff")),
    box-node((4, 0), [`file_layouts` \ (JSON per file)], name: <db>),
    box-node((4, 1.4), [`GET /api/files/` \ `{sha}/layout`], name: <get>),
    box-node((2, 1.4), [`reading_items` \ `plan_views`], name: <plan>, fill: rgb("#eef3ff")),
    box-node((0, 1.4), [reader: crops via \ pdf.js + ink], name: <reader>, fill: rgb("#fff8e6")),
    edge(<up>, <worker>, "->", [notify]),
    edge(<worker>, <db>, "->", [analyse]),
    edge(<db>, <get>, "->"),
    edge(<get>, <plan>, "->", [layout]),
    edge(<plan>, <reader>, "->", [views]),
  ),
  caption: [From an upload to the system view.],
)

== Detection on the server

The detection runs once per file. Files are immutable and content-addressed
(@d-blobs), so the result never becomes stale. A background worker
(`layout::worker`) takes the newest file that has no layout, or a layout of
an older `ALGORITHM_VERSION`, analyses it on a blocking thread and stores
the result in `file_layouts`. An upload wakes the worker; after a start it
works through all older files (backfill). Requests never wait for it: until
a file is analysed its layout is `pending` and the reader shows whole pages.
A file hayro cannot read gets state `failed`.

Each page is rendered in greyscale with hayro at 150 dpi (`RENDER_DPI`), but
never larger than an A4 page at that resolution (`MAX_LONG_SIDE_PX` = 1754
pixels on the long side): facsimiles often declare huge page sizes, and the
detection only needs pixels per staff line distance.

#note[In the following, $t$ is the thickness of a staff line and $d$ the
line distance (centre to centre) in pixels; "spaces" are multiples of $d$.
Every constant is named in `layout/detect.rs`; the agent documentation
(`docs/agents/layout.md`) lists the same names.]

=== Steps

+ *Binarise.* Otsu threshold of the grey histogram, clamped to 60..210
  (`OTSU_MIN`, `OTSU_MAX`). Ink = darker than the threshold.
+ *Measure.* Histograms of vertical runs (every second column): the most
  frequent black run length in 1..19 is $t$; the most frequent sum of a black
  run and the following white run (smoothed over three bins) in 4..149 is $d$.
+ *Deskew.* "Thin" ink lies in vertical runs of at most
  $max(2t + 1, t + 3)$ pixels. The skew angle $alpha$ maximises the sum of
  squares of the row histogram of thin pixels after shifting each by
  $(x - w\/2) tan alpha$: first $plus.minus 3 degree$ in steps of
  $0.1 degree$, then $plus.minus 0.1 degree$ around the best in steps of $0.01 degree$.
  Below $0.02 degree$ nothing is done; otherwise every column is shifted
  (vertical shear).
+ *Line evidence.* Ink in horizontal runs of at least
  $max(1.5 d, 8)$ pixels, gaps of one pixel closed (`LONG_RUN_*`). Staff
  lines remain long runs through note heads and stems; text does not.
+ *Staves per strip.* The page is cut into vertical strips of $8 d$
  (32 px to a quarter of the width). In a strip, rows that are at least
  half covered by line evidence form line candidates (a run of at most $3$
  thin-run heights; strength = peak coverage). Candidate pairs $(i, l)$ with
  spacing $g = (y_l - y_i) \/ 4$ between $max(0.4 d, 3"px")$ and $2.5 d$
  form a five-line group if lines 1--3 lie at $y_i + k g$ within
  $max(0.2 g, 1.5"px")$; one inner line may be missing (dense passages). A
  group is rejected if its weakest line is below 0.45 of its median
  strength, or if other candidates lie in the middle of two or more of its
  gaps (it would take every other line of two close staves -- the main
  error on a hand-ruled manuscript). A sixth line of at least 0.7 relative
  strength adds a six-line (guitar tablature) group. Groups are chosen by
  total strength, without overlaps.
+ *Staves.* Groups are linked from left to right into tracks: same line
  count, at most 4 strips apart, top line within $0.6 g$, spacing within
  $0.2 g$. Broken tracks of the same staff are merged. A staff must span at
  least $12 d$. A six-line staff whose spacing is less than 1.25 times that
  of the page's normal staves is a staff plus a ledger line and loses its
  weaker outer line. The exact left and right end of each staff is found
  column by column (all lines but one inked, gaps up to $0.6 d$ bridged).
+ *Systems.* Two neighbouring staves belong to one system if the rows
  between them are inked in at least 90 % of the rows within $3 d$ left and
  $1 d$ right of their left end (system barline, brace, bracket), or if one
  narrow column anywhere covers 97 % of those rows (a barline, e.g. after an
  incipit). Without such a connection every staff is its own system (parts).
+ *Cuts between systems.* On the row ink profile of the music's width (plus
  $2 d$), a row is ink-free with at most 0.4 % of the width inked. The cut
  between two systems lies in the middle of the longest ink-free run between
  them, so dynamics, tempo marks, lyrics and rehearsal marks stay with their
  system. Without an ink-free row the row with least ink is taken; it counts
  as "unclean" if more than 2 % of the width is inked there.
+ *Header and footer.* Above the first and below the last system, ink-free
  runs score $"length" \/ (1 + "distance to the staff" \/ 8 d)$; runs
  touching the page edge (or a scanner border) only count if there is no
  other. Ink above the cut is the header (title, composer), below it the
  footer (copyright, page number). Ink that starts within $4 d$ below the
  last staff (an 8vb line, low notes) stays with the last system, up to the
  next ink-free run of $1 d$ (`FOOTER_ATTACH_SPACES`).
+ *Regions.* Bands are contiguous; each carries cut lines, ink extent,
  horizontal extent (systems: from $12 d$ left of the staves for instrument
  names and braces to $6 d$ right, for text after the last barline), staff count and the smallest line
  distance. With skew, the band is the bounding box of the slanted band.
+ *Confidence.* Starts at 1 and is multiplied by penalties:

#table(
  columns: (1fr, auto),
  [Finding], [Factor],
  [No staff but ink on the page (text, title page)], [confidence 0.2],
  [Each unclean cut (at most 3)], [0.85],
  [Three or more staff-like lines far ($> 7 d$) from the staves of a system (missed staff)], [0.5],
  [Otherwise, more than $2 d$ of dense ink far from the staves of a system], [0.9],
  [Each system whose staff count differs from the page median (at most 3)], [0.8],
  [A staff narrower than 85 % of the widest in its system], [0.7 per system],
  [A staff's line distance more than 30 % off the page median], [0.9],
  [Skew above $1.5 degree$], [0.9],
)

A page with confidence below 0.6 (`CONFIDENCE_MIN`) or without systems is
marked `full_page`: the system view shows it whole.

#why[A greyscale projection is enough for printed and scanned music and costs
23--112 ms per page including rendering on one laptop core (about four times
that on a Raspberry Pi 4). Optical music recognition would need large models
and still fail on manuscripts. On 23 real scores (parts, lead sheets,
piano, dense old prints, a full score and a Bach manuscript) the prototype
found the systems of 82 of 84 music pages correctly, flagged one
unreliable page and failed unflagged on one, which the footer rule above
now fixes.]

== Reading sequence

`reading_items` turns the pages into one sequence of *items* (crops):

- a page marked `full_page`, or without systems, is one `Page` item (the whole page);
- every system is a `System` item, cropped vertically to its ink plus one
  line distance, clamped to its cut lines, horizontally to its ink extent;
- the header of the first page (title block) and headers or footers taller
  than 6 % of the page (`TALL_TEXT`; verses, a new movement's title) are
  `Text` items; other headers and footers (running heads, page numbers,
  copyright lines) and bands marked hidden are skipped.

The staff height of a system on paper is $4 times "staff_space" times$ page height.

== Views

The client knows its screen in CSS pixels ($W times H$, the stage minus 8 px)
and assumes 132 CSS pixels per inch (`CSS_PX_PER_MM` = 5.197; iPad, most
8--11" Android tablets have 120--160): browsers do not report the real
density. The staff size setting gives the minimum staff height $m$:
S = 5 mm, M = 6 mm, L = 7 mm, XL = 8 mm (default M).

The detected systems only decide *where a view starts and where it ends*.
What the reader shows is always the original page: on every page a view
touches it shows *one contiguous crop* -- from the top of the first item on
that page to the bottom of the last one, with everything in between (the
space between the systems, text, bands that are hidden or small headers and
footers lying between shown systems). Hidden and skipped bands only matter at
the start and the end of a view. A stroke drawn across several systems
therefore stays straight, and the view looks like the sheet.

For the whole document (scales in CSS px per mm of paper):

$ "fit"_w = W / (x_1 - x_0) quad
  "needed" = (m dot "CSS_PX_PER_MM") / (min "staff height on paper") quad
  s = min("needed", "fit"_w) $

where $[x_0, x_1]$ (mm) is the union of the horizontal extents of all system
and text items of the document. Every view uses this one horizontal range and
this one scale $s$, so consecutive views neither change size nor move
sideways. Music wider than the screen at the minimum height is shown at full
width (`below_min`).

The height of a candidate view of items $a..e$ is the sum over the pages it
touches of the height of its crop on that page (from the first item's top to
the last item's bottom, gaps included).

#[
  #set enum(numbering: "1.")
  + A view starts at item $a$. A `Page` item is always alone, fitted whole.
  + The view grows while the next item is not a `Page` item and
    $"height" dot s <= H$.
  + A view does not end with a title (a `Text` item followed by music on the
    same page, or in the upper half of its page); the title moves on.
  + A single item taller than the screen at $s$ is scaled down to fit.
  + *Next view* (user decision): if the view holds at least three systems
    (`OVERLAP_MIN_SYSTEMS`), the next view starts with its last system (one
    system overlap, so the eye finds its place); with one or two systems it
    starts after the last item. A view that would only repeat the
    overlapped system is skipped.
]

A view that continues on the next page stacks two crops directly below each
other (end of page $n$, start of page $n+1$), separated only by a 1-pixel
hairline; a stroke cannot continue across that line, because it belongs to
another page.

#why[The first version stitched one crop per system, removed the space
between them, gave each a shadow and enlarged every view to fill the screen.
Musicians found that lines drawn over several systems jumped at every system
boundary, the views changed size and position, and the patchwork no longer
looked like their sheet. One contiguous crop per page and one scale per
document fix all three (decision a-contiguous-view in the agent
documentation); the price is that the space between systems is shown, so
slightly fewer systems fit.]

The reading position is the first item of the current view. When the views
are planned again -- the tablet is turned, the window resized, the staff
size changed -- the reader shows the last view that starts at or before that
item, so the music the musician was reading stays on screen. Switching from
the page view starts at the first item of the current page; switching back
shows the page of the view's first item.

#figure(
  diagram(
    spacing: (6mm, 5mm),
    box-node((0, 0), [view 1: \ systems 1--5], name: <v1>, fill: rgb("#eef3ff")),
    box-node((2, 0), [view 2: \ systems 5--9 \ (page 1 → 2)], name: <v2>, fill: rgb("#eef3ff")),
    box-node((4, 0), [view 3: \ systems 9--13], name: <v3>, fill: rgb("#eef3ff")),
    edge(<v1>, <v2>, "->", [next]),
    edge(<v2>, <v3>, "->", [next]),
  ),
  caption: [Five systems per view: the last system of a view is the first of the next, also across a page boundary.],
)

== Reader

The reader keeps one mode switch (`☰ Systems`) and, in the system view, the
staff size (S, M, L, XL) in the reader bar. Both are stored per user on the
server (`PUT /api/auth/reader-settings`, part of `/api/auth/me`): the web
client keeps nothing on the device (R4).

For the current view the reader shows one canvas per page segment (one,
or two at a page boundary), without shadows or borders between systems and
one shadow around the whole view. Each crop is
rendered by pdf.js directly as a crop: the viewport is offset by the crop's
corner and scaled to the crop's on-screen width, at the device pixel ratio,
into an off-screen canvas that is cached (24 crops). After a view is shown,
the crops of the next view are rendered into the cache, so a page turn shows
a finished image.

Annotations stay in page coordinates. Each page segment has its own ink canvas; its
`PageBox` holds the page size on screen and the crop's offset, and the canvas
is translated by the offset, so strokes are drawn, erased and stored exactly
as in the page view (R-ANN-005, R-ANN-012). Undo acts on the page last drawn on.

Keys, pedals, taps and swipes turn views; before the first and after the
last view the previous or next piece of a programme opens, as in the page
view. A programme loads the layouts of all its sheets together with the
sheets, so the system view needs no network on stage.

While a file is `pending` or `failed`, or its page count differs from the
PDF, the reader shows whole pages with a short note.

== Corrections by librarians

The detection can be wrong on unusual layouts. A librarian opens
#strong[Edit part → Edit systems] and sees each page with its bands. A band
can be split (a new cut line in its middle, then dragged), two bands joined
by removing the cut between them, a cut line moved by dragging (or with the
arrow keys), the kind of a band set to system, header, footer or hidden, and
a page marked to be shown whole.

A correction is stored per file and page (`layout_corrections`) as the
complete list of cut lines and band kinds, and applied whenever the layout is
served: per band, the horizontal extent and the ink come from the detected
bands it overlaps, the staff count and staff size from the detected systems
it overlaps (so the minimum staff size still works). The detection never
touches corrections, so they survive a new detection run; a new file
version starts uncorrected. A correction applies to every member, because
all of them read the same file. `PUT` and `DELETE` on
`/api/files/{sha256}/layout/pages/{page}` are for librarians only.

== Limits

- Splitting one system into halves at a barline (for music wider than the
  screen) is a later proposal (R-READ-017); today such music is shown at full
  width, which on an 8" tablet in landscape means about 0.9--1.0 times the
  printed staff size.
- One-line percussion staves are not detected; ossia staves and two short
  systems side by side were not tested. Footnotes below the last system are
  attached to it.
- The millimetre sizes are exact only at 132 CSS pixels per inch.
