#import "../template.typ": *

= Shared crate `musicus-api` <api>

*Purpose:* define, in one place, everything server and clients must agree
on. The crate has no I/O and no dependencies besides `serde` and
`postcard`, so it compiles for the server, for WebAssembly, and later for a
native app.

It has two sub units that do not depend on each other:

#table(
  columns: (auto, 1fr),
  [Unit], [Purpose],
  [`dto`], [Plain data types of the REST API (Data Transfer Objects) plus a few constants.],
  [`ink`], [The annotation model, its binary encoding, validation, and the three-way merge.],
  [`naming`], [Names of parts derived from instruments, key and voices; the fixed list of keys.],
)

#why[
  The client and server share Rust types instead of using Dioxus "server
  functions" or a generated OpenAPI client. A plain REST API stays usable for
  the later offline app and for scripts, and does not tie the server to the
  release cycle of the UI framework. See @d-shared-types.
]

== Unit `dto`

Groups the request and response bodies by area. Every endpoint of the
server uses exactly these types, so `dto.rs` is also the most precise
description of the API.

#table(
  columns: (auto, 1fr),
  [Area], [Types],
  [Errors], [`ApiError` (`error` code + human `message`), returned with every non-2xx status.],
  [Authentication], [`LoginRequest`, `LoginResponse`, `CurrentUser`, `InviteInfo`, `AcceptInvite`, `ChangePassword`, `SessionInfo`],
  [Users], [`Role`, `UserSummary`, `CreateUser`, `UpdateUser`, `Invite`, `CreatedUser`],
  [Access], [`Instrument`, `InstrumentInput`, `Group`, `GroupInput`, `IdList`],
  [Library], [`Score`, `ScoreInput`, `Part`, `PartInput`, `FileVersion`],
  [Programmes], [`Programme`, `ProgrammeInput`, `ProgrammeSummary`, `ProgrammeItem`],
  [Annotations], [`AnnotationSet`, `NewAnnotationSet`, `UpdateAnnotationSet`, `PageRevision`, `SavedPage`, `PageConflict`],
)

Notable details:

- `Role` (`Member` < `Librarian` < `Admin`) only controls *management*
  rights. Reading sheets is never granted by a role but by groups (except
  that librarians and admins may read everything).
- `CSRF_HEADER` (`x-musicus-csrf`) and `SESSION_COOKIE` (`musicus_session`)
  are constants here so server and client cannot disagree on the names.
- `UpdateAnnotationSet::programme_id` is an `Option<Option<Id>>`: the field
  missing means "leave unchanged", JSON `null` means "unlink the programme".
  A custom deserializer (`double_option`) makes this distinction.
- Lists that are replaced as a whole (group members, grants, programme
  pieces) are sent as `IdList` with `PUT`, which makes these operations
  idempotent.

== Unit `naming`

A part is named after what it is: its instruments (alphabetical, joined
with " / "), " in " and its key, then its voices joined with " & " in
their order, e.g. "Trumpet in B♭ 1", "Horn in F 3a", "Flute / Piccolo",
"Klarinette 1 & 2" or "Trombone 1 & 2 & 3". A part without instrument, key
and voice is an "Unnamed part". Voices are cleaned the same way everywhere
(`clean_voices`): trimmed, blank and repeated entries (ignoring case)
dropped, the order kept; an "&" inside an entry separates two voices, so a
name never hides how many voices a part has. Names sort with numbers by
value, so a part with several voices sorts by its first voice, then the
next ("Clarinet 1", "Clarinet 1 & 2", "Clarinet 2"). An optional custom name replaces the derived
name. The server computes the name (`Part.display_name`) on every read, so
renaming an instrument renames its parts; the web client uses the same
function only to preview the name while a part is edited.

Keys come from a fixed list, stored as ASCII codes and shown with
accidentals: B♭ (`Bb`), E♭, F, C, A, D, G, E, A♭, D♭, G♭ and B♮ (`H`).
B natural uses the German letter because a stored "B" is ambiguous (B♭ in
German). The server also accepts common spellings ("B-flat", "in Es") and
rejects anything else.

== Unit `ink`

Describes what a user drew on one page of one sheet: a `PageLayer` is a
list of `InkObject`s, each a `Stroke` (pen or highlighter), a `Stamp`
(breath mark, fermata, glasses, accidentals, ...) or a `TextNote`.

#figure(
  diagram(
    spacing: (10mm, 8mm),
    box-node((0, 0), [`PageLayer`], name: <l>),
    box-node((0, 1), [`InkObject` (enum)], name: <o>),
    box-node((-1.3, 2), [`Stroke` \ id, tool, colour, width, \ start, deltas, pressure], name: <s>),
    box-node((0, 2), [`Stamp` \ id, kind, at, size, colour], name: <st>),
    box-node((1.3, 2), [`TextNote` \ id, at, size, colour, text], name: <t>),
    edge(<l>, <o>, "->", [`objects: Vec`], label-side: left),
    edge(<o>, <s>, "->"),
    edge(<o>, <st>, "->"),
    edge(<o>, <t>, "->"),
  ),
  caption: [The annotation model.],
)

=== Coordinates

Positions are relative to the page: `x` and `y` run from 0 to
`COORD_MAX` (65535) from the top-left to the bottom-right corner. Lengths
(stroke width, stamp size) are in units of 1/65535 of the page width. This
makes a layer independent of zoom, screen size and device; the client maps
to pixels when drawing (`PageBox` in the web client).

=== Encoding

`encode` writes one format version byte (`FORMAT_VERSION = 1`) followed by
the postcard encoding of the layer. Stroke points are stored as a start
point plus differences to the previous point (`deltas`), which postcard
writes as variable-length integers, mostly one byte each. A typical page
(30 strokes of 60 points) takes about 7 KB; the server additionally
compresses stored layers with zstd.

`decode` checks the version byte, the size limit (`MAX_ENCODED_BYTES`,
4 MiB), the object and point limits, duplicate object ids, and that every
stroke has one pressure value per point. The server calls `decode` on every
upload, so a malformed or oversized layer is rejected with HTTP 422 before
it is stored.

#why[
  Vector objects with page-relative integer coordinates, encoded in a
  compact binary format, instead of JSON or bitmaps: JSON was 7--9 times
  larger in the prototype measurements, and bitmaps would neither scale with
  zoom nor allow erasing single strokes. See @d-ink-format.
]

=== Merge

`merge(base_ids, local, server)` combines two versions of a page edited on
two devices of the same user. Objects are never edited in place, only
added or removed, so a merge by object id is exact: an object survives
unless one side deleted it, and objects added on either side are kept. The
client uses it when the server reports a conflict (see @flow-save).

#why[
  Making objects immutable (an edit is "remove + add") is what makes this
  simple merge correct, without operational transforms or a CRDT library.
  Every object carries a random 64-bit id for this purpose. See
  @d-optimistic.
]
