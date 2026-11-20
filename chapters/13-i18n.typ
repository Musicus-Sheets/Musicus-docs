#import "../template.typ": *

= Languages (internationalisation) <i18n>

*Purpose:* Musicus shows its user interface, dates, numbers, error
messages, part names and sort order in the language of the user's browser
(English if that language is not shipped), while all data is stored and
shown exactly as entered. Requirements: F-I18N-001, R-I18N-001 to
R-I18N-010; decision @d-i18n-fluent. The work is done in phases; this
chapter describes the target and marks what exists.

== Principles

#table(
  columns: (auto, 1fr),
  [Principle], [Meaning],
  [Data as entered], [Titles, composers, tags, notes, instrument names and families, group names, voices, custom part names, programme texts and set names are never translated. A German band's "Klarinette" stays "Klarinette" for an English reader.],
  [Browser language], [The language is the first entry of the browser's preferred languages that Musicus ships, else English. There is no setting and nothing is stored, neither on the server nor on the device.],
  [No prose from the server], [The server sends components and codes; the browser composes the words. Part names ("Clarinet in B♭ 1 & 2"), key names, the name of an unnamed annotation set and error messages are rendered by the client.],
  [Formatting by the browser], [Dates, times, numbers and sorting use the browser's `Intl` API in the UI language.],
)

== Units

#table(
  columns: (auto, 1fr),
  [Unit], [Purpose],
  [`musicus-i18n`], [Message catalogue (`locales/<lang>/<area>.ftl`), build-time generated typed functions, English fallback per message, the pseudo-locale for tests, and the search tables (key spellings, connecting words) the server uses.],
  [`musicus-web::locale`], [Chooses the language from `navigator.languages`, sets `<html lang>`, formats dates, numbers and sizes through `Intl`, and provides the collator for sorted lists.],
  [`musicus-api::naming`], [Composes part names from components with the words of the UI language (`NameWords`).],
  [`musicus-server::part_index`], [Indexes the components of part names plus every key spelling of the shipped languages for the library search.],
)

== Phases

#table(
  columns: (auto, 1fr),
  [Phase], [Content],
  [0], [Decisions, requirements, glossary (`docs/agents/glossary.md`). Done.],
  [1], [Catalogue crate, language choice, `Intl` formatting, checks. Done: the client grew by about 53 KB (gzip).],
  [2], [Errors as codes (separate branch).],
  [3], [Part names and the default set name composed in the browser; search on components. Done (migration 0009).],
  [4], [All client texts in the catalogue (about 450 English messages); a lint forbids literal texts; a pseudo-locale test run marks every translated text. Done.],
  [5], [All displayed lists sorted in the browser with the UI language's collation.],
  [later], [German catalogue, translated user guide, translation platform.],
)
