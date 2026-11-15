#import "../template.typ": *

= Web client `musicus-web` <client>

*Purpose:* the user interface for musicians, librarians and admins. It is a
single-page application written with Dioxus 0.7, compiled to WebAssembly,
and served as static files by the server. It talks to the server only
through the REST API. It keeps no data on the device (R4).

== Sub units

#table(
  columns: (auto, 1fr),
  [Unit], [Purpose],
  [`main`], [Start-up, the route table (`Route`), the `Session` context (who is logged in), the global stylesheet.],
  [`ui`], [The page frame `Shell` (navigation, login guard), the role helpers `can_manage`/`is_admin`, and small shared helpers (error box, date formatting, `confirm`/`prompt` dialogs).],
  [`api`], [HTTP client for the REST API: JSON helpers, binary upload, annotation page load and save, error mapping.],
  [`bridge` + `js/bridge.js`], [Everything browsers offer only in JavaScript: pdf.js rendering, the in-memory sheet cache, the wake lock, fullscreen, clipboard, and sending unsaved annotations when the tab closes.],
  [`ink`], [Draws annotation layers on a canvas, converts between page and pixel coordinates, hit-tests the eraser.],
  [`pages::login`, `account`], [Login, invite acceptance, password change, device list.],
  [`pages::library`, `programmes`, `instruments`], [Score list with search and thumbnails; concert programmes with prefetch; the instrument list. For librarians and admins the same pages carry the management controls.],
  [`pages::score_edit`, `programme_edit`, `forms`], [Editors opened from those pages: the guided flow for a new piece, the edit views of a piece and of a part (with PDF upload and versions), the programme editor, and the form pieces they share.],
  [`pages::groups`, `users`], [Groups with members and grants (librarians and admins); user accounts with invite links (admins).],
  [`pages::viewer`], [The sheet reader with drawing tools and annotation sets.],
)

#figure(
  diagram(
    spacing: (10mm, 9mm),
    box-node((1.5, 0), [`main` \ `Route`, `Session`], name: <main>),
    box-node((1.5, 1), [`ui::Shell`], name: <shell>),
    box-node((0, 2), [`library`, `programmes`, \ `instruments`, editors, \ `groups`, `users`, …], name: <pages>, fill: rgb("#eef3ff")),
    box-node((3, 2), [`viewer`], name: <viewer>, fill: rgb("#eef3ff")),
    box-node((0, 3.3), [`api`], name: <api>),
    box-node((1.5, 3.3), [`bridge` (Rust)], name: <bridge>),
    box-node((3, 3.3), [`ink`], name: <ink>),
    box-node((1.5, 4.4), [`js/bridge.js`], name: <js>, fill: rgb("#fff8e6")),
    box-node((0.5, 5.4), [pdf.js \ (+ worker)], name: <pdfjs>, fill: rgb("#fff8e6")),
    box-node((2.5, 5.4), [browser APIs \ wake lock, fetch], name: <browser>, fill: rgb("#fff8e6")),
    box-node((-1.4, 4.4), [REST API \ (server)], name: <server>, stroke: (dash: "dashed", paint: luma(90))),
    edge(<main>, <shell>, "->", [layout routes]),
    edge(<main>, (3, 0), <viewer>, "->", [full-screen routes], label-side: left),
    edge(<shell>, <pages>, "->"),
    edge(<pages>, <api>, "->"),
    edge(<pages>, <bridge>, "->", [prefetch]),
    edge(<viewer>, <api>, "->", label-pos: 0.3),
    edge(<viewer>, <bridge>, "->"),
    edge(<viewer>, <ink>, "->"),
    edge(<bridge>, <js>, "->", [wasm-bindgen]),
    edge(<js>, <pdfjs>, "->"),
    edge(<js>, <browser>, "->"),
    edge(<api>, (0, 4.4), <server>, "->", [fetch]),
  ),
  caption: [Units of the web client. Yellow: JavaScript.],
)

