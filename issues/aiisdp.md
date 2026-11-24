Nothing checks that the test driver needs every default target

Question: should a check fail when a `@[default_target]` in lakefile.lean is missing from the `tests` driver's `needs`?
Options: leave it to the documented rule until a second default target is added | add a check in `lake test` that compares the two lists

Item 5kekon made `.rr2/check` run only `lake test` and set `needs := #[LeanDeps, deps]` on `lean_exe tests` (lakefile.lean), so `lake test` builds what `lake build` builds. That rests on a rule written in the lakefile's docstring and in AGENTS.project.md ("a new default target goes there too"), which AGENTS.md Rule 2 calls incomplete when it exists only in documentation. If someone adds a default target and forgets `needs`, the gate stops covering it and nothing reports it. A check would have to read the lakefile (for example through the `Lake` API or by parsing the attributes), which brings in machinery that two targets may not yet justify.
