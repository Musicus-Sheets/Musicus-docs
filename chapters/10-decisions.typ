#import "../template.typ": *

= Architecture decisions <decisions>

This chapter records the decisions a reader might not expect, with the
reasons and the price paid. Each entry states the situation, the decision,
why it was taken, and its consequences. Requirements R1--R7 are listed in
the introduction.

== One process instead of separate services <d-monolith>

#decision(
  [A typical web application runs an application server, a database server
   and often an object store as separate services.],
  [Musicus is a single process: the API, the static web client, an embedded
   SQLite database and a file store on local disk.],
  [The server must run on a Raspberry Pi or a 1 GB VPS (R7) and be operated
   by volunteers. One process needs about 11 MB at idle, installs as one
   binary or one container, and is backed up as one file plus one folder.
   The measured load (120 simultaneous downloads of a 3 MB file in 0.2 s on
   one core) is far below what one process can handle.],
  [No high availability; scaling means a bigger machine. The domain logic
   uses plain SQL through sqlx, so moving to PostgreSQL (evaluated as
   variant A-PG) touches the `db` unit and the SQL dialect, not the architecture.],
)

== SQLite with one writer connection <d-sqlite>

#decision(
  [SQLite allows only one writer at a time. Concurrent writes from many
   connections lead to `SQLITE_BUSY` errors or lock waits.],
  [Two pools: exactly one write connection, and 2--8 read-only connections.
   WAL mode lets readers run while the writer writes.],
  [The pool of one is the write queue: requests wait for the connection
   inside the process, in order, instead of failing. Reads (the vast
   majority: listing, downloading, loading layers) never wait for writes.
   In tests with 2 million parts and 1 million annotation pages, SQLite
   handled 560--2 800 page saves per second, about 10 times the expected
   peak of a large orchestra.],
  [Long write transactions would block all other writes, so handlers keep
   them short. Heavy parallel writing (many ensembles on one server) is the
   point where PostgreSQL becomes the better choice.],
)

== Static SQL with JSON id lists <d-static-sql>

#decision(
  [Queries such as "parts of these scores" need a variable number of ids.
   The usual approach builds `IN (?, ?, ...)` strings at run time.],
  [Every SQL statement is a compile-time constant. Id lists are passed as
   one JSON array parameter and expanded with `json_each(?)`. The shared
   access rule is spliced in with `concat!` at compile time.],
  [sqlx 0.9 accepts only `&'static str` queries unless they are explicitly
   marked as safe. Keeping all SQL static makes SQL injection impossible by
   construction and keeps the code reviewable.],
  [Some queries read slightly unusually 
   (`IN (SELECT value FROM json_each(?3))`). The access rule is a macro, not a function.],
)

== Content-addressed, immutable file store <d-blobs>

#decision(
  [Uploaded files could be stored in the database, under their original
   names, or in an object store.],
  [Files are stored on disk under their SHA-256 hash and never changed or
   deleted. A new upload of a part creates a new version that points to a
   new blob. Annotation layers, in contrast, live in the database.],
  [A hash-named file can be cached forever (`ETag` is the hash), is
   deduplicated automatically, cannot be half-written (temp file + rename),
   and makes incremental backups and the planned offline sync simple. Large
   files in SQLite would bloat the WAL and the backup and cannot be served
   with `Range` as cheaply. Annotation layers are the opposite case (small,
   private, often changed, versioned per page), so they belong in the
   database.],
  [Disk usage only grows; a clean-up of unreferenced blobs is future work.
   Annotation sets can keep pointing to old versions, which is intended.],
)

== Access rule in SQL, no cache, 404 for denied reads <d-access>

#decision(
  [Permission systems often cache computed permissions and answer 403 for
   forbidden resources.],
  [The rule "may this user read this part" is one SQL fragment evaluated in
   every query that touches parts, scores, programmes, files or
   annotations. Nothing is cached. Denied reads answer 404.],
  [The check costs about 25 µs even for 200 000 parts, so a cache would add
   complexity and the risk of stale permissions for no gain. Using the same
   fragment for lists and single loads guarantees they agree. A 404 does not
   reveal whether a title exists in the library.],
  [Changes to groups and grants apply on the next request. Clients cannot
   distinguish "does not exist" from "not allowed", which is intended.],
)

