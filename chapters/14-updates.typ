#import "../template.typ": *

= Updates, downgrades and platforms <updates>

#note[
  *This chapter is mostly a plan.* Implemented are the own update runner
  with the version marker, the downgrade window, the preview updates with
  their merge script, the development migrations as previews
  (@updates-runner, first row of phase 0), and the database check with the
  schema snapshot and the `db-change` notice (@updates-ci); everything else is planned, except where a section says
  "today". Phase 0 of the roadmap
  (@updates-roadmap) must be part of release 1.0.0, because a downgrade can
  only return to releases that already contain the mechanism.
]

*Purpose:* a volunteer administrator updates Musicus by replacing the
container image or the program; every newer release installs over any older
one without data loss, and for a limited time an installation can go back to
an older release by simply starting it. Musicus runs with Docker Compose
(preferred) and as a plain program on Linux, Windows and macOS, including
64-bit Raspberry Pi computers. Requirements: F-OPS-005, F-OPS-006, F-OPS-007,
F-OPS-008, F-TECH-002, R-OPS-010 to R-OPS-049, R-TECH-004 to R-TECH-007; decision
@d-update-model.

== Today (version 0.1, before the first release)

#table(
  columns: (auto, 1fr),
  [Topic], [State],
  [Database updates], [The own update runner (@updates-runner) inside `Db::open`, that is at every start of every command, still including `backup`. The development migrations `0001`–`0010` are the first preview updates; databases that applied them are recognised once. No release update file exists yet. No snapshot yet.],
  [Distribution], [No release, no tags, no published image. `compose.yaml` builds the image locally for the machine's own architecture (`build: .`).],
  [Version], [0.1.0, written once as the workspace `version` of the root `Cargo.toml` (all crates inherit it). Implemented (phase 0): `musicus-server --version`, public `GET /api/version` and the "About Musicus" view print it; the title pages of the user guide and of this document take it from their build (`build.sh` → `typst --input version=…`), the guide site passes each release's version.],
  [Backup and restore], [`backup` writes a copy with `VACUUM INTO`, after applying pending updates. Restoring is a manual file copy.],
  [Tests], [CI (`rust.yml`) on Linux x86_64 only.],
)

The development migrations were irrelevant for the plan (there are no
installations with real data). They are now the previews 0001–0010; the
release of 1.0.0 merges them into its update `1.0.0.sql`, which the
maintainer simplifies by hand to the final schema at that release
(`RELEASING.md`). Every guarantee below starts with 1.0.0.

== Releases and versions

#table(
  columns: (auto, 1fr),
  [Rule], [Meaning],
  [Version numbers], [`major.minor.patch`. A minor release brings features and may contain one database update. A patch release contains fixes only, never a database update (R-OPS-018) and never a new kind of stored value (R-OPS-041).],
  [No back-ports], [Old minor releases get no new patches; a fix comes with the next release. The rhythm of releases is irregular.],
  [How an update is installed], [Docker Compose: `docker compose pull && docker compose up -d` (R-OPS-010). Plain program: stop, replace the program file, start.],
  [No update check], [Musicus never asks the internet for new releases (R-OPS-025). Administrators learn about releases from the release page and the user guide site.],
  [Version visible], [`GET /api/version` without login and an "About" view for everyone (R-OPS-033, R-OPS-034); the version on the title pages of the user guide and of this document and on every page of the guide site (R-OPS-035); a git tag `vX.Y.Z` per release in the requirements repository and in both documentation repositories, created by hand after the release pipeline succeeded (R-OPS-036). The one source of the number is the workspace `version` in `Cargo.toml`; a release raises it and tags `vX.Y.Z` on that commit.],
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

*Counting (confirmed).* "The three previous minor releases" are the three
release lines released before the current one, in release order, whatever
their numbers. 1.10 may follow 1.9; then 2.0 follows 1.10, not 1.9. With
1.8 → 1.9 → 1.10 → 2.0 the targets from 2.0 are 1.10, 1.9 and 1.8. Any
patch of such a line may be started. After several upgrades in a row
(1.0 → 1.5 → 1.6) each release the installation was upgraded from stays a
target for three months after its own upgrade. The window always holds;
nothing shortens it, not even a restriction of access.

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
  tolerate unknown values. Since phase 0 every stored enum and format has
  such a fallback (@updates-fallbacks); a new value is allowed only where
  the fallback covers it.
- *Fail closed* (R-OPS-017). Anything an older release cannot fully
  understand must be invisible to it. A restriction introduced by a newer
  release (for example a grant with an expiry date) is stored so that the
  older release does not see the restricted item at all: the newer release
  moves the item out of the structures the older release reads (the grant
  leaves the old grant table and lives in a new table with its expiry).
  After a downgrade the older release grants no access for it: less access,
  never more. Being new-only data, the item does not come back on the next
  upgrade (R-OPS-016); librarians grant it again by hand. The release notes
  of a release that introduces a restriction say so. The window is never
  shortened.
- Derived data (search index, system layouts) is rebuilt after any start on
  a database last used by another release.
- All release updates stay in the program for ever, because any older
  release may be upgraded (R-OPS-011). The removal statements therefore live
  in the update files; the database only records which parts have run.

== Fallbacks for unknown stored values <updates-fallbacks>

An older release reads what a newer one wrote. The types of the program
stay exact: there are no catch-all "unknown" variants, because they would
only move the problem from reading a value to every place that uses it.
Instead each value that a newer release could extend is handled where it
is read: the value fails to parse, and that place decides once what this
means. The decision fails closed: never more access, never a wrong view, no
server error. A value that did not parse never exists in the program, so it
cannot be written back (R-OPS-041, R-OPS-017).

#table(
  columns: (auto, 1fr),
  [Stored value], [Where it is read, and what an unknown value means there],
  [Role (`users.role`)], [Login, sessions and invite links: refused, as for a disabled account. It is not treated as a member, because a new role may have fewer rights. The admin's user list shows the account as "Unknown role" and offers no role change; other changes keep the stored role. A request naming an unknown role is rejected as malformed. If every admin had one, `musicus-server create-admin` creates a new admin.],
  [Pages and corrections of system layouts (e.g. a band kind it does not know)], [Each page and each correction is read on its own; one that does not parse is shown as a whole page. The system editor says the page was saved by a newer version and offers only resetting a correction. A request with an unknown band kind is rejected as malformed.],
  [Layout state, a layout it cannot read at all], [Treated as a failed detection (whole pages). The background detection never redoes a layout of a newer algorithm.],
  [Ink format version, new kinds of marks], [A version check when the reader decodes the page: it shows the page without its markings, says why, and does not let anyone draw on that page, so the stored markings stay as they are. The server never decodes stored pages. A new kind of mark needs a new format version.],
  [Import file and item states, proposals and changes it cannot read], [The file, piece or part is left out of the review, the proposals and the import, and its row is never changed.],
  [Error codes stored in import problems], [Shown as an unknown error (`unknown`, the forward-compatible error code of the API).],
  [Reader view settings, import language], [The default (no effect on access).],
)

The full inventory, with the function that reads each value, is kept in the
agent documentation (`docs/agents/data-model.md`, "Stored values"). Tests write
such values directly into the database and check that the requests above
behave as described. Not yet covered: data of real releases (the test
matrix, phase 2).

== Version marker <updates-marker>

A small set of tables replaces `_sqlx_migrations` (implemented; marker
format 1, later formats only add columns and keys, so every release from
1.0 on can read them):

#table(
  columns: (auto, 1fr, auto),
  [Table / key], [Meaning], [Written],
  [`musicus_meta.last_version`], [The release that last started successfully.], [every start],
  [`musicus_meta.oldest_allowed`], [The oldest release allowed to start; the check an older release makes before anything else.], [when a removal runs],
  [`musicus_meta.marker_format`], [Version of these tables, so that every release from 1.0 on can read them.], [first start],
  [`musicus_meta.last_updates`], [The names of the updates (and merged previews) the program that last started knew; an update missing from it needs a rebuild.], [every start],
  [`musicus_updates`], [One row per applied update: name, release, kind (`release` or `preview`), time of the additive part, of the last rebuild and of the removal part (empty while pending or when there is none), the previews it contains, the program that applied it.], [when a part runs],
  [`musicus_upgrades`], [History: from release, to release, time. Source of rule (b) of the window.], [every upgrade and downgrade],
)

