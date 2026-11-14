#import "template.typ": *

#show: project.with(
  title: "Musicus",
  subtitle: "Technical documentation: architecture and components",
  version: "Describes Musicus 0.1 (first implementation of concept A)",
)

#include "chapters/01-introduction.typ"
#include "chapters/02-system-overview.typ"
#include "chapters/03-api-crate.typ"
#include "chapters/04-server.typ"
#include "chapters/05-data-model.typ"
#include "chapters/06-web-client.typ"
#include "chapters/07-flows.typ"
#include "chapters/08-deployment.typ"
#include "chapters/09-quality.typ"
#include "chapters/10-decisions.typ"
#include "chapters/11-glossary.typ"
