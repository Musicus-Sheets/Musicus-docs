#import "../template.typ": *

= Server `musicus-server` <server>

*Purpose:* the single server process. It owns the database and the file
store, enforces authentication and access control, and serves both the REST
API and the built web client. It is built on Axum (HTTP), Tokio (async
runtime) and sqlx (SQLite access).

== Sub units

The crate is split into a library (`lib.rs`, used by the binary and by the
integration tests) and a thin binary (`main.rs`). The library consists of
these units:

#table(
  columns: (auto, auto, 1fr),
  [Layer], [Unit], [Purpose],
  table.cell(rowspan: 2)[Entry], [`main`, `config`], [Command line (clap), process start-up, TLS, graceful shutdown.],
  [`lib`], [`open_state` (opens database and file store), `bootstrap_admin`.],
  table.cell(rowspan: 2)[HTTP], [`routes`], [Router, middleware, and one sub module per API area.],
  [`error`], [One error type for all handlers, turned into HTTP status + `ApiError` JSON; input validation helpers.],
  table.cell(rowspan: 2)[Security], [`auth`], [Passwords, session tokens, the `AuthUser` extractor, CSRF check, login rate limiter.],
  [`access`], [The rule "who may read which part", as an SQL fragment.],
  table.cell(rowspan: 4)[Storage], [`state`], [`App`: the shared state handed to every handler; `Settings`.],
  [`db`], [SQLite connection pools, migrations, online backup.],
  [`blobs`], [Content-addressed file store on disk.],
  [`cache`], [In-memory LRU cache of hot sheet files.],
  [Formats], [`processors`], [Recognises uploaded files and extracts page count and thumbnail.],
)

@fig-server shows how they depend on each other. Arrows point from the user
of a unit to the unit used. Handlers reach the database, blob store and
cache through `state::App`; `auth` also reads sessions through it.

#figure(
  diagram(
    spacing: (9mm, 9mm),
    box-node((1.5, 0), [`main` / `config`], name: <main>),
    box-node((1.5, 1), [`lib::open_state`], name: <lib>),
    box-node((0, 2), [`routes::*` handlers], name: <routes>, fill: rgb("#eef3ff")),
    box-node((3, 2), [`state::App`], name: <state>),
    box-node((-1.4, 3.2), [`auth` \ (`AuthUser`)], name: <auth>),
    box-node((0, 3.2), [`access`], name: <access>),
    box-node((1.4, 3.2), [`error`], name: <error>),
    box-node((2.2, 4.4), [`db`], name: <db>),
    box-node((3.3, 4.4), [`blobs`], name: <blobs>),
    box-node((4.4, 4.4), [`cache`], name: <cache>),
    box-node((0, 4.4), [`processors`], name: <proc>),
    edge(<main>, <lib>, "->"),
    edge(<lib>, <state>, "->", [creates]),
    edge(<main>, (0, 1), <routes>, "->", [builds router]),
    edge(<routes>, <state>, "->", [`State<AppState>`]),
    edge(<routes>, <auth>, "->"),
    edge(<routes>, <access>, "->"),
    edge(<routes>, <error>, "->"),
    edge(<routes>, (0, 3.8), <proc>, "->", [uploads], label-side: left),
    edge(<state>, <db>, "->"),
    edge(<state>, <blobs>, "->"),
    edge(<state>, <cache>, "->"),
  ),
  caption: [Units of the server and their dependencies.],
) <fig-server>

== Entry: `main` and `config`

`config` declares the command line with clap. Every option of `serve` can
also be set through an environment variable (`MUSICUS_*`), which is how the
container image is configured. Four subcommands exist:

#table(
  columns: (auto, 1fr),
  [Command], [What it does],
  [`serve`], [Runs the server. Creates the first admin if the database has no users (see below).],
  [`create-admin`], [Inserts an admin user and prints a one-time invite link.],
  [`backup --to <file>`], [Writes a consistent copy of the database with `VACUUM INTO`, safe while the server runs.],
  [`healthcheck`], [Sends `GET /api/health` over a raw TCP connection and exits 0 or 1.],
)

`serve` turns the options into `Settings`, calls `open_state`, then either
binds a plain TCP listener (Axum) or, with `--tls-cert`/`--tls-key`, a
rustls listener (axum-server). Both stop gracefully on SIGTERM or Ctrl-C:
running requests may finish, which matters for annotation saves in flight
when a container is stopped.

On a fresh database `bootstrap_admin` creates the user `admin` without a
password and logs a one-time invite link. The administrator sets the
password through the web client; no default password ever exists.

#why[
  `healthcheck` is a subcommand of the server binary, not a `curl` call,
  because the runtime image (distroless) has no shell and no curl. See
  @d-distroless.
]

== Shared state: `state`

Axum hands every handler an `AppState = Arc<App>`. `App` holds:

