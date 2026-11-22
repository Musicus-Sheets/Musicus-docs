#import "../template.typ": *

= Build and deployment <deployment>

== Build

The released program is a single file: the server with the web client
built into it (R-OPS-030). The web client is built first, by the Dioxus CLI:

+ `scripts/fetch-pdfjs.sh` downloads the pinned pdf.js release from npm,
  verifies its SHA-512 checksum, and copies the legacy build into
  `crates/musicus-web/public/vendor/pdfjs/` (not committed).
+ `dx bundle --platform web --package musicus-web --release` compiles the
  client to WebAssembly, runs `wasm-bindgen` and `wasm-opt`, and bundles
  `bridge.js`, the stylesheet and the `public/` folder into
  `target/dx/musicus-web/release/web/public` (about 5.4 MB; empty the
  folder before, so no file of an earlier build remains).
+ `cargo build --release -p musicus-server --features embed-web` builds
  the server; its build script embeds every file of that folder (another
  folder with `MUSICUS_WEB_DIST`, relative to the repository root) and stops
  with the build commands if the client is missing. The program grows by
  the size of the client.

```sh
./scripts/fetch-pdfjs.sh
rm -rf target/dx/musicus-web/release
dx bundle --platform web --package musicus-web --release
cargo build --release --locked -p musicus-server --features embed-web
```

Without the feature the server builds without any client (development
needs no `dx` output) and warns at start that only `/api` is served.
`--web-dir <folder>` (`MUSICUS_WEB_DIR`) serves a client from a folder
instead, also over a built-in one; in development this is the debug build
of `dx build`.

#why[
  A plain program that needs a second folder next to it breaks as soon as
  someone copies only the file or starts it from another working
  directory. The build script embeds the files the same way it already
  embeds the database updates, so no extra library is needed, and the
  container image uses exactly the program offered for download. See
  @server (`routes`) for how the files are served.
]

== Data folder

Without `--data-dir` (or `MUSICUS_DATA_DIR`) the program uses the usual
folder for application data of the system (R-OPS-031) and logs
`data folder: <path>` at start, for every command:

#table(
  columns: (auto, 1fr),
  [System], [Default data folder],
  [Linux and other Unix], [`$XDG_DATA_HOME/musicus` if that variable holds an absolute path, else `~/.local/share/musicus`],
  [macOS], [`~/Library/Application Support/Musicus`],
  [Windows], [`%APPDATA%\Musicus` (the roaming application data of the user)],
  [Container image], [`/data` (the image sets `MUSICUS_DATA_DIR`)],
)

The folders come from the environment variables `XDG_DATA_HOME`, `HOME`
and `APPDATA`; if the needed one is missing, the program stops and asks for
`--data-dir`. For compatibility, a program started without a configured
folder in a working directory whose `data/musicus.sqlite` exists (the
default before) keeps using `./data` and warns, naming the new default and
`--data-dir data`; nothing is moved. This fallback is to be removed before
1.0. Services (systemd, a Windows service as LocalSystem) should always set
the folder explicitly.

== Run-time layout

#table(
  columns: (auto, 1fr),
  [Path (in the data directory)], [Content],
  [`musicus.sqlite` (+ `-wal`, `-shm`)], [The database in WAL mode.],
  [`blobs/ab/<sha256>`], [Immutable sheet files and thumbnails.],
  [`tmp/`], [Uploads in progress; emptied at start-up.],
)

Configuration is by command-line options or `MUSICUS_*` environment
variables; the full list is in the repository README.

== Listening address

`MUSICUS_LISTEN` defaults to `[::]:8080`. The server binds this as one
dual-stack socket (`IPV6_V6ONLY` switched off explicitly, since Windows and
some BSDs default to IPv6 only), so it answers on `127.0.0.1` and `::1`
alike; IPv4 clients appear as `::ffff:a.b.c.d` and are logged and rate
limited by their IPv4 address. Where IPv6 is missing (kernel booted with
`ipv6.disable=1`, some container setups), binding `[::]` fails and the server
falls back to `0.0.0.0` with the same port and logs a warning. Any other
address, `0.0.0.0` and `127.0.0.1` included, is bound exactly as given. The
start-up log names the bound address and whether it serves both families.
`musicus-server healthcheck` connects to `[::1]`, then `127.0.0.1`, for an
unspecified listening address.