== Opaque session tokens instead of JWT <d-sessions>

#decision(
  [Many APIs use signed, self-contained tokens (JWT) that need no database
   lookup.],
  [Sessions are random 256-bit tokens; the database stores their SHA-256.
   Each request looks the session up. Expiry slides (default 60 days) and
   is written at most once an hour.],
  [Logout, password change, disabling a user and revoking a device take
   effect immediately, which JWTs cannot do without a deny list. The lookup
   is one primary-key read. Storing only the hash means a leaked database
   does not contain usable tokens. The long sliding expiry keeps tablets
   logged in between rehearsals.],
  [One indexed read per request. Bearer tokens for future apps use the same
   table.],
)

== CSRF protection by a required header <d-csrf>

#decision(
  [Cookie-authenticated APIs are open to cross-site request forgery. The
   classic defence is a synchronizer token embedded in forms.],
  [Cookies are `SameSite=Lax`, and every state-changing request
   authenticated by cookie must carry the header `x-musicus-csrf`. Bearer
   token requests are exempt.],
  [A cross-site page cannot add a custom header to a request without a CORS
   preflight, which the server never approves. This needs no token storage,
   no extra round trip, and works naturally with a single-page app that
   sends all requests through one helper.],
  [Plain HTML forms cannot be used for writes; the client never uses them.],
)

== Invite links instead of passwords set by an admin <d-invites>

#decision(
  [Admins usually create accounts with an initial password, often sent by
   e-mail.],
  [Creating a user returns a one-time link (valid 7 days). The user chooses
   the password there. The first admin is created the same way at first
   start, with the link written to the log. Password resets are new links.],
  [No password ever exists that someone else knows, no default password
   exists, and the server needs no mail configuration; a librarian can send
   the link through any messenger. Accepting a link ends all other sessions,
   so it doubles as a secure reset.],
  [Someone must deliver the link. E-mail delivery and OpenID Connect are
   possible later additions.],
)

== Bounded password hashing <d-hashing>

#decision(
  [Argon2id deliberately needs 19 MiB of memory per hash. At the start of a
   rehearsal, 60 musicians may log in within seconds.],
  [Hashing runs on blocking threads behind a semaphore with one permit per
   CPU core. Unknown usernames are verified against a dummy hash.],
  [Without the bound, 60 parallel logins would need over 1 GB of RAM and
   could crash a small server. With it, the last of 60 logins waits about
   1.3 s on one core. The dummy hash keeps response times equal for known
   and unknown usernames.],
  [Login bursts are serialised per core; the in-memory login limiter
   restarts empty after a server restart.],
)

== Shared Rust types instead of server functions <d-shared-types>

#decision(
  [Dioxus offers "server functions": the client calls Rust functions that
   run on the server, with the transport generated automatically.],
  [The server exposes a plain REST API built with Axum; request and
   response types live in the shared crate `musicus-api`.],
  [The later offline app, scripts and possibly other clients need a stable,
   versionable HTTP API. Dioxus is pre-1.0 and has changed its APIs between
   minor versions; keeping it out of the server isolates the server from
   that churn. File streaming with `Range` and caching headers needs plain
   HTTP routes anyway. Shared types still give compile-time agreement
   between client and server.],
  [Client helpers for HTTP are written by hand (`api.rs`), about 150 lines.],
)

== pdf.js in the browser, hayro on the server <d-pdf-rendering>

#decision(
  [The client is written in Rust; a pure-Rust PDF renderer (hayro) exists
   and runs in WebAssembly.],
  [The browser renders pages with pdf.js through a small JavaScript bridge,
   using its *legacy* build. The server uses hayro only for page counts and
   thumbnails.],
  [pdf.js is the de-facto standard for PDFs in browsers and handles
   real-world files best. hayro in WebAssembly measured 1.1--1.7 MB
   (compressed) extra download and is, by its own description, still
   missing features. On the server, hayro avoids C dependencies and a
   failed thumbnail is harmless. The legacy pdf.js build was chosen after the
   current build failed in the test browser, because it relies on very new
   JavaScript features that older tablets also lack.],
  [The client contains JavaScript, kept in one file behind a typed Rust
   interface. The renderer can be swapped later without touching the pages.],
)

