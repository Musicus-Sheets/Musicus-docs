#import "../template.typ": *

= Updates, downgrades and platforms (plan) <updates>

#note[
  *This chapter is a plan.* Nothing described here is implemented yet,
  except where a section says "today". Phase 0 of the roadmap
  (@updates-roadmap) must be part of release 1.0.0, because a downgrade can
  only return to releases that already contain the mechanism.
]

*Purpose:* a volunteer administrator updates Musicus by replacing the
container image or the program; every newer release installs over any older
one without data loss, and for a limited time an installation can go back to
an older release by simply starting it. Musicus runs with Docker Compose
(preferred) and as a plain program on Linux, Windows and macOS, including
64-bit Raspberry Pi computers. Requirements: F-OPS-005, F-OPS-006, F-OPS-007,
F-TECH-002, R-OPS-010 to R-OPS-037, R-TECH-004 to R-TECH-007; decision
@d-update-model.

== Today (version 0.1)

#table(
  columns: (auto, 1fr),
  [Topic], [State],
  [Database updates], [Ten forward-only migrations (`0001`–`0010`) applied by `sqlx::migrate!` inside `Db::open`, that is at every start of every command, including `backup`. An older program refuses a database with migrations it does not know.],
  [Distribution], [No release, no tags, no published image. `compose.yaml` builds the image locally for the machine's own architecture (`build: .`).],
  [Version], [0.1.0 for all crates; `musicus-server --version` prints it. No endpoint, nothing in the user interface; the title pages of the user guide and of this document carry a hand-written "0.1".],
  [Backup and restore], [`backup` writes a copy with `VACUUM INTO`, after migrating. Restoring is a manual file copy.],
  [Tests], [CI (`rust.yml`) on Linux x86_64 only.],
)

The existing migrations are irrelevant for the plan: there are no
installations with real data. At the first release they are collapsed into
one baseline for 1.0.0, and every guarantee below starts there.

== Releases and versions

#table(
  columns: (auto, 1fr),
  [Rule], [Meaning],
  [Version numbers], [`major.minor.patch`. A minor release brings features and may contain one database update. A patch release contains fixes only and never a database update (R-OPS-018).],
  [No back-ports], [Old minor releases get no new patches; a fix comes with the next release. The rhythm of releases is irregular.],
  [How an update is installed], [Docker Compose: `docker compose pull && docker compose up -d` (R-OPS-010). Plain program: stop, replace the program file, start.],
  [No update check], [Musicus never asks the internet for new releases (R-OPS-025). Administrators learn about releases from the release page and the user guide site.],
  [Version visible], [`GET /api/version` without login and an "About" view for everyone (R-OPS-033, R-OPS-034); the version on the title pages of the user guide and of this document and on every page of the guide site (R-OPS-035); a git tag per release in the requirements repository (R-OPS-036).],
)

== The downgrade window <updates-window>

An upgrade is always possible, from any release (1.0.0 or later) to any
newer one, in one start (R-OPS-011). Going back is possible to (R-OPS-014):

#table(
  columns: (auto, 1fr),
  [Rule], [Older release that may be started],
  [(a) three minors], [Any release of the three minor releases before the newest one that ran. From 1.5: 1.2.x, 1.3.x, 1.4.x.],
  [(b) where it came from], [The release the installation was upgraded from, for three months after that upgrade, even if it is older than three minors.],
  [(c) patches], [Any release of the same minor, always, however many patches lie between (no database changes, R-OPS-018).],
)

*Example.* An installation runs 1.0.3 and is upgraded directly to 1.5.0 on
1 March. Until 1 June it can return to 1.0.3 (rule b) or to any 1.2, 1.3 or
1.4 release (rule a). From 1 June on only 1.2 to 1.4 remain. 1.5.0 and a
later 1.5.4 can replace each other at any time (rule c).

Outside the window the older release refuses to start, changes nothing and
names the oldest release that can be started (R-OPS-015). Data of a feature
that a release removes stays untouched while a release with that feature may
still start, so it is back after a downgrade (R-OPS-013). Data that only the
newer release can represent is lost on a downgrade and does not come back on
the next upgrade (R-OPS-016). Going back never gives anyone access the newer
release denied (R-OPS-017).