#why[
  A reverse proxy configured with `localhost` (nginx resolves it to both
  `127.0.0.1` and `::1` and alternates) returned 502 for part of the requests
  while the default was the IPv4-only `0.0.0.0`. The fallback is limited to
  the default `[::]`: an explicitly chosen address that cannot be bound is an
  error, not something to replace silently.
]

== Container image

The `Dockerfile` has three stages:

#table(
  columns: (auto, 1fr),
  [Stage], [Purpose],
  [`dx`], [Installs the Dioxus CLI (slow, therefore its own cached stage).],
  [`build`], [Fetches pdf.js, bundles the web client into an emptied folder, builds the server with the client built in (`--features embed-web`).],
  [runtime], [`gcr.io/distroless/cc-debian12:nonroot`: only the server program (the same single file as the plain program); runs as UID 65532; data in the volume `/data`; `HEALTHCHECK` runs `musicus-server healthcheck`.],
)

#why[
  The runtime image is distroless: no shell, no package manager, not root.
  It shrinks the image to about 70 MB and removes most of what an attacker
  could use after a compromise. The price is that health checks and backups
  must be built into the server binary. See @d-distroless.
]

`compose.yaml` runs the image with one named volume. It publishes the port
on every interface over IPv4 and IPv6; `MUSICUS_BIND=127.0.0.1` restricts it
to `127.0.0.1` and `[::1]` (two port lines built with `${MUSICUS_BIND:+…}`,
which are identical, and counted once, when the variable is empty). The optional profile
`https` adds Caddy (`deploy/Caddyfile`), which obtains and renews a Let's
Encrypt certificate and forwards to the server; the server then trusts
`X-Forwarded-For` (`MUSICUS_TRUST_PROXY`) and should only listen on
localhost.
An existing nginx works the same way: `deploy/nginx.conf.example`
forwards to `127.0.0.1:8080`, raises `client_max_body_size` to the upload
limit and sets `X-Forwarded-For` to the client address (the server takes the
first entry of that header).

#note[
  HTTPS is required in practice, not optional: browsers only keep the
  `Secure` session cookie and grant the screen wake lock in a secure
  context. Plain HTTP works on `localhost` only (or with
  `MUSICUS_INSECURE_COOKIES` for tests).
]

== Operation

- *Health:* `GET /api/health` returns `ok` when the process answers and the
  database is readable. No login needed.
- *Version:* `GET /api/version` (no login), `musicus-server --version`, or
  "About Musicus" in the web client name the running release.
- *Backup:* `musicus-server backup --to <file>` writes a consistent
  database copy while the server runs, without updating it; then copy
  `blobs/`. The order matters: blobs referenced by the backup already exist,
  because files are only ever added. Backups and snapshots are plain SQLite
  files, as readable as the data directory.
- *Restore:* with the server stopped, `musicus-server restore --from <file>`
  checks that the file is a Musicus database, keeps the replaced one as
  `snapshots/replaced-<time>.sqlite` and puts the copy in place; `blobs/` is
  not touched. It refuses while a server holds the lock on `musicus.lock`.
  With Docker: `docker compose stop musicus`, then
  `docker compose run --rm musicus restore --from /data/<file>`.
- *Logs:* to standard output; level via `RUST_LOG` (default `info`).
- *Upgrades:* replace the binary or image; pending database updates run
  at start-up. Starting an older release inside the downgrade window works;
  outside it the program refuses with a message naming the oldest release
  that can start (@updates). Before database updates the server writes a
  snapshot to `snapshots/` (newest three kept) and puts it back by itself if
  an update fails; the same program then refuses to retry until
  `musicus-server retry-update` runs.
