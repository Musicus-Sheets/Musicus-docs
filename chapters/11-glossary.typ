#import "../template.typ": *

= Glossary <glossary>

#table(
  columns: (auto, 1fr),
  [Term], [Meaning],
  [Annotation set], [A named, private collection of annotation layers of one user for one file version of a part, e.g. "Christmas concert 2026".],
  [Annotation layer / page], [The annotation objects on one page of a set (`PageLayer`).],
  [Blob], [An immutable stored file, addressed by its SHA-256 hash.],
  [Grant], [Permission of a group to read parts: by instrument, or by whole score.],
  [Ink], [The annotation model and format in `musicus-api::ink`.],
  [Instrument], [Entry of the controlled instrument vocabulary; parts are tagged with instruments.],
  [Part], [One sheet of a score for one or more instruments, e.g. "2nd Trumpet in Bb". Has file versions.],
  [Programme], [A concert: date, title and an ordered list of scores.],
  [Revision], [Counter of an annotation page, used for `If-Match` and conflict detection.],
  [Role], [Member, librarian or admin. Controls management rights only.],
  [Score], [A work or arrangement with its metadata; consists of parts.],
  [WAL], [SQLite's write-ahead log mode, which lets readers and one writer work at the same time.],
)