== Start-up and navigation: `main` and `ui`

`main` launches the Dioxus app. The root component asks `/api/auth/me` once
and stores the result in the `Session` context (`user`, and `checked` once
the answer arrived). All pages read the logged-in user from this context.

The `Route` enum maps URLs to page components. Most routes render inside
`ui::Shell` (navigation bar); the reader routes (`/parts/:id` and
`/programmes/:pid/parts/:id`) render full-screen without it. `Shell`
redirects to `/login` when the session check found no user. Its navigation
shows Library, Programmes and Instruments to everyone, Groups to librarians
and admins, and Users to admins.

There is no separate management area (@d-inline-management): the library,
programme and instrument pages ask `ui::can_manage()` and add their
controls ("Add piece", "Edit" on pieces and parts, "New programme", "Edit"
on a programme, instrument editing) for librarians and admins; the editors
have their own routes such as `/scores/new`, `/scores/:id/edit`,
`/parts/:id/edit` and `/programmes/:id/edit`. Old `/manage` links redirect
to the library. The server also enforces every permission; hiding controls
is only convenience.

== Server access: `api`

All requests go through a few helpers (`get`, `post`, `put`, `patch`,
`call`, `upload`). Each request:

- sends the CSRF header `x-musicus-csrf` (the browser adds the session
  cookie by itself);
- turns a non-2xx answer into `ApiErr` with the server's message;
- on 401 reloads the browser at `/login`. The full reload is deliberate: it
  discards all in-memory state of the previous session.

Two functions handle the binary annotation pages: `get_page` (returns the
bytes and the revision from the `ETag`, or "missing" for HTTP 204) and
`put_page` (sends `If-Match: "<revision>"` and reports `Saved(revision)` or
`Conflict`).

== JavaScript bridge: `bridge` and `js/bridge.js`

`bridge.rs` declares the JavaScript functions with `wasm-bindgen` and gives
them typed Rust signatures; `bridge.js` implements them. `dx` bundles the JS
file with the WebAssembly module.

#table(
  columns: (auto, 1fr),
  [Function], [Purpose],
  [`prefetch(url)`], [Downloads a sheet into an in-memory map (url → bytes) unless it is there already. The download starts when the function is called, not when the Rust future is polled, so several prefetches run in parallel.],
  [`pageCount`, `renderPage`], [Open the cached bytes with pdf.js (in a Web Worker) and render one page as large as fits the given box, at device pixel ratio. Rendering goes to an off-screen canvas first, so the visible page never flashes blank; an older render of the same canvas is cancelled.],
  [`retainOnly(urls)`], [Frees cached sheets not in the list (called when another programme is opened).],
  [`setPending`, `clearPending`], [Keep a copy of every unsaved annotation page. On `pagehide` (tab closed, reload) they are sent with `fetch(..., {keepalive: true})`, which browsers complete even while the page unloads.],
  [`keepAwake`, `toggleFullscreen`, `copyText`], [Screen wake lock (re-acquired after tab switches), fullscreen, clipboard.],
)

#why[
  PDF pages are rendered by pdf.js through this bridge, not by a Rust
  renderer compiled to WebAssembly. pdf.js is the most widely tested PDF
  renderer for browsers; the pure-Rust alternative would add 1.1--1.7 MB to
  the download and is still young. The *legacy* build of pdf.js is shipped
  because the current one needs JavaScript features older tablets lack.
  See @d-pdf-rendering.
]

#why[
  Downloaded sheets are held in a JavaScript `Map` in memory, not in
  IndexedDB or the Cache API, and the server sends `Cache-Control:
  no-store` by default. Nothing stays on the device after the tab closes
  (R4); the prefetch still makes page turns independent of the Wi-Fi. See
  @d-no-client-storage.
]

== Drawing: `ink`