== The update runner <updates-runner>

Implemented in `crates/musicus-server/src/updates/` (decision record
a-update-runner in `docs/agents/decisions.md`).

#table(
  columns: (auto, 1fr),
  [Topic], [Design],
  [Update files], [One SQL file per update. Header comments, optionally `-- @previews: 0001-a 0002-b` (merged release updates only), then the sections `-- @additive` (required), `-- @rebuild` and `-- @removal`, each at most once and in this order. Any other line starting with `-- @` is an error, so a typo cannot move a removal into the additive part. Release updates are named after their release (`1.3.0.sql`); a patch version is refused (R-OPS-018). `build.rs` embeds all files.],
  [Release order], [`migrations/releases.txt` lists the released lines (`1.0`, `1.1`, …) in release order and is compiled into each program, so a newer program knows every earlier line. It is needed only to count "the three previous lines"; versions are compared by number, which equals release order because there are no back-ports. A line not listed yet is the development line after the last one. An older program decides only by comparing its line with `oldest_allowed`; it never needs to know newer lines.],
  [Window], [Oldest line kept = the first of the three lines before the program's line in `releases.txt` (or the program's own line), lowered by every release the installation was upgraded from less than three calendar months ago (UTC), including the upgrade the current start performs. A removal of a release update is due when that line is at least the update's release; it runs only in the newest program that ever ran on the database (no newer version recorded, no unknown update applied) and raises `oldest_allowed` to the update's release.],
  [Rebuild], [An update whose removal is pending is rebuilt when the program that last started did not know it (`last_updates`); this also covers switching branches, where all programs share one version number.],
  [Previews], [A release update whose listed previews all ran is recorded without running; if only some ran, the program reports an unclear development database and stops.],
  [Execution], [Rebuilds, then additive parts, then removals. Each part runs with its record in one transaction, foreign keys off around it and `foreign_key_check` before the commit (SQLite's table-rebuild procedure). Nothing is written before the refusal checks; a refused start leaves the database file byte-identical.],
  [Refusal], [For example: "This data was last used by Musicus 1.5.0. Musicus 1.1.0 can no longer use it; start Musicus 1.2.0 or newer." printed as the last line, exit code 1 (R-OPS-015).],
  [Development migrations], [The sqlx migrations 0001–0010 are the previews `0001-init` to `0010-german-key-spellings`, text unchanged inside `-- @additive` (0009 without its own transaction statements; the runner turns foreign keys off). Destructive steps in them are acceptable before 1.0: development databases have no downgrade guarantee. They give exactly the schema of the sqlx migrations (checked by a test). A database with sqlx migrations 1 to k applied and no marker is recorded once as having the previews 0001 to k; the remaining previews run; the sqlx table is kept.],
  [Merge simplification], [The release script first appends the previews in order: the reference. Then it applies safe rules to the additive part: `ADD COLUMN` and `RENAME COLUMN` folded into a `CREATE TABLE` of the same cycle, and tables, indexes, triggers, views and columns that were created and dropped again removed. A rule fires only if every statement between that mentions the object is another `CREATE TABLE` or `CREATE INDEX`; other SQL stays as written. The result is kept only if it gives the same schema (columns, constraints, indexes, triggers, views) and the same rows as the appended version, on an empty database with the earlier release updates and, with `--fixture`, on a copy of a database of the previous release; otherwise the appended version is written. There is no special path for 1.0: its update is simplified by hand at the release and checked with `--compare`.],
)

Rule for update authors: while a removal is pending, the release that
brought the update and every later one write old and new structures, and
must tolerate the old ones being gone, because running the removal lets
that release start again.

Limits: derived data rebuilt after another program ran is only the part
search index (system layouts are not re-checked); a due removal runs only
at a start; a stored version that cannot be read blocks removals; the
program version stays 0.1.0 until the first release sets it.

== Start-up sequence

Every command that uses the database follows the same order; `backup`
stops after step 1 (R-OPS-021). Implemented today: steps 1 to 4, 6 and 8
without the snapshot and its restore, without the early listener, and with
`backup` still running all steps. `serve` first opens the listener and
answers every request with HTTP 503 `server_starting` (with
`Retry-After`) until the last step is done (R-OPS-045); `/api/health`
reports `ok` only then.

+ Open the database without changing it and read the marker. An empty data
  directory gets all updates in one go (removals as
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
  switch the router from `server_starting` to normal service.

#why[
  An automatic snapshot plus automatic restore turns a failed update into
  "start the old image again". Files need no snapshot: blobs are immutable
  and only added (R-FILE-004), so every snapshot stays consistent with the
  blob folder; a future clean-up of unused files must count files
  referenced by kept snapshots as used (R-FILE-009).
]

== Open clients during shutdown, start and update <updates-clients>

Tablets stay open for hours; an update must neither lose a marking nor
interrupt a musician (F-OPS-008).

#table(
  columns: (auto, 1fr, 1fr),
  [Situation], [Server], [Web client],
  [Stop signal (R-OPS-043)], [Accepts no further changes; answers 503 `server_shutting_down` with `Retry-After`; finishes writes in progress, checkpoints and closes the database, exits.], [Banner "Server is shutting down"; actions that need the server are blocked (R-OPS-044).],
  [Unreachable (R-OPS-044)], [—], [Banner "Server not reachable"; what is loaded (an open part) stays readable; drawing continues.],
  [Starting (R-OPS-045, R-OPS-046)], [Listens at once; 503 `server_starting` until snapshot, updates and checks are done.], [Banner "Server is starting"; polls a status endpoint and removes the banner by itself when the server is ready.],
  [Unsaved markings (R-OPS-047)], [—], [Kept in the open tab's memory, saved automatically when the server is back (usual merge); nothing stored on the device (R-SEC-001); closing the tab with unsaved markings while the server is away warns (`beforeunload`).],
  [New version (R-OPS-048)], [`GET /api/version` returns the new version.], [Notice "Musicus has been updated"; saves what is pending, reloads automatically at a safe moment, never while reading or drawing.],
)

Consequences: the start-up sequence opens the listener before the
database updates; two new error codes `server_shutting_down` and
`server_starting` join `ErrorCode` (with English messages and catalogue
texts); the graceful shutdown of today (R-OPS-008) keeps the listener open
during the drain so clients get the dedicated answer. The Docker health
check reports the container as starting meanwhile; long updates on a Pi
may need a longer `start-period`.

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
one update each. Implemented (R-OPS-023, R-OPS-024; details in
@updates-runner):

+ A branch that changes the database adds a *preview update*
  `migrations/preview/NNNN-<topic>.sql`, with an additive and a removal
  section. Development builds apply previews like release updates, but
  never their removal sections: another branch's program may still use
  the old structures. The removal runs with the merged release update.
+ A preview that has been merged is never edited again; a correction is a
  new preview.
+ The release script `scripts/release-migrations.py <version>` merges all
  previews into `migrations/<version>.sql`, writes the list of contained
  previews into its header (`-- @previews:`), deletes the preview files
  and adds the release line to `migrations/releases.txt`. It simplifies
  the merged update where that is provably safe (@updates-runner). For
  1.0.0 only, the maintainer then simplifies the update by hand to the
  final schema and checks it against the appended version.
+ A database that has applied all listed previews marks the release update
  as applied without running it. One that applied only some of them is a
  development database in an unclear state: the program says so and the
  developer starts from a fresh demo database.
+ Release builds (built with `MUSICUS_RELEASE_BUILD=1`) refuse to start
  when preview files are present (R-OPS-024); every other build, also a
  local Docker image, is a development build. The release pipeline that
  fails before publishing (@updates-release) is still planned.
+ The merge happens in a release pull request from a branch
  `release/<version>`; only such a pull request may delete previews and
  add the merged update (@updates-ci).

#why[
  `sqlx::migrate!` refuses a database with an applied migration it does not
  know and cannot merge files, so previews could not be combined into one
  release update without breaking every development database. A small own
  runner (a few hundred lines) also carries the marker and the
  additive/removal split. It must ship in 1.0.0; the developer databases
  with `0001`–`0010` applied are recognised once and marked as having the
  previews 0001–0010 (done).
]

