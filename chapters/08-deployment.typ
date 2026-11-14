#import "../template.typ": *

= Build and deployment <deployment>

== Build

The server is a normal Cargo binary (`cargo build --release -p
musicus-server`). The web client is built by the Dioxus CLI:

+ `scripts/fetch-pdfjs.sh` downloads the pinned pdf.js release from npm,
  verifies its SHA-512 checksum, and copies the legacy build into
  `crates/musicus-web/public/vendor/pdfjs/` (not committed).
+ `dx bundle --platform web --package musicus-web --release` compiles the
  client to WebAssembly, runs `wasm-bindgen` and `wasm-opt`, bundles
  `bridge.js`, the stylesheet and the `public/` folder, and writes
  precompressed copies into `target/dx/musicus-web/release/web/public`.
+ The server serves this folder when started with `--web-dir`.

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

== Container image

The `Dockerfile` has three stages:

#table(
  columns: (auto, 1fr),
  [Stage], [Purpose],
  [`dx`], [Installs the Dioxus CLI (slow, therefore its own cached stage).],
  [`build`], [Fetches pdf.js, bundles the web client, builds the server.],
  [runtime], [`gcr.io/distroless/cc-debian12:nonroot`: only the server binary and the web assets; runs as UID 65532; data in the volume `/data`; `HEALTHCHECK` runs `musicus-server healthcheck`.],
)

#why[
  The runtime image is distroless: no shell, no package manager, not root.
  It shrinks the image to about 70 MB and removes most of what an attacker
  could use after a compromise. The price is that health checks and backups
  must be built into the server binary. See @d-distroless.
]

`compose.yaml` runs the image with one named volume. The optional profile
`https` adds Caddy (`deploy/Caddyfile`), which obtains and renews a Let's
Encrypt certificate and forwards to the server; the server then trusts
`X-Forwarded-For` (`MUSICUS_TRUST_PROXY`) and should only listen on
localhost.

#note[
  HTTPS is required in practice, not optional: browsers only keep the
  `Secure` session cookie and grant the screen wake lock in a secure
  context. Plain HTTP works on `localhost` only (or with
  `MUSICUS_INSECURE_COOKIES` for tests).
]

== Operation

- *Health:* `GET /api/health` returns `ok` when the process answers and the
  database is readable. No login needed.
- *Backup:* `musicus-server backup --to <file>` writes a consistent
  database copy while the server runs; then copy `blobs/`. The order matters:
  blobs referenced by the backup already exist, because files are only ever
  added.
- *Logs:* to standard output; level via `RUST_LOG` (default `info`).
- *Upgrades:* replace the binary or image; pending migrations run at
  start-up.
