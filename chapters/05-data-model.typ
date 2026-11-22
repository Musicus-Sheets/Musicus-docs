#import "../template.typ": *

= Data model <data>

All structured data lives in one SQLite file, `musicus.sqlite`, in the data
directory. The schema is created by database updates applied
automatically at start-up (@updates). Before the first release these are
the preview updates `crates/musicus-server/migrations/preview/0001-init.sql`
to `0010-german-key-spellings.sql` (the development migrations of the
`sqlx::migrate!` time, whose numbers appear below); the release of 1.0.0
merges them into one update `migrations/1.0.0.sql`. Times
are stored as Unix seconds, concert dates as `YYYY-MM-DD` text.

== Entities and relations

#figure(
  diagram(
    spacing: (5mm, 8mm),
    box-node((0, 0), [`sessions`], name: <sessions>),
    box-node((0, 1), [`invites`], name: <invites>),
    box-node((1, 0.5), [`users`], name: <users>),
    box-node((2, 0), [`group_members`], name: <gm>, fill: luma(235)),
    box-node((3, 0.5), [`groups`], name: <groups>),
    box-node((4, 0), [`group_instrument_grants`], name: <gig>, fill: luma(235)),
    box-node((4, 1), [`group_score_grants`], name: <gsg>, fill: luma(235)),
    box-node((5, 0.5), [`instruments`], name: <instr>),
    box-node((5, 2), [`part_instruments`], name: <pi>, fill: luma(235)),
    box-node((3, 2), [`scores`], name: <scores>),
    box-node((4, 3), [`parts`], name: <parts>),
    box-node((5, 3.8), [`part_files`], name: <pf>, fill: luma(235)),
    box-node((5, 4.8), [`files`], name: <files>),
    box-node((1, 2), [`programme_items`], name: <pitems>, fill: luma(235)),
    box-node((1, 3), [`programmes`], name: <prog>),
    box-node((2.5, 4.8), [`annotation_sets`], name: <sets>, fill: rgb("#eef3ff")),
    box-node((0.5, 4.8), [`annotation_pages`], name: <pages>, fill: rgb("#eef3ff")),
    edge(<sessions>, <users>, "-"),
    edge(<invites>, <users>, "-"),
    edge(<gm>, <users>, "-"),
    edge(<gm>, <groups>, "-"),
    edge(<gig>, <groups>, "-"),
    edge(<gig>, <instr>, "-"),
    edge(<gsg>, <groups>, "-"),
    edge(<gsg>, <scores>, "-"),
    edge(<pi>, <instr>, "-"),
    edge(<pi>, <parts>, "-"),
    edge(<scores>, <parts>, "-"),
    edge(<parts>, <pf>, "-"),
    edge(<pf>, <files>, "-"),
    edge(<pitems>, <prog>, "-"),
    edge(<pitems>, <scores>, "-"),
    edge(<sets>, <parts>, "-"),
    edge(<sets>, <files>, "-"),
    edge(<sets>, <prog>, "-", stroke: (dash: "dashed")),
    edge(<sets>, (2.5, 3.9), (-0.3, 3.9), (-0.3, 1.6), (1, 1.6), <users>, "-"),
    edge(<pages>, <sets>, "-"),
  ),
  caption: [Tables and their relations. Grey: link tables. Blue: private annotation data. Dashed: optional.],
)

== Tables by area