== Checks in continuous integration <updates-ci>

The rules above are enforced by three checks. The database check and the
`db-change` notice are implemented (workflow `Database`,
`.github/workflows/database.yml`, jobs `db-check` and `db-change`); the
release check comes with the release pipeline (@updates-release).

#table(
  columns: (auto, 1fr, auto),
  [Check], [Fails (or reports) when], [Kind],
  [Database check (R-OPS-038)], [In a normal pull request: a database update file is added outside `migrations/preview/` (release updates are reserved for release pull requests); a released update or a preview already on `main` is modified or deleted (changes go into a new preview); the schema snapshot is outdated, or changed without a new preview.], [blocking],
  [`db-change` notice (R-OPS-039)], [A pull request adds a preview: label `db-change` and the note "This PR changes the database; the next release must be a minor release (x.Y.0), not a patch."], [informational],
  [Release check (R-OPS-040)], [On `release/<version>`: a patch version with any preview or a database update for this version; a minor or major version whose merged update `migrations/<version>.sql` does not list exactly the removed previews, or with previews left.], [blocking],
)

*Schema snapshot.* `scripts/db-schema.sh` creates an empty database with
the program's own update runner, exactly as Musicus does at its first
start, and writes its structure to `crates/musicus-server/schema.sql`:
every table, virtual table, index, trigger and view as one block, sorted by
table, kind and name, with the comments of the stored SQL removed and one
column or constraint per line. Left out are the runner's marker tables,
SQLite's internal tables and the shadow tables of the search indexes. A
developer who adds a preview runs the script and commits the file with it;
`cargo test` and the job `db-check` (`scripts/db-schema.sh --check`) fail
while it is out of date. The diff also shows every schema change in
review. Code that expects a column no update creates is caught by the
`test` job.

