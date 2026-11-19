#import "../template.typ": *

= Interaction flows <flows>

This chapter follows the most important use cases through the components,
so it is visible how the units described above work together.

== First start and invitations <flow-invite>

+ `musicus-server serve` starts with an empty data directory. `open_state`
  creates the database and runs the migrations; `bootstrap_admin` finds no
  users, inserts `admin` without a password and an invite with a random
  token, and logs the link `<public-url>/invite/<token>`.
+ The administrator opens the link. The client route `Invite` asks
  `GET /api/auth/invites/{token}` for the name, then posts the chosen
  password to the same URL.
+ The server hashes the password (Argon2id), stores it, deletes all
  invites *and sessions* of that user, creates a new session and sets the
  cookie. The client stores the returned user in `Session` and shows the
  library.
+ New users are created by an admin (`POST /api/users`), which returns
  another invite. The same flow serves password resets (`POST
  /api/users/{id}/invite`).

#why[
  Users choose their own password through a one-time link; admins never
  know or transmit passwords, and the server needs no e-mail set-up. See
  @d-invites.
]

== Login and authenticated requests

+ The client posts username and password to `/api/auth/login`.
+ `LoginLimiter` rejects the attempt with 429 if the username or the IP had
  10 failures in the last 15 minutes.
+ `verify_password` waits for a hashing permit (at most one Argon2
  computation per core), verifies on a blocking thread, and verifies a dummy
  hash for unknown usernames.
+ On success a session row is created and the token is returned as an
  `HttpOnly` cookie (or in the body for `bearer: true` clients).
+ Every later request passes the `AuthUser` extractor (@server): token from
  cookie or header, CSRF header check for writes, session lookup, sliding
  expiry.

== Reading a sheet: the burst case <flow-download>

When the conductor announces the next piece, many tablets request the same
file at once.

+ The client already knows the file hash from the part
  (`Part.file.sha256`) and requests `GET /api/files/{sha256}`.
+ `routes::files` checks that the hash is well-formed and that the user may
  read at least one part that uses this file (`part_visible!`). Otherwise:
  404.
+ If the request carries `If-None-Match` with the hash, the answer is 304.
+ If it carries `Range`, the bytes are streamed from disk by tower-http's
  `ServeFile` (partial content).
+ Otherwise the file comes from the `FileCache`; on a miss it is read once
  from disk and inserted. All responses share the same reference-counted
  buffer.
+ The response carries `ETag: "<sha256>"` and the configured
  `Cache-Control` (`private, no-store` by default).

In the prototypes, one CPU core served 120 simultaneous downloads of a 3 MB
file in 0.2 s. The real limit is the Wi-Fi, which the next flow avoids.

== Concert programme prefetch <flow-prefetch>

+ The member opens a programme. The client loads `GET /api/programmes/{id}`,
  which contains only the pieces and parts this member may read.
+ The `programmes` page collects the file URLs, frees sheets of other
  programmes (`retainOnly`), and calls `bridge::prefetch` for three files at
  a time, showing progress.
+ `bridge.js` keeps the bytes in memory. When the reader later opens a
  part, pdf.js opens it from memory; no network request is needed. The
  reader also prefetches the next piece of the programme.

== Uploading a sheet <flow-upload>

+ A librarian picks a PDF in the part editor; the browser reads it and sends
  it as the raw body of `PUT /api/parts/{id}/file`.
+ `BlobStore::receive` streams the body to `tmp/`, computing SHA-256, and
  stops at the upload limit (413).
+ `processors::sniff_mime` checks the first kilobyte (415 if not PDF).
+ If a file with this hash exists, the temporary file is dropped. Otherwise
  `process_pdf` runs on a blocking thread (page count, thumbnail), the
  thumbnail is stored as its own blob, the PDF is moved into the store, and a
  `files` row is inserted.
+ In a transaction, `part_files` gets a new version unless the current
  version already points to this file (re-uploading the same file is a
  no-op).
+ Existing annotation sets keep pointing to the old file; their owners see
  a hint and can move the sets to the new version (@flow-save).

== Importing an archive <flow-import>

+ A librarian opens #emph[Import] and selects (or drops) the archive folder.
  The browser lists the PDF files with their paths, suggests the pattern
  that fits most of them and the naming language, and previews the result
  (`musicus_api::import`, the same code the server runs).
+ `POST /api/import/batches` creates the batch. The browser computes the
  SHA-256 of every file (in WebAssembly, in chunks) and sends the list
  (`POST …/files`). The server marks content that is already in the library
  or twice in the folder as duplicate, computes the proposals from the paths
  and answers with the files it still needs.
