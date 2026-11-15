# Musicus – technical documentation

Architecture and component documentation of [Musicus](https://github.com/NelDav/Musicus),
written in [Typst](https://typst.app). It describes each component, its sub units,
how they interact, and the reasons behind unusual design decisions.

This repository is included in the main repository as the git submodule
`docs/technical`.

## Build

```sh
./build.sh          # → out/musicus-technical.pdf and out/musicus-technical.html
```

The PDF is the main format (A4, for reading and printing); the HTML page is a
self-contained second format with a navigation sidebar and dark mode. Both come
from the same source. Requires `typst` (tested with 0.15;
`cargo install --locked typst-cli`); the HTML export of Typst is still marked
experimental, hence `--features html`. The first build downloads the `fletcher`
diagram package from the Typst package registry (network needed once).

The layout follows the user guide: the Inter font (SIL Open Font License,
`fonts/Inter-LICENSE.txt`) is bundled so the PDF looks the same everywhere;
code uses DejaVu Sans Mono, which Typst embeds itself.

## Structure

| File | Content |
| --- | --- |
| `main.typ` | Entry point, includes the chapters |
| `template.typ` | Layout for both outputs and helpers: `why`, `note`, `decision`, `diagram` (fletcher, fitted to the page; SVG in HTML), `box-node`; HTML stylesheet |
| `build.sh` | Builds PDF and HTML into `out/` |
| `fonts/` | Bundled Inter font |
| `chapters/01-introduction.typ` | Purpose, audience, requirements, repository layout |
| `chapters/02-system-overview.typ` | Components and how they interact |
| `chapters/03-api-crate.typ` | Shared crate `musicus-api` (`dto`, `ink`) |
| `chapters/04-server.typ` | Server units and their interplay |
| `chapters/05-data-model.typ` | Database schema |
| `chapters/06-web-client.typ` | Web client units, JavaScript bridge, reader |
| `chapters/07-flows.typ` | Use cases traced through the components |
| `chapters/08-deployment.typ` | Build, container image, operation |
| `chapters/09-quality.typ` | Tests |
| `chapters/10-decisions.typ` | Architecture decision records |
| `chapters/11-glossary.typ` | Glossary |

When the code changes, update the affected chapter; when a design decision is
taken that a reader would not expect, add an entry to `10-decisions.typ` and
reference it from the component with a `#why[...]` box.