*Rules of the database check* (`scripts/check-db-changes.py`, comparing the
pull request with its base branch): a file added under `migrations/`
outside `preview/` (also `releases.txt`, which only the release script
writes) fails, as does a preview not named `NNNN-<topic>.sql`; a file of
`migrations/` that is on the base branch must not be modified, renamed or
deleted; `schema.sql` must not change without a new preview (except in a
pull request that changes the snapshot's generator). In addition, a new
preview's number must be higher than every preview on the base branch,
so that development databases apply previews in the order they were
merged: a branch that lost the race renumbers its preview. In the merge
queue the pull requests of a group are checked together.

*The `db-change` notice* labels the pull request `db-change` (the label is
created if missing) and writes one comment, kept up to date on later pushes
and removed together with the label when the pull request no longer adds a
preview. It never fails. Pull requests from forks only get the note in the
job summary, because their token cannot write.

*Release pull requests* are recognised by the branch name
`release/<version>` (for example `release/1.3.0`). Only they may delete
previews and add the merged update; the database check skips its rules for
them (the release check covers them) but still compares the schema
snapshot, which the merge must leave unchanged.

*Limitation.* No check sees new kinds of values written into existing
columns: a new role, a new system layout region kind, a new ink format
version, a new error code stored in import problems. A patch must not
write such values either (R-OPS-041). This is covered by the test data of
every release checked against older releases (upgrade/downgrade matrix),
by fallbacks for unknown values on every stored enum (@updates-fallbacks),
and by the release checklist line "patch: no new stored values (new enum
variants, format versions) — R-OPS-041" (`RELEASING.md`, step 7).