== No persistent storage on the client <d-no-client-storage>

#decision(
  [Web apps usually cache data with the HTTP cache, IndexedDB or a service
   worker.],
  [Sheets are kept in a JavaScript `Map` in memory only. The server sends
   `Cache-Control: private, no-store` by default (configurable to
   `immutable`). Annotations are always loaded from the server.],
  [Requirement R4: no data stays on the device until the encrypted app
   exists. Memory still allows downloading a whole programme in advance, so
   the network is not needed during the concert. The option `immutable` lets
   operators trade this for faster reloads.],
  [Reloading the page downloads the sheets again; very large programmes use
   correspondingly much memory in the tab.],
)

== Vector annotations in a compact binary format <d-ink-format>

#decision(
  [Annotations could be stored as images, as SVG, or as JSON objects.],
  [Annotations are lists of vector objects with page-relative 16-bit
   coordinates, encoded with postcard and delta-coded points, compressed
   with zstd on the server, one record per page.],
  [Page-relative coordinates make annotations independent of screen size
   and zoom. Single objects can be erased and merged. The format is 7--9
   times smaller than JSON (about 7 KB for a typical page), small enough to
   save the whole page on every change and keep it in SQLite. A version byte
   allows format changes later.],
  [The format is not human-readable; debugging uses the decoder in
   `musicus-api`. Annotations are tied to page geometry, which is why they
   belong to a file version (see @d-blobs).],
)

== Optimistic concurrency per page <d-optimistic>

#decision(
  [The same user may edit a set on a tablet and on a laptop. Concurrent
   saves could overwrite each other.],
  [Each page has a revision. Saves must send `If-Match` with the revision
   they are based on; a mismatch answers 409. The client then merges by
   object id and saves again. Objects are immutable (an edit is a removal
   plus an addition) and carry random 64-bit ids.],
  [Only one person edits a set, so conflicts are rare and come from that
   person's own devices. Immutable objects make the id-based three-way merge
   exact, without locks, operational transforms or a CRDT library. The
   revision is also the basis for the planned offline sync.],
  [Moving an object is "erase and redraw". If both devices change the same
   page within the same second, one extra round trip is needed.],
)

== 204 for pages without annotations <d-204>

#decision(
  [REST conventions suggest 404 for a resource that does not exist.],
  [Loading an annotation page that was never saved answers 204 with
   `ETag: "0"`.],
  [Every page turn loads a layer, and most pages have none. Browsers log
   every 404 as an error in the console, which buried real errors, and a
   404 is also the answer for "no access". 204 says "exists, empty" and hands
   the client the revision to send in its first `If-Match`.],
  [Clients must treat 204 as an empty layer.],
)

== Reader state outside the UI framework <d-reader-store>

#decision(
  [In Dioxus, component state normally lives in signals, which are dropped
   with the component.],
  [The reader keeps annotation state in a plain `Rc<RefCell<Store>>`. A
   single signal (`version`) is bumped to trigger redraws. Unsaved pages
   are flushed by a task started with `spawn_forever` when the reader
   closes, and copies are handed to `bridge.js` for the tab-close case.],
  [Saving must finish after the user leaves the reader or closes the tab;
   tasks bound to the component would be cancelled with it, and signals of
   an unmounted component must not be touched. Keeping the store outside
   the reactive system also avoids re-rendering on every pen movement.],
  [Redraws are triggered explicitly. The store's consistency is maintained
   by hand (generation counters), which is why it is confined to one
   module.],
)

== Distroless runtime image <d-distroless>

#decision(
  [Container images are usually based on a Linux distribution with a shell
   and tools like curl.],
  [The runtime image contains only the server binary, the web assets and
   the C runtime (`distroless/cc`), and runs as a non-root user.],
  [Smaller image (about 70 MB), fewer packages to patch, and nothing an
   attacker could use to run further commands after a compromise.],
  [Health check and backup are subcommands of the server
   (`musicus-server healthcheck`, `musicus-server backup`) because no shell
   or curl is available. Debugging inside the container needs a separate
   debug image.],
)

== Management inside the regular views <d-inline-management>

