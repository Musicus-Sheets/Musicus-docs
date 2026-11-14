# Musicus – technical documentation

Architecture and component documentation of [Musicus](https://github.com/NelDav/Musicus),
written in [Typst](https://typst.app). It describes each component, its sub units,
how they interact, and the reasons behind unusual design decisions.

This repository is included in the main repository as the git submodule
`docs/technical`.

## Build

```sh
cargo install --locked typst-cli    # or your package manager's typst
typst compile main.typ musicus-technical.pdf
typst watch main.typ                # rebuild on every change
```

The first build downloads the `fletcher` diagram package from the Typst package
registry (network needed once).

## Structure

| File | Content |
| --- | --- |
| `main.typ` | Entry point, includes the chapters |
| `template.typ` | Page layout and helpers (`why`, `note`, `decision`, `box-node`) |
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