*Which check runs where* (R-OPS-032). Only what can differ between
platforms runs on every supported system; everything else runs once, on
Linux x86_64.

#table(
  columns: (1fr, 1fr),
  [Every supported platform], [Linux x86_64 only],
  [Rust tests (`cargo test`); release build of the program; short start (smoke) test of the built program. Linux x86_64 and arm64, Windows x86_64, macOS arm64 block; macOS x86_64 runs but does not block (R-OPS-042).], [Submodule pinning, agent-docs check, UI-literals lint, rustfmt, clippy (host and wasm32), documentation builds, database check (R-OPS-038), `db-change` notice, release check.],
)

The container image is built for linux/amd64 and linux/arm64 at least for
every release (R-OPS-028).

== Release pipeline (planned) <updates-release>

A release is built, checked and published by one pipeline that publishes
nothing unless everything succeeded (R-OPS-049, user decision).

#table(
  columns: (auto, 1fr),
  [Run], [When and what],
  [Dry run], [On the pull request from `release/<version>`: stage 1 completely, nothing is published.],
  [Real run], [Starts automatically when a `release/<version>` pull request is merged into `main`: stage 1, then stage 2.],
  [Stage 1 (temporary)], [Results are workflow artifacts that expire. The workspace version in `Cargo.toml` equals the version in the branch name; all tests, lints, documentation and requirements checks; the release check (R-OPS-040); program build and smoke test per platform (R-OPS-029, R-OPS-032); multi-arch images built, not pushed (R-OPS-028); user guide and technical documentation built and their title pages checked to show the release version (R-OPS-035); the complete guide website built, including the new release.],
  [Stage 2 (publish)], [Only if stage 1 is entirely green, in this order, least reversible last: push the images with their version tags; create the tag `vX.Y.Z` in the main repository; create the GitHub release with the program archives and `SHA256SUMS`; deploy the guide website. Every step is idempotent (it skips what already exists), so a failed publish run is simply run again.],
  [Failure], [Nothing is published, the artifacts are discarded; fix and run again.],
  [By hand afterwards], [Tags `vX.Y.Z` in `docs/requirements`, `docs/technical` and `docs/user-guide` on the commits the release points to (R-OPS-036); no token for the documentation repositories in the pipeline.],
)