+ The browser uploads those files one by one (`PUT /api/import/files/{id}/content`),
  like a normal upload: streamed to `tmp/`, hash checked against the
  announced one, PDF checked, thumbnail and page count, `files` row; the
  layout worker analyses the systems in the background. An interrupted
  import continues by selecting the folder again: only missing files are
  uploaded.
+ The review (`GET /api/import/batches/{id}`) resolves every proposal
  against the current instruments, aliases, pieces and groups: colours,
  suggested existing pieces, the groups that will read each part, warnings
  from the detected systems. Changes are stored as overrides
  (`PATCH /api/import/items`); mapping a word to an instrument stores an
  alias that every row uses at once.
+ `POST …/commit` creates each chosen (or every green) piece with its parts
  and file versions in one short write transaction, with the same validation
  as the piece form. From then on the normal read rule applies.
+ `POST …/undo` removes the parts and the pieces the batch created, unless
  musicians annotated them, other parts were added, or a piece is in a
  programme (409, nothing removed). Files stay in the store.

== Drawing and saving an annotation <flow-save>

#figure(
  diagram(
    spacing: (12mm, 7mm),
    node((0, 0), [*Tablet* (reader)], name: <a>),
    node((2, 0), [*Server*], name: <s>),
    node((4, 0), [*Laptop* (same user)], name: <b>),
    edge((0, 0.4), (0, 7.4), stroke: (dash: "dotted", paint: luma(150))),
    edge((2, 0.4), (2, 7.4), stroke: (dash: "dotted", paint: luma(150))),
    edge((4, 0.4), (4, 7.4), stroke: (dash: "dotted", paint: luma(150))),
    edge((0, 1), (2, 1), "->", [`GET page` → 204, `ETag "0"`], label-side: left),
    edge((4, 1.8), (2, 1.8), "->", [`PUT If-Match "0"` → 200, rev 1], label-side: right),
    edge((0, 2.8), (2, 2.8), "->", [`PUT If-Match "0"`], label-side: left),
    edge((2, 3.6), (0, 3.6), "->", [409 `{current_revision: 1}`], label-side: right),
    edge((0, 4.4), (2, 4.4), "->", [`GET page` → rev 1], label-side: left),
    node((0, 5.2), text(9pt)[`merge(base, local, server)`], fill: rgb("#fff8e6"), inset: 4pt),
    edge((0, 6), (2, 6), "->", [`PUT If-Match "1"` → 200, rev 2], label-side: left),
  ),
  caption: [Saving a page that was edited on two devices.],
)

+ When the reader shows a page, it loads the layer
  (`GET /api/annotation-sets/{set}/pages/{n}`). A page never saved answers
  204 with `ETag: "0"`; otherwise the server decompresses the stored layer
  and returns it with its revision as `ETag`.
+ The user draws. Each finished stroke is added to the `PageState`,
  pushed on the undo stack, registered with the bridge for the tab-close
  case (`setPending`), and a save is scheduled 1.5 s later. If no set exists
  yet, the first stroke creates one (named after the programme, or "My
  annotations").
+ The save sends the encoded layer with `If-Match: "<revision>"`. The server
  checks ownership and access, the page range, decodes and validates the
  layer (422 if invalid), compresses it, and in one write transaction
  compares the stored revision with `If-Match`.
+ Equal: the row is upserted with `revision + 1` and the new revision is
  returned. Different: 409 with `current_revision`.
+ On 409 the client fetches the current layer, merges (objects deleted on
  either side disappear, objects added on either side are kept) and saves
  the merge with the new revision.
+ Leaving the reader flushes all dirty pages; closing the tab sends them
  with `keepalive` requests from `bridge.js`.

#why[
  Optimistic concurrency per page with a client-side merge, instead of
  locking or a CRDT: only one person edits a set, conflicts come only from
  that person's second device, and immutable objects make the merge exact.
  See @d-optimistic.
]

#why[
  An unsaved page answers 204 with revision 0 rather than 404. Every page
  turn loads a layer, and most pages have none; a 404 would be logged as an
  error by the browser on every turn and would be indistinguishable from
  "no access". See @d-204.
]

== Access changes take effect immediately

Removing a member from a group, removing a grant or disabling a user needs
no further action: the next request evaluates the access rule again. A
disabled user's sessions are deleted at once. Annotation sets are not
deleted when access is lost; they become invisible and reappear if access
is granted again.