Interpretations to confirm: "minor" counts release lines in release order
across majors (2.0 follows 1.9); after several upgrades in a row
(1.0 → 1.5 → 1.6) each release the installation was upgraded from stays a
target for three months after that upgrade.

== Database updates: additive part and removal part <updates-model>

Every database change is split into two parts that run at different times.

#table(
  columns: (auto, 1fr, 1fr),
  [Part], [Contains], [Runs],
  [Additive], [New tables and columns (nullable or with a default), new indexes, copying existing data into new structures. Old structures stay and are kept up to date by the newer release (written together with the new ones).], [At the first start of the release that brings it.],
  [Rebuild], [Refills the new structures from the old ones (the same statements as the copy step, after emptying them).], [At start, when an older release has used the database since the additive part ran (detected by the version that ran last).],
  [Removal], [Dropping tables and columns, the old half of a rename or type change, destructive rewrites, the data of a removed feature.], [Later, by a newer release, as soon as no release that may still start needs the old structures.],
)

#figure(
  diagram(
    spacing: (9mm, 8mm),
    box-node((0, 0), align(center)[*1.1* \ column `a`], name: <r1>),
    box-node((1.5, 0), align(center)[*1.2* \ adds `b`, copies `a` → `b`, \ writes both], name: <r2>, fill: rgb("#eef3ff")),
    box-node((3, 0), align(center)[*1.3*], name: <r3>),
    box-node((4, 0), align(center)[*1.4*], name: <r4>),
    box-node((5.5, 0), align(center)[*1.5* \ drops `a` \ (removal of 1.2)], name: <r5>, fill: rgb("#fff8e6")),
    edge(<r1>, <r2>, "->"),
    edge(<r2>, <r3>, "->"),
    edge(<r3>, <r4>, "->"),
    edge(<r4>, <r5>, "->"),
    edge((0, 1), (4.6, 1), "-|", [1.1 may still start on the data], label-side: right, stroke: (paint: rgb("#2f5bd3"), thickness: 1.2pt)),
  ),
  caption: [A column `a` replaced by `b` in 1.2. The removal waits until 1.1
    is no longer a downgrade target: at the start of 1.5 the three previous
    minors are 1.2 to 1.4. Had the installation come from 1.1 less than three
    months earlier, 1.5 would keep `a` until that time has passed.],
)

Rules for whoever writes a database update:

- A removal is due when every release that may still start (@updates-window)
  is at least the release that brought the update. Running it raises the
  oldest release allowed to start to that release.
- Values that older releases do not know (a new role, a new region kind, a
  new ink format) are new-only data unless the older releases already
  tolerate unknown values. Error codes already have such a fallback
  (`unknown`); the other stored enums (`Role`, `RegionKind`, …) get one in
  phase 0.
- *Restrictions count as removals* (R-OPS-017). An older release ignores a
  restriction it does not know and would grant too much. The newer release
  therefore writes the effect of the restriction into the data the older one
  reads (an expired grant is removed from the old grant table), or, where
  that is impossible, raises the oldest release allowed to start as soon as
  the restriction is first used, which shortens the window. The release
  notes name such a change.
- Derived data (search index, system layouts) is rebuilt after any start on
  a database last used by another release.
- All release updates stay in the program for ever, because any older
  release may be upgraded (R-OPS-011). The removal statements therefore live
  in the update files; the database only records which parts have run.

== Version marker <updates-marker>

A small set of tables (proposed names) replaces `_sqlx_migrations`:

#table(
  columns: (auto, 1fr, auto),
  [Table / key], [Meaning], [Written],
  [`musicus_meta.last_version`], [The release that last started successfully.], [every start],
  [`musicus_meta.oldest_allowed`], [The oldest release allowed to start; the check an older release makes before anything else.], [when a removal runs or a restriction forces it],
  [`musicus_meta.marker_format`], [Version of these tables, so that every release from 1.0 on can read them.], [baseline],
  [`musicus_updates`], [One row per applied update: name, release, kind (`release` or `preview`), time of the additive part, time of the removal part (empty while pending), the previews it contains.], [when a part runs],
  [`musicus_upgrades`], [History: from release, to release, time. Source of rule (b) of the window.], [every upgrade and downgrade],
)

== Start-up sequence

Every command that uses the database follows the same order; `backup`
stops after step 1 (R-OPS-021).

+ Open the database without changing it and read the marker. An empty data
  directory gets the 1.0 baseline and all updates in one go (removals as
  the window allows), with no snapshot.