The website workflow of today (`user-guide-pages.yml`, started by a
published release) becomes the last step of the pipeline; its manual test
build stays. The warning of `build-guide-site.sh` when an older release's
tag differs from its workspace version stays a warning; the blocking check
is the one in stage 1. Until the pipeline exists, `RELEASING.md` lists the
same steps to do by hand.

#why[
  Publishing is the only part that cannot be taken back: an image tag that
  was pulled or a release that was announced stays out there. Building and
  checking everything first, and publishing in the order from easiest to
  hardest to undo, means a failure leaves either nothing or a state that a
  re-run completes.
]

== Platforms <updates-platforms>

#table(
  columns: (auto, auto, auto, 1fr),
  [System], [Way], [Architecture], [State today → plan],
  [Linux server or PC], [Docker Compose], [amd64], [Works with a local build → published image (R-OPS-028).],
  [Raspberry Pi 3, 4, 5 or newer, 64-bit OS], [Docker Compose], [arm64], [Buildable (`docker buildx --platform linux/arm64`), never tested → published arm64 image; smoke test on a Pi (R-OPS-027).],
  [Windows, macOS with Docker Desktop], [Docker Compose], [amd64, arm64], [Uses the Linux images → covered by multi-architecture images.],
  [Linux], [plain program], [x86_64, arm64], [Works (needs `--web-dir`) → program download (R-OPS-029).],
  [Windows], [plain program], [x86_64], [Upload blocker fixed (finding 1), compiles, never run → CI, download.],
  [macOS (Apple silicon)], [plain program], [arm64], [Never built → CI, download.],
  [macOS (Intel), _should_], [plain program], [x86_64], [Never built → built and smoke-tested in CI, not a release blocker (R-OPS-042).],
)

32-bit systems and Raspberry Pi models before the 3 are not supported.
Windows on ARM is not required (if it works, fine).

=== Program downloads

Each published release offers program archives built by CI (R-OPS-029):
`linux-x86_64`, `linux-arm64`, `windows-x86_64` (`.zip`),
`macos-arm64` and `macos-x86_64`, plus a `SHA256SUMS` file
(`sha256sum -c SHA256SUMS`). The program contains the web client, so it
is a single file (R-OPS-030), and without `--data-dir` it uses the usual
data folder of the system (R-OPS-031).