#table(
  columns: (auto, 1fr),
  [Table], [Content and rules],
  table.cell(colspan: 2, fill: luma(240))[*Accounts*],
  [`users`], [Username (case-insensitive, unique), display name, role, `disabled`. `password_hash` is NULL until the invite was accepted. Reader settings `reader_mode` (page / systems) and `staff_size` (S, M, L, XL).],
  [`invites`], [Hash of a one-time token, user, expiry. All invites of a user are deleted when one is used.],
  [`sessions`], [Hash of the session token, user, created / last seen / expiry, user agent (for the device list).],
  table.cell(colspan: 2, fill: luma(240))[*Access*],
  [`groups`, `group_members`], [Groups (e.g. "Trumpets") and their members.],
  [`instruments`], [Controlled vocabulary of instruments (unique names, optional family).],
  [`group_instrument_grants`], [Group may read every part tagged with the instrument.],
  [`group_score_grants`], [Group may read every part of the score (conductor, section leaders).],
  table.cell(colspan: 2, fill: luma(240))[*Library*],
  [`scores`], [The work or arrangement: title, subtitle, composer, arranger, genre, tags (JSON array), notes, archive number (free text such as "0304", not unique) and its search forms (`archive_search`).],
  [`score_fts`], [FTS5 full-text index over the score metadata, kept in sync by triggers.],
  [`parts`], [One sheet of a score: optional custom name (`label`), key (code from a fixed list, e.g. `Bb`), notes. Without a custom name the part is named after its instruments, key and voices ("Trumpet in B♭ 2", "Klarinette 1 & 2").],
  [`part_voices`], [The voices a part contains, in order (part, position, voice; free text such as "2" or "1a"). A table of its own, indexed by voice, so that a later grant per voice can be checked with a join like the instruments.],
  [`part_fts`], [FTS5 index of the shown name of every part, written by the server because the name depends on instrument names.],
  [`part_instruments`], [Instruments a part serves; a part may serve several ("Flute / Piccolo").],
  [`files`], [One row per stored blob: hash, MIME type, size, page count, thumbnail hash.],
  [`part_files`], [File versions of a part (1, 2, ...). The highest version is current.],
  [`file_layouts`], [Music systems of every page of a file (JSON), the algorithm version and state (done / failed); written by the layout worker (@system-view). No row: not analysed yet.],
  [`layout_corrections`], [A librarian's correction of one page of a file: cut lines, band kinds and the whole-page flag (JSON), who and when. Applied when the layout is served; never changed by the detection.],
  table.cell(colspan: 2, fill: luma(240))[*Mass import*],
  [`import_batches`], [One selected folder: name, pattern, naming language (German / English), who and when.],
  [`import_files`], [Every PDF of the folder: path below the folder (unique per batch), size, SHA-256 from the browser, state (pending, uploaded, duplicate, failed), the stored `files` row once uploaded, and the reason a file was skipped or rejected as an error code (`problem`).],
  [`import_items`], [Proposed pieces and their parts (one per file): the values read from the names with their source (JSON), the librarian's changes (JSON), state (pending / committed) and, after the commit, the piece and part created.],
  [`instrument_aliases`], [A word of file names (e.g. "klar") that means an instrument, chosen once by a librarian, used by every import.],
  table.cell(colspan: 2, fill: luma(240))[*Programmes*],
  [`programmes`, `programme_items`], [A concert (title, date, notes) and its pieces in order. A piece may appear twice (encore).],
  table.cell(colspan: 2, fill: luma(240))[*Annotations (private)*],
  [`annotation_sets`], [One user, one part, one *file*; name (unique per user and part), optional programme link, default flag.],
  [`annotation_pages`], [One row per page: revision number and the zstd-compressed `ink` layer.],
)

== Notable schema choices

- *Score vs. part.* Metadata about the work belongs to the score, the
  instrument belongs to the part. Access is decided at part level, the
  library lists scores with the parts the user may read.
- *Instruments are a table, not free text,* so "Trp.", "Trumpet" and
  "Trompete" cannot drift apart and break grants. Deleting an instrument that
  parts still use fails (foreign key, HTTP 409).
- *Annotation sets point to a file, not only to a part.* When a librarian
  uploads a corrected PDF, existing annotations stay on the version they were
  drawn on (old files are never deleted) and can be moved to the new version
  if the page count is unchanged.
- *One row per annotation page,* so saving a page is a single upsert and
  two pages never conflict with each other.
- *`WITHOUT ROWID` link tables* with the primary key ordered for the access
  check (e.g. `group_members (user_id, group_id)`), so the check resolves
  through primary-key lookups only.
- *Full-text search* uses `unicode61 remove_diacritics 2`, so "Fucik" finds
  "Fučík". The query builder quotes every word and appends `*` (prefix
  search), so user input can never be interpreted as FTS operators. Every
  word must match either the score's metadata (`score_fts`) or the name of
  a part of it the user may read (`part_fts`), so "fucik trumpet" works and
  nobody finds a piece through a part they cannot see.
- *Migration 0002* made the part label optional and the voice text, and
  converted unambiguous key spellings ("in Bb", "Es") to codes. Existing
  labels became custom names, so existing parts keep their names; key values
  that are ambiguous ("B" is B♭ in German) or unknown stay unchanged and can
  still be saved.
- *Migration 0005* moved the voice into `part_voices`, so a part can contain
  several voices ("Klarinette 1 & 2"). An existing voice became the only
  entry of the list, unchanged; the part search index is rebuilt on the next
  start.
- *Staged import files* (migration 0007) are ordinary blobs with a `files`
  row but without a `part_files` row. Every library read of a file goes
  through a part, so they stay invisible to everybody until a piece is
  committed; the review reaches them only through its own batch.
- *Archive number* (migration 0006) is free text and deliberately not
  unique: paper archives contain gaps, double numbers and typos, and the
  number only links a piece to its folder. The search index holds the
  number as written plus the forms a librarian types ("0304" is also indexed
  as "304", "A-12" as "A12"); the server computes them
  (`naming::archive_search_text`). Adding the column required recreating
  `score_fts` (FTS5 tables cannot be altered) and rebuilding it.

#why[
  Annotation layers are stored in the database, not in the blob store: they
  are small (a few KB), private, change often, and need a revision number per
  page. Sheet files are the opposite: large, shared and immutable. See
  @d-blobs.
]