+ A release build with preview updates refuses to start (R-OPS-024).
+ If the own version is older than `oldest_allowed`: stop with a message
  that names the oldest possible release (R-OPS-015); nothing is written.
+ Plan the work: additive parts of own updates not yet applied, rebuilds
  (an older release ran since an update was applied), and due removals.
  Updates the program does not know (it is the older release) are ignored.
+ If there is work: check free space, write a snapshot
  `snapshots/musicus-<old version>-<time>.sqlite` with `VACUUM INTO`, keep
  the three newest (R-OPS-019).
+ Run each part in its own transaction and record it.
+ On any failure: close the database, put the snapshot back (also removing
  `-wal` and `-shm`), and stop with a message that the update failed, the
  data is unchanged and which release ran before (R-OPS-020). A note in the
  data directory keeps a restart loop (Docker restart policy) from writing
  more snapshots of the same state.
+ Write `last_version` and, for an up- or downgrade, a row in
  `musicus_upgrades`; rebuild derived data if another release ran last;
  start serving.

#why[
  An automatic snapshot plus automatic restore turns a failed update into
  "start the old image again". Files need no snapshot: blobs are immutable
  and only added (R-FILE-004), so every snapshot stays consistent with the
  blob folder; a future clean-up of unused files must count files
  referenced by kept snapshots as used (R-FILE-009).
]

== Backup, restore and export

- `backup` copies the database as it is and never applies updates
  (R-OPS-021); today it migrates first.
- New command `restore --from <file>` for a stopped installation: checks
  that the file is a Musicus database, keeps the replaced database under a
  new name, removes `-wal`/`-shm` and puts the copy in place (R-OPS-022).
  The next start upgrades it if it is older.
- Backups, snapshots and exports are not encrypted, like the database
  itself (plain SQLite, passwords as Argon2 hashes). The user guide says
  that they need the same care as the data directory (R-OPS-037).

== Database updates during development <updates-preview>

Developers keep their local demo databases across branches; releases ship
one update each. Proposed workflow (details are design to be confirmed
during implementation, R-OPS-023):

+ A branch that changes the database adds a *preview update*
  `migrations/preview/NNNN-<topic>.sql`, with an additive and a removal
  section. Development builds apply previews like release updates.
+ A preview that has been merged is never edited again; a correction is a
  new preview.
+ The release script merges all previews into `migrations/<version>.sql`,
  writes the list of contained previews into its header and deletes the
  preview files.
+ A database that has applied all listed previews marks the release update
  as applied without running it. One that applied only some of them is a
  development database in an unclear state: the program says so and the
  developer starts from a fresh demo database.
+ Release builds refuse to start when preview files are present
  (R-OPS-024); the release workflow fails before publishing.

#why[
  `sqlx::migrate!` refuses a database with an applied migration it does not
  know and cannot merge files, so previews could not be combined into one
  release update without breaking every development database. A small own
  runner (a few hundred lines) also carries the marker and the
  additive/removal split. It must ship in 1.0.0; the developer databases of
  today (`0001`–`0010` applied) are recognised once and marked as having
  the 1.0 baseline.
]

== Platforms <updates-platforms>

#table(
  columns: (auto, auto, auto, 1fr),
  [System], [Way], [Architecture], [State today → plan],
  [Linux server or PC], [Docker Compose], [amd64], [Works with a local build → published image (R-OPS-028).],
  [Raspberry Pi 3, 4, 5 or newer, 64-bit OS], [Docker Compose], [arm64], [Buildable (`docker buildx --platform linux/arm64`), never tested → published arm64 image; smoke test on a Pi (R-OPS-027).],
  [Windows, macOS with Docker Desktop], [Docker Compose], [amd64, arm64], [Uses the Linux images → covered by multi-architecture images.],
  [Linux], [plain program], [x86_64, arm64], [Works (needs `--web-dir`) → program download (R-OPS-029).],
  [Windows], [plain program], [x86_64], [Blocked: uploads fail (finding 1) → fix, CI, download.],
  [macOS], [plain program], [arm64], [Never built → CI, download.],
)

32-bit systems and Raspberry Pi models before the 3 are not supported.
The exact architectures per system are a proposal (R-OPS-026).

=== Portability findings