The programs are *unsigned* for now. The user guide explains the first
start: Windows SmartScreen ("Windows protected your PC" → "More info" →
"Run anyway"; typically only when a downloaded file is double-clicked in
Explorer, usually not when started from a terminal or as a service) and
macOS Gatekeeper ("cannot be verified" → right-click → Open, or allow it in
System Settings). Signing is possible later: on Windows with a code-signing
certificate, Microsoft Trusted Signing, or free signing for open-source
projects through the SignPath Foundation; on macOS with the Apple Developer
Program (about 99 USD a year) and notarisation.

=== Portability findings

#table(
  columns: (auto, 1fr, auto),
  [\#], [Finding], [Action],
  [1], [`blobs.rs` (`sync_dir`) synced the blob folder after a rename with `File::open(dir)?.sync_all()`. Folders cannot be opened like that on Windows, so every upload would fail.], [done: the folder is synced on Unix only],
  [2], [Graceful shutdown listens for SIGTERM only under `cfg(unix)`; Ctrl+C works everywhere. Fine as it is.], [none],
  [3], [The plain program needs the web client in a separate folder (`--web-dir`).], [embed it (R-OPS-030)],
  [4], [The default data directory is `data`, relative to the working directory, which depends on how the program is started.], [usual folder per OS (R-OPS-031)],
  [5], [CI builds and tests only on Linux x86_64; the image is built for the host architecture only.], [platform-dependent checks on all systems, multi-arch images (R-OPS-032)],
  [6], [A blob is committed with "exists? else rename". On Windows a rename onto a file that is open (being served) fails, and two simultaneous uploads of the same new file race.], [done: "target exists" after a failed rename counts as success; still to test on Windows],
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
  merged update lists exactly the removed previews (@updates-ci); workspace
  version equals the branch name and the title pages show it (stage 1 of
  @updates-release).
- *Stored values:* data written by the newest patch of each minor is read by
  the first release of that minor (R-OPS-041).

== Roadmap <updates-roadmap>

#table(
  columns: (auto, 1fr, auto),
  [Phase], [Content], [Effort],
  [0 (in 1.0)], [Own update runner with marker tables, additive/removal/rebuild parts, refusal message; preview folder, release merge script with verified simplification; the development migrations `0001`–`0010` as previews (done, @updates-runner; the 1.0.0 update is simplified by hand at the release)], [L],
  [0 (in 1.0)], [Snapshot before updates, automatic restore, `backup` without updating, `restore` command], [M],
  [0 (in 1.0)], [`GET /api/version`, "About" view, version on the title pages from the release version (done)], [S],
  [0 (in 1.0)], [Release pipeline (@updates-release): dry run on the release pull request, real run on its merge; stage 1 builds and checks everything (version = branch, title pages, release check, images, archives, docs, guide site), stage 2 publishes images, tag, GitHub release, guide site; Compose file using a version tag; docs tags by hand], [M],
  [0 (in 1.0)], [Open clients: listener before updates with `server_starting`, shutdown drain with `server_shutting_down`, client banners, polling, unsaved markings kept and re-sent, close warning, version change with reload at a safe moment (F-OPS-008)], [M],
  [0 (in 1.0)], [Database check with schema snapshot (`schema.sql`, `db-schema.sh`) and `db-change` notice (done); release check on `release/<version>` branches (@updates-ci)], [M],
  [0 (in 1.0)], [Done: fallback values for stored enums (@updates-fallbacks); release checklist line "patch: no new stored values"; Windows folder sync fix (findings 1 and 6)], [S],
  [1], [Platform-dependent CI (tests, build, smoke) on Linux arm64, Windows and macOS; program archives with `SHA256SUMS`; web client inside the program; OS data folder; user-guide text for SmartScreen and Gatekeeper (R-OPS-029 to R-OPS-032)], [M],
  [2], [Fixtures and the upgrade/downgrade test matrix (meaningful from the second release)], [M],
  [3], [Storage modules, file store interface, PDF engine module, conformance suites (F-TECH-002)], [L],
)

Open: the container registry and image name are decided when the release
workflow is built (Docker Hub and/or GitHub Container Registry likely).

Not part of this plan: a portable export format, a second database or file
store implementation.
