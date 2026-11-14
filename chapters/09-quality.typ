#import "../template.typ": *

= Tests and quality checks <quality>

#table(
  columns: (auto, auto, 1fr),
  [Level], [Where], [What it covers],
  [Unit], [`musicus-api`], [Encoding round trips including coordinate extremes, size of a typical page, rejection of malformed layers, merge cases, `double_option` and roles.],
  [Unit], [`musicus-server`], [Blob store (hashing, deduplication, size limit, cleanup), LRU cache, login limiter, cookie parsing, PDF processing, FTS query building, date validation.],
  [Integration], [`musicus-server/tests/api.rs`], [The full router against a temporary data directory: login, sessions and CSRF; access control and 404s; Range and ETag; upload versioning; annotation revisions, conflicts, privacy and migration; programmes and search; user administration.],
  [End to end], [`e2e/smoke.mjs`], [Playwright drives Chromium against a running server: admin set-up, upload, groups, invites, search, prefetch, rendering, drawing, saving, reload, page turns, privacy, and no browser errors.],
)

Commands:

```sh
cargo test
cargo clippy --all-targets
cargo clippy -p musicus-web --target wasm32-unknown-unknown
node e2e/smoke.mjs <invite-url> some.pdf <screenshot-dir>
```

The integration tests call the router directly (`tower::ServiceExt::oneshot`)
without opening a port, so they run in parallel and need no set-up.

== Prototypes

`prototypes/` contains the benchmarks that tested the design's
assumptions (burst downloads, access check cost, annotation sizes, Argon2
cost, hayro speed and size, SQLite versus PostgreSQL). They are not built
with the workspace and not part of the product; they are kept so the
numbers quoted in this document can be reproduced.