`PageBox` is the size of the displayed page in CSS pixels and converts
between page coordinates (0--65535) and pixels. `draw_layer` clears the ink
canvas and draws a whole layer: highlighter strokes first, then pen
strokes, stamps and text, so pen marks stay on top. Pen width varies with
the recorded pressure. `hit` returns the ids of all objects within the
eraser radius of a point. `new_id` creates random 64-bit object ids.

== Pages

=== Library and programmes

`library` loads `/api/scores` (with the search term, debounced by 150 ms)
and shows each score with its readable parts and their thumbnails.
`programmes` lists concerts; opening one loads the programme and starts
downloading all its sheets through `bridge::prefetch`, three at a time,
with a progress display. Parts opened from a programme use the programme
reader route, so the reader knows the previous and next piece.

=== Reader (`viewer`)

The reader is the most involved page. It has three layers stacked in the
`stage` element: the PDF canvas (`page-canvas`), the ink canvas
(`ink-canvas`) on top, and the toolbars. Its parts:

#table(
  columns: (auto, 1fr),
  [Part], [Responsibility],
  [Loading], [`ViewerPage` loads the part, its score, the user's annotation sets and (if opened from a programme) the programme. `choose_set` picks the set linked to the programme, else the default set.],
  [Rendering], [Effects re-render the PDF page whenever the file, the page number or the available size changes (`onresize` of the stage).],
  [Annotation store], [A `Store` of `PageState` per (set, page): the layer, the server revision it is based on, the object ids of that revision (`base_ids`, for merging), and change counters (`generation`, `saved_generation`). It also keeps undo and redo stacks.],
  [Saving], [`save_page` sends a dirty page with `If-Match`; on conflict it fetches the server version, merges with `ink::merge` and retries (up to five times). Changes are saved 1.5 s after the last one, immediately on page turns, and when the reader closes.],
  [Input], [Pointer events on the ink canvas. While a stroke is drawn, segments go directly to the canvas; the stroke becomes an object on `pointerup`. Once a pen was seen, touch input is ignored (palm rejection). Keyboard and foot pedals arrive through a small `eval` script that forwards `keydown` events.],
  [Navigation], [Tap zones (left and right third), arrow and page keys. Turning past the last page opens the next piece of the programme.],
  [Sets], [Create, duplicate, rename, make default, link to the programme, delete, and move to a new file version.],
)

#why[
  The annotation store is an `Rc<RefCell<Store>>` outside Dioxus' signal
  system. Saving must outlive the component: when the user leaves the
  reader, pending pages are still flushed by a task started with
  `spawn_forever`, which must not touch signals of an unmounted component.
  A redraw is triggered by bumping a single `version` signal. See
  @d-reader-store.
]

#why[
  Live strokes are drawn imperatively on the canvas instead of through the
  virtual DOM: a pen produces 60--240 events per second, and re-rendering
  components for each would add visible latency.
]

=== Management in the regular views

`forms` holds the pieces every editor shares: the score fields, the
instrument checkboxes, the editor of an existing part (fields, upload or
replacement of the PDF, list of file versions, deletion) and the form that
adds a new part. A PDF upload reads the file in the browser and sends it as
the raw request body.

`score_edit` contains the guided flow for a new piece: step 1 creates the
score from its details, step 2 adds parts one after another. Each new part
is created first and its PDF is then uploaded in a background task, so the
librarian can type the next part while the upload runs; every added part
shows its upload state, and "Finish" waits for running uploads. The flow
ends in the library, where the new piece is highlighted (a memory-only
global signal, `FOCUS_SCORE`). The same module has the edit views of a
piece and of a single part.

`programme_edit` edits title, date, notes and the ordered pieces of a
programme; `instruments` lists the instruments by family and lets
librarians add, rename and delete them (a refused deletion of an
instrument still in use is shown as a message). `groups` edits members and
grants, `users` creates accounts with invite links (copied to the
clipboard and sent by the admin, since the server sends no e-mail).
