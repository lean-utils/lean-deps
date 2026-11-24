# lean-deps's own rules for agents

- Everything is Lean: the library, the command, their tests and checks (`lake build`, `lake test`). No shell, bash, Python or C files.
- Toolchain: `lean-toolchain`, the one every Lean repository of the owner uses; no Lake dependencies.
- Consumers (first: grand-persuit) pin a commit; each pinned commit carries a tag `pin/<sha12>` here, pushed before the pin lands (AGENTS.md Rule 6).
- The library's public functions and the command's output are public contracts: their doc comments say what they return and what they cannot know.
- The queue is `issues/ORDER` with one `issues/ID.md` per item, in rr2's format (sections `## Next, in order`, `## Proposed`, `## Needs a decision`); it changes only through `rr2 issue add|move|edit|finish`, never by hand. An agent rr2 runs on an item changes no file under `issues/`.
- Warnings fail the build.
