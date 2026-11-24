# lean-deps's own rules for agents

- Everything is Lean: the library, the command, their tests and checks (`lake build`, `lake test`). No shell, bash, Python or C files.
- Toolchain: `lean-toolchain`, the one every Lean repository of the owner uses; no Lake dependencies.
- Consumers (first: grand-persuit) pin a commit; each pinned commit carries a tag `pin/<sha12>` here, pushed before the pin lands (AGENTS.md Rule 6).
- The library's public functions and the command's output are public contracts: their doc comments say what they return and what they cannot know.
- The queue is `issues/ORDER` with one `issues/ID.md` per item, in rr2's format (sections `## Next, in order`, `## Proposed`, `## Needs a decision`); it changes only through `rr2 issue add|move|edit|finish`, never by hand. An agent rr2 runs on an item changes no file under `issues/`.
- Warnings fail the build.

## Map

- `LeanDeps/Header.lean`: the plain header reader (pure; its grammar is its contract). `LeanDeps/Graph.lean`: the graph and its closures (pure). `LeanDeps/Load.lean`: the package directory read into a graph, and paths resolved to modules (the only IO of the library). `LeanDeps.lean`: the library a consumer imports; it imports nothing of `Lean` or `Lake`.
- `LeanDepsMain.lean`: the command `deps` (arguments, text and JSON output; `Lean.Data.Json` is used here only).
- `LeanDepsTests.lean` and `LeanDepsTests/` (named after this package, since a consumer's workspace resolves module names here too: a generic `Tests` would take the consumer's own): `#guard`s of the reader and the graph, and fixture packages under `.lake/test-packages/` on which the built `deps` runs.