#decision(
  [Administrative functions are often collected in a separate admin area
   with its own lists of everything.],
  [Musicus has no management area. The library, programme and instrument
   views are the same for every role; for librarians and admins they add
   "Add piece", "Edit" on every piece and part, "New programme", "Edit" on a
   programme and instrument editing. Groups and users have their own tabs.],
  [Librarians work where the music is: they find a piece the way musicians
   do and edit it there, instead of looking it up a second time in another
   list. One set of views is easier to learn, to document and to support,
   and members see exactly what librarians see, minus the controls.],
  [Every view must check the role before showing a control. This is
   convenience only: the server checks every request, so a hidden button
   is never the protection. New management functions belong next to the
   content they change.],
)

== Imports go through a staging area and a review <d-import-staging>

#decision(
  [An archive could be imported directly: read the names, create pieces
   and parts, done.],
  [An import uploads into a staging area (`import_files`, `import_items`).
   Nothing is created until a librarian commits a reviewed piece. The values
   read from the names are stored with their source; the review is computed
   on every read against the current library, with green, yellow and red
   marks; red blocks the commit. Instruments are never created
   automatically; a word that means an instrument is stored as alias once.
   Each piece is committed in its own short transaction, and a batch can be
   undone as long as nobody annotated its parts.],
  [The instrument of a part decides who may read it. A wrong guess ("Klar"
   becoming a new instrument, a full score taken as conductor's part)
   would show sheets to the wrong musicians or hide them. A staging area
   lets the librarian check thousands of files without anything reaching
   members, and short transactions keep annotation saves flowing during a
   large import (@d-sqlite).],
  [Staged files are blobs without a part, so they are invisible through
   the library by construction; the review has its own librarian-only
   routes. Undo cannot delete blobs (@d-blobs), so files of an undone import
   stay in the store.],
)

== Music systems detected on the server, once per file <d-system-layout>

#decision(
  [The system view (@system-view) needs to know where the music systems are
   on every page. This could be computed in the browser when a part is
   opened, by optical music recognition, or entered by hand.],
  [The server finds staves, systems and cut lines with a projection-based
   image analysis of each page rendered by hayro, once per file, in one
   background worker, and stores the result with an algorithm version. The
   client only plans the views for its screen. Pages the analysis is unsure
   about are shown whole; librarians can correct a page.],
  [Files are immutable and shared by all members, so one analysis serves
   everyone and never becomes stale. The analysis needs 23--112 ms per page on
   one laptop core and no external model; a tablet would repeat it for every
   musician at the worst moment (opening a piece on stage). hayro already
   renders thumbnails on the server, so no new dependency is needed. Optical
   music recognition would be far heavier and still fail on manuscripts. In
   the prototype, 82 of 84 music pages of 23 real scores were correct.],
  [New uploads have no layout for a few seconds (the reader shows whole
   pages meanwhile). A better algorithm must raise `ALGORITHM_VERSION`; the
   worker then analyses every file again in the background. Systems wider
   than the screen are shown at full width, not split (R-READ-017).],
)

== Fluent messages with typed keys, formatting by the browser <d-i18n-fluent>

#decision(
  [Musicus is to speak the language of its users (F-I18N-001). The web
   client is Rust compiled to WebAssembly; every kilobyte of the client is
   downloaded by every tablet. Translations should be possible for
   musicians without programming, later through a translation platform.],
  [User-interface texts are Project Fluent messages in a crate
   `musicus-i18n`, English as source. A build script turns the English
   catalogue into one Rust function per message, so a missing message or a
   wrong argument does not compile. All shipped languages are compiled into
   the client; a message missing in a language falls back to English.
   Dates, numbers and sorting use the browser's `Intl` API. The language is
   the browser's; there is no setting.],
  [Measured in WebAssembly: Fluent with plural rules adds about 60 KB
   (gzip), date formatting from ICU4X about 217 KB and collation about
   418 KB, while the browser offers both for free. Fluent has plural rules
   and selectors, so translators control word order ("Clarinette en si♭"),
   and the usual translation platforms read it. gettext has no selectors and
   no compile-time check; other Rust libraries have weak plural support.],
  [Translators work in `.ftl` files (or a platform that writes them). The
   server sends no prose: part names are composed in the browser from
   their components, and errors become codes (@i18n). The search index
   stores the key spellings of every shipped language, so a new language
   needs one index rebuild.],
)
