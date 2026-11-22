#import "template.typ": *

// Release version on the title page: `typst compile --input version=1.2.0`
// (build.sh passes it); "dev" when built without one.
#let musicus-version = sys.inputs.at("version", default: "dev")

#show: project.with(
  title: "Musicus",
  subtitle: "Technical documentation: architecture and components",
  version: if musicus-version == "dev" { "Describes a development version of Musicus" } else {
    "Describes Musicus " + musicus-version
  },
)

#include "chapters/01-introduction.typ"
#include "chapters/02-system-overview.typ"
#include "chapters/03-api-crate.typ"
#include "chapters/04-server.typ"
#include "chapters/05-data-model.typ"
#include "chapters/06-web-client.typ"
#include "chapters/12-system-view.typ"
#include "chapters/07-flows.typ"
#include "chapters/08-deployment.typ"
#include "chapters/09-quality.typ"
#include "chapters/13-i18n.typ"
#include "chapters/14-updates.typ"
#include "chapters/10-decisions.typ"
#include "chapters/11-glossary.typ"