#table(
  columns: (auto, 1fr),
  [Field], [Purpose],
  [`db: Db`], [The two connection pools (reader and writer).],
  [`blobs: BlobStore`], [The file store.],
  [`cache: FileCache`], [RAM cache of hot files (default 128 MB).],
  [`settings: Settings`], [Cookie `Secure` flag, client cache policy, session and invite lifetimes, upload limit, proxy trust.],
  [`limiter: LoginLimiter`], [Counts failed logins.],
  [`hashing: Semaphore`], [Bounds parallel Argon2 computations to the number of CPU cores.],
)

The state contains no per-user data and no permission cache; everything
user-specific is read from the database per request.

== Storage units

=== `db`: SQLite pools

`Db` contains two `sqlx` pools on the same database file:

- `write`: exactly *one* connection. SQLite allows one writer at a time; a
  pool of one turns concurrent write requests into an orderly queue inside
  the process instead of `SQLITE_BUSY` errors.
- `read`: 2 to 8 read-only connections (by CPU count). In WAL mode readers
  never wait for the writer.

`Db::open` sets WAL mode, `synchronous = NORMAL`, foreign keys, a busy
timeout and the page cache size, then runs the embedded migrations
(`migrations/*.sql`, applied by `sqlx::migrate!` at start-up). The schema is
described in @data.

Two helpers are used throughout the handlers: `now()` (Unix seconds) and
`json_ids()`, which turns a list of ids into a JSON array that SQL then
expands with `json_each(?)`.

#why[
  SQL statements receive id lists as one JSON parameter and expand them with
  SQLite's `json_each`, instead of building `IN (?, ?, ...)` strings. sqlx
  0.9 only accepts static SQL strings unless explicitly marked safe, so this
  keeps every statement static and immune to injection. See @d-static-sql.
]

=== `blobs`: content-addressed file store

Every uploaded file is stored once, at `blobs/<first two hex digits>/<sha256>`.
The unit offers:

- `receive(body, limit)`: streams a request body into `tmp/`, hashing it on
  the way, and aborts at the upload limit. Returns a `PendingBlob` (temporary
  path, hash, size).
- `commit(pending)`: moves the file to its final path with an atomic
  rename, after `fsync` of file and directory. If the hash already exists,
  the temporary file is deleted instead (deduplication).
- `discard(pending)`, `put_bytes(bytes)` (for thumbnails), `path(sha256)`.

A blob path therefore either does not exist or holds complete content. On
start-up, leftovers in `tmp/` from interrupted uploads are deleted. Blobs are
never modified or deleted by the application.

#why[
  Files live on disk, named by their hash, not inside the database and not
  under their original names. Immutable, hash-named files can be cached
  forever, deduplicate themselves, are cheap to back up incrementally, and
  are the basis of the later offline sync ("which hashes do you have?").
  See @d-blobs.
]

=== `cache`: hot files in RAM

`FileCache` is a small least-recently-used cache from hash to `Bytes`
(reference-counted buffers). When 60 musicians open the same piece, the
file is read from disk once and every response shares the same buffer.
Files larger than a quarter of the capacity are not cached.

== Security units

=== `auth`

#table(
  columns: (auto, 1fr),
  [Item], [Purpose],
  [`hash_password`, `verify_password`], [Argon2id (19 MiB, t = 2, p = 1) on a blocking thread, each call holding a permit of `App::hashing`. For unknown users a dummy hash is verified, so the response time does not reveal whether a username exists.],
  [`new_token`, `token_hash`], [256-bit random tokens (hex). Only their SHA-256 is stored, for sessions and invites alike.],
  [`create_session`, `session_cookie`], [Store a session row; build the `Set-Cookie` header (`HttpOnly; SameSite=Lax; Secure`).],
  [`AuthUser` (extractor)], [Runs before every protected handler; see below.],
  [`ClientIp` (extractor)], [Client address for rate limiting; trusts `X-Forwarded-For` only with `--trust-proxy`.],
  [`LoginLimiter`], [In-memory count of failed logins per username and per IP: 10 failures in 15 minutes block further attempts with HTTP 429.],
)

`AuthUser` is an Axum extractor: a handler that lists it as a parameter
cannot run for anonymous users. Extraction does this:

+ Take the token from `Authorization: Bearer` (apps) or from the session cookie (browser).
+ If it came from the cookie and the method changes state (not GET/HEAD/OPTIONS), require the header `x-musicus-csrf`; otherwise 403.
+ Look up the session by token hash, join the user, reject expired sessions and disabled users (401).
+ If the session was last seen more than an hour ago, extend its expiry (sliding expiry, default 60 days).
+ Return `id`, `role` and `session_id` to the handler.

#why[
  Opaque tokens checked against the database on every request, instead of
  signed JWTs: logout, password changes and disabling a user take effect
  immediately, and the lookup is a single indexed read. See @d-sessions.
  The CSRF protection is a required custom header rather than a token,
  because browsers cannot send custom headers cross-site without a CORS
  preflight the server never allows. See @d-csrf.
]

