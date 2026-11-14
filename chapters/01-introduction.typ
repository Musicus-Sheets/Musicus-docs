#import "../template.typ": *

= Introduction

Musicus provides sheet music to the members of an orchestra or band. A
librarian uploads PDF parts. Access is granted to groups, e.g. the group
"Trumpets" may read every part tagged with the instrument "Trumpet". Every
member can draw private annotations on their parts, in several named sets
(e.g. one per concert), without changing the PDF.

This document explains how Musicus is built: which components exist, what
each one is for, which smaller units it consists of, and how they work
together. Where the design deviates from what a reader would expect, the
reason is given. Short reasons appear in yellow *Why?* boxes next to the
component; the full reasoning is collected in @decisions.

== Audience and scope

The audience is developers and operators who want to understand, change or
run Musicus. It assumes basic knowledge of Rust, HTTP and SQL. It describes
the code as of the first implementation (crate version 0.1.0). Other
documents cover other needs:

#table(
  columns: (auto, 1fr),
  [Document], [Content],
  [User guide], [How musicians, librarians and admins use the application.],
  [Technical documentation (this)], [Architecture and components, for humans.],
  [Agent documentation], [Condensed technical facts for coding agents.],
  [Requirements], [What the system must do and under which constraints.],
  [`README.md` of the repository], [Build, run and configuration reference.],
)

== Requirements that shaped the architecture

The architecture follows from a few requirements. They are repeated here
because many decisions in this document refer back to them.

#table(
  columns: (2.2em, 1fr),
  [ID], [Requirement],
  [R1], [Store sheet files on a server; PDF now, other formats (MusicXML) later.],
  [R2], [Users, authentication, and access through groups and metadata (instrument), not file by file.],
  [R3], [Private, non-destructive annotations, saved on the server, in several named sets per user.],
  [R4], [No persistent data on the client for now. A later app stores data encrypted and works offline.],
  [R5], [Backend in Rust, GUI in Dioxus.],
  [R6], [Many musicians open the same piece at the same moment (burst load).],
  [R7], [The server must run on small hardware (Raspberry Pi, 1 vCPU / 1 GB VPS).],
)

== Repository layout

#table(
  columns: (auto, 1fr),
  [Path], [Content],
  [`crates/musicus-api`], [Shared library: JSON types of the REST API and the annotation format.],
  [`crates/musicus-server`], [The server binary: HTTP API, database, file store, CLI.],
  [`crates/musicus-web`], [The web client (Dioxus, compiled to WebAssembly) and its JavaScript bridge.],
  [`e2e/`], [Browser smoke test (Playwright).],
  [`scripts/fetch-pdfjs.sh`], [Downloads the pinned pdf.js build into the client's `public/` folder.],
  [`Dockerfile`, `compose.yaml`, `deploy/`], [Container image, Compose setup, Caddy configuration.],
  [`prototypes/`], [Throw-away benchmarks that validated the design. Not part of the product.],
  [`docs/technical/`], [This document (a git submodule).],
)
