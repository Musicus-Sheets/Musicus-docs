#import "../template.typ": *

= System overview <overview>

Musicus consists of three components, all written in Rust, plus the data
the server keeps on disk. @fig-context shows them at run time.

#figure(
  diagram(
    spacing: (8mm, 9mm),
    box-node((0, 0), align(center)[*Browser* (tablet, laptop) \ `musicus-web` (WebAssembly) \ + `bridge.js` + pdf.js], name: <web>, fill: rgb("#eef3ff")),
    box-node((0, 1.3), align(center)[*Caddy* (optional) \ TLS termination], name: <caddy>, stroke: (dash: "dashed", paint: luma(90))),
    box-node((0, 2.6), align(center)[*`musicus-server`* \ REST API `/api` \ + static web client], name: <server>, fill: rgb("#eef3ff")),
    box-node((-0.9, 3.9), align(center)[*SQLite* \ `musicus.sqlite`], name: <db>),
    box-node((0.9, 3.9), align(center)[*Blob store* \ `blobs/ab/<sha256>`], name: <blobs>),
    box-node((2, 1.3), align(center)[*`musicus-api`* \ shared types], name: <api>, fill: rgb("#fff8e6")),
    edge(<web>, <caddy>, "<->", [HTTPS], label-side: left),
    edge(<caddy>, <server>, "<->", [HTTP], label-side: left),
    edge(<server>, <db>, "<->", [sqlx], label-side: right),
    edge(<server>, <blobs>, "<->", [files], label-side: left),
    edge(<api>, <web>, "->", stroke: (dash: "dotted")),
    edge(<api>, <server>, "->", stroke: (dash: "dotted")),
  ),
  caption: [Components at run time. Dotted arrows: `musicus-api` is compiled into both.],
) <fig-context>

== Components and their purpose

#table(
  columns: (auto, 1fr, auto),
  [Component], [Purpose], [Sub units],
  [`musicus-api`],
  [The contract between server and clients: every JSON request and response body, and the binary annotation format with its validation and merge logic. Contains no I/O.],
  [`dto`, `ink`],

  [`musicus-server`],
  [Everything that runs on the server: authentication, access control, the library, file storage and serving, concert programmes, annotation storage, and the command line (serve, create an admin, backup, health check).],
  [13 modules, see @server],

  [`musicus-web`],
  [The user interface in the browser: login, library, programmes, the sheet reader with the drawing tools, and the management pages. Talks to the server only through the REST API.],
  [7 modules + `bridge.js`, see @client],

  [SQLite database],
  [All structured data: users, sessions, groups, grants, metadata, programmes, annotation layers.],
  [tables, see @data],

  [Blob store],
  [The sheet files and thumbnails as immutable files named by their SHA-256 hash.],
  [`blobs/`, `tmp/`],
)

== How the components interact

- *Client to server:* only through the REST API under `/api`, with JSON
  bodies whose types come from `musicus-api`. Two endpoints use binary
  bodies: file upload (raw PDF) and annotation pages (the `ink` format).
  The browser authenticates with an `HttpOnly` session cookie.
- *Server to storage:* the server is the only process that touches the
  database and the blob store. Both live in one data directory
  (`MUSICUS_DATA_DIR`), so a backup is "the database file plus a folder".
- *Server to client code:* the same server process also serves the built
  web client (HTML, WebAssembly, JavaScript, CSS) as static files, so the
  whole application is one binary plus one folder of assets.
- *Shared crate:* `musicus-api` is compiled into both the server and the
  client. A change to a request type therefore breaks the build of whichever
  side was not updated, instead of failing at run time.

#why[
  One process with an embedded database instead of separate services
  (application server, database server, object store) keeps the memory
  footprint around 11 MB at idle and makes installation and backup trivial on
  a Raspberry Pi (R7). The measurements behind this choice are in the concept
  document; the reasoning is in @d-monolith and @d-sqlite.
]

== Compile-time dependencies

#figure(
  diagram(
    spacing: (18mm, 10mm),
    box-node((0, 0), [`musicus-web`], name: <w>),
    box-node((2, 0), [`musicus-server`], name: <s>),
    box-node((1, 1), [`musicus-api`], name: <a>, fill: rgb("#fff8e6")),
    edge(<w>, <a>, "->"),
    edge(<s>, <a>, "->"),
    box-node((0, -1), text(9pt)[Dioxus 0.7, gloo-net, web-sys, wasm-bindgen], name: <wd>, stroke: none, fill: none),
    box-node((2, -1), text(9pt)[Axum 0.8, sqlx 0.9 (SQLite), tower-http, \ argon2, hayro, zstd, clap, rustls], name: <sd>, stroke: none, fill: none),
    box-node((1, 2), text(9pt)[serde, postcard], name: <ad>, stroke: none, fill: none),
    edge(<w>, <wd>, "->", stroke: luma(160)),
    edge(<s>, <sd>, "->", stroke: luma(160)),
    edge(<a>, <ad>, "->", stroke: luma(160)),
  ),
  caption: [Crate dependencies and their most important libraries.],
)

The workspace builds the server and the shared crate with a plain
`cargo build`. The client is a member of the workspace but excluded from
`default-members`, because it only compiles for `wasm32-unknown-unknown`
and is built with the Dioxus CLI (`dx`).
