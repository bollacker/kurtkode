# Third-party material

Kurtkode itself is licensed under the GNU General Public License, version 3 (`LICENSE`). These parts come from
other projects and keep their own licenses.

| What | Where | From | License |
|---|---|---|---|
| ripgrep binary (the `grep` tool's engine) | `AgentCore/Sources/AgentCore/Bin/rg` | BurntSushi/ripgrep | MIT or Unlicense (`Bin/ripgrep-LICENSE-MIT`, `Bin/ripgrep-UNLICENSE`) |
| Textual (Markdown rendering in the app) | fetched by Swift Package Manager at build time (`project.yml`) | gonzalezreal/textual | MIT |
| Eval fixtures, set `pkg`: source trees at given commits, hidden tests, reference diffs | `eval-results/real-fixtures/pkg/` | pypa/packaging | Apache-2.0 or BSD-2-Clause (the `LICENSE*` files are inside each tarball) |
| Eval fixtures, set `sqg`: hidden tests and reference diffs | `eval-results/real-fixtures/sqg/` | tobymao/sqlglot | MIT |
| Eval fixtures, set `cel`: hidden tests and reference diffs | `eval-results/real-fixtures/cel/` | google/cel-go | Apache-2.0 |
| Eval fixtures, set `opa`: hidden tests and reference diffs | `eval-results/real-fixtures/opa/` | open-policy-agent/opa | Apache-2.0 |
| Reference diffs and task notes quoting upstream commits | `spike/real-set-2/` | the projects above | as above |

The eval fixtures are test data for kurtkode's evaluation harness (`EvalKit`), not part of the program. Sets whose
source trees are too large to commit (`sqg`, `cel`, `opa`, and kurtkode's own `kk`) are rebuilt locally by the scripts
in `spike/real-set-2/`. Three sets built from a private repository (responsedigger: `rd`, `rdh`, `rdw`) are not
published, and the documents that describe their results refer to them by name only.