#table(
  columns: (auto, 1fr, auto),
  [\#], [Finding], [Action],
  [1], [`blobs.rs` (`sync_dir`) syncs the blob folder after a rename with `File::open(dir)?.sync_all()`. Folders cannot be opened like that on Windows, so every upload would fail.], [sync the folder on Unix only],
  [2], [Graceful shutdown listens for SIGTERM only under `cfg(unix)`; Ctrl+C works everywhere. Fine as it is.], [none],
  [3], [The plain program needs the web client in a separate folder (`--web-dir`).], [embed it (R-OPS-030)],
  [4], [The default data directory is `data`, relative to the working directory, which depends on how the program is started.], [usual folder per OS (R-OPS-031)],
  [5], [CI builds and tests only on Linux x86_64; the image is built for the host architecture only.], [CI matrix, multi-arch images (R-OPS-032)],
  [6], [A blob is committed with "exists? else rename". On Windows a rename onto a file that is open (being served) fails, and two simultaneous uploads of the same new file race.], [treat "target exists" after a failed rename as success; test on Windows],
  [7], [The backup target path reaches SQLite through `to_string_lossy`; a path that is not valid UTF-8 would be changed.], [refuse such paths with a clear message],
  [8], [A Pi 3 has 1 GB of memory and is slow to compile Rust; performance targets were measured on a laptop, not on any Pi. Snapshots take space on the SD card.], [build elsewhere; measure on a Pi 3],
  [9], [Building on Windows needs a C compiler for `ring` (TLS) and SQLite (assumption, check in CI).], [CI on Windows],
)

== Prepared for replacement (F-TECH-002)

A different database or an object store is not planned. The code is only
prepared, so that a later switch is contained:

- Storage modules per data area (library, access, annotations, users,
  layouts, import); handlers contain no SQL; the access rule stays one
  definition and is applied inside the storage functions (R-TECH-004).
- The file store offers read, range read, write and existence checks and no
  longer hands out file paths (R-TECH-005).
- One module wraps the server's PDF library (hayro) for page count,
  thumbnail and rendering (R-TECH-006).
- A conformance test suite for each of the three states what a replacement
  must keep (R-TECH-007).

R-TECH-001 (embedded SQLite) is unchanged; replacing SQLite would need its
change with the user's consent.

== Tests

- *Fixtures per release:* each release creates a data directory with a
  script through the API (users, groups, grants, pieces, parts, files,
  programmes, markings, layout corrections, an import batch) and keeps it as
  a release asset.
- *Upgrade:* the current program opens the fixture of every earlier minor
  and passes the same data checks (R-OPS-011, R-OPS-012).
- *Downgrade:* the current program upgrades the fixtures of the previous
  three minors, writes new data, then the previous release images start on
  the result (R-OPS-014, R-OPS-016, R-OPS-017); outside the window the start
  is refused unchanged (R-OPS-015); the three-month rule is tested with a
  manipulated upgrade time.
- *Failure:* an update that fails on purpose ends with the snapshot restored
  (R-OPS-020).
- *Release check:* no database update in a patch release, no preview files,
  version on the title pages, requirements tag present.

== Roadmap <updates-roadmap>

#table(
  columns: (auto, 1fr, auto),
  [Phase], [Content], [Effort],
  [0 (in 1.0)], [Own update runner with marker tables, additive/removal/rebuild parts, refusal message; preview folder, release merge script and the 1.0 baseline replacing `0001`–`0010`], [L],
  [0 (in 1.0)], [Snapshot before updates, automatic restore, `backup` without updating, `restore` command], [M],
  [0 (in 1.0)], [`GET /api/version`, "About" view, version on the title pages from the release version], [S],
  [0 (in 1.0)], [Release workflow: multi-arch image with version tags, Compose file using it, requirements tag, release check], [M],
  [0 (in 1.0)], [Fallback values for stored enums; Windows folder sync fix (finding 1)], [S],
  [1], [CI on Linux arm64, Windows and macOS; program downloads; web client inside the program; OS data folder (R-OPS-029 to R-OPS-032)], [M],
  [2], [Fixtures and the upgrade/downgrade test matrix (meaningful from the second release)], [M],
  [3], [Storage modules, file store interface, PDF engine module, conformance suites (F-TECH-002)], [L],
)

Not part of this plan: a notice for open browser tabs after an update
(older client against newer server), a portable export format, a second
database or file store implementation.