#why[
  Logins are hashed behind a semaphore so a burst of logins cannot exhaust
  the memory of a small server. See @d-hashing.
]

#why[
  The sliding expiry is written at most once an hour, so reading sheets (many
  GET requests) does not turn into database writes that would compete with
  annotation saves for the single writer.
]

=== `access`

All read permissions are expressed by one SQL fragment, the macro
`part_visible!()`. It is true for a part `p` if the user is a librarian or
admin, *or* one of the user's groups is granted one of the part's
instruments, *or* one of the user's groups is granted the part's whole
score. The fragment is spliced (with `concat!`) into every query that lists
or loads parts, scores, programmes, files and annotations, so listing and
loading cannot disagree.

`can_read_part` and `ensure_part_readable` wrap it for single checks. A
denied read answers *404 Not Found*, never 403.

#why[
  The rule is SQL, evaluated per request, with no permission cache: it costs
  about 25 µs even with 200 000 parts, and a removed grant applies to the
  very next request. Answering 404 instead of 403 means a member cannot probe
  which titles exist in the library. See @d-access.
]

== HTTP units

=== `routes`: router and middleware

`routes::api()` maps all endpoints under `/api` to handlers;
`routes::app()` nests it, adds the web client, and wraps everything in
middleware:

- security headers: `X-Content-Type-Options: nosniff`, `X-Frame-Options:
  DENY`, `Referrer-Policy: same-origin`, `Permissions-Policy`;
- request tracing (`tower-http` `TraceLayer`, controlled by `RUST_LOG`);
- body limits: 2 MB by default, 4 MiB for annotation pages, none for file
  uploads (the blob store enforces the configurable upload limit while
  streaming);
- the web client: `ServeDir` serves the built assets (preferring
  precompressed `.br`/`.gz` copies) and falls back to `index.html` for any
  unknown path, because client-side routes like `/parts/7` are handled by
  the single-page app.

Unknown `/api` paths answer a JSON 404, not `index.html`.

=== Handler modules

#table(
  columns: (auto, 1fr),
  [Module], [Responsibility],
  [`routes::auth`], [Login (cookie or bearer token), logout, current user, invite info and acceptance, password change (logs out other devices), list and revoke own sessions.],
  [`routes::users`], [Admin only: list, create (returns an invite), change role, disable (deletes sessions), issue a new invite.],
  [`routes::groups`], [Instruments (librarians), groups and membership (admins), instrument and score grants (librarians). Lists are replaced whole in one transaction.],
  [`routes::library`], [Scores and parts with metadata (part names derived via `musicus_api::naming`, keys validated against the key list), full-text search over scores and the user's parts, uploads with versioning, file version list. Shared helpers `visible_parts`, `with_parts`, `scores_by_ids` are reused by programmes.],
  [`part_index`], [Keeps the search index of part names current: re-indexes parts when they or their instruments change, rebuilds it on start if it does not match the parts table.],
  [`routes::files`], [Serves files and thumbnails by hash after the access check, with `ETag`, `Range`, the RAM cache and the configured `Cache-Control`.],
  [`routes::programmes`], [Concert programmes and their ordered pieces; members only see pieces they have parts for.],
  [`routes::annotations`], [Annotation sets (create, duplicate, rename, default, link to a programme, delete, migrate to a new file version) and page layers with revision checks.],
)

Handlers follow one pattern: extract `State`, `AuthUser`, path and body;
check the role (`require_librarian`, `require_admin`) or the access rule;
validate input with `error::required`/`optional`; run one or a few SQL
statements (writes in a transaction on the writer pool); return a
`musicus-api` type as JSON.

=== `error`

`AppError` enumerates every failure a handler can report (not found,
unauthorized, forbidden, bad request, conflict, unprocessable, payload too
large, unsupported media type, precondition required, too many requests,
internal). Its `IntoResponse` implementation chooses the status code and
renders `ApiError` JSON. `From<sqlx::Error>` maps unique-constraint
violations to 409 ("already exists") and foreign-key violations to 409
("still in use"), so handlers can rely on the database for these checks.
Internal errors are logged with details but answered with a generic message.

== Format unit: `processors`

Called once per upload:

- `sniff_mime` recognises PDF by the `%PDF-` marker in the first kilobyte.
  Anything else is rejected with 415.
- `process_pdf` uses hayro, a pure-Rust PDF renderer, to count pages and
  render a 240-pixel-wide PNG thumbnail of the first page. It runs on a
  blocking thread; if hayro cannot read a file (e.g. an encrypted PDF), the
  file is still stored, just without page count and thumbnail.

#why[
  The server renders thumbnails with hayro, while the browser renders pages
  with pdf.js. hayro needs no C libraries (easy cross-compilation for the
  Pi), and a thumbnail tolerates rendering gaps; full page display uses the
  more mature pdf.js. MusicXML will become a second processor without
  touching the blob store. See @d-pdf-rendering.
]
