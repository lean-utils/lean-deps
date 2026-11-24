# lean-deps

The import graph of a Lean package's sources, for agents and checks: a library (`Deps`) and a command, `lake exe deps`, that prints a module's direct and transitive imports and importers and the tests that import it, and `fallback: all` for a path it cannot resolve (a build file, a C file, an asset, a deleted or unknown path). Later: the C files a Lake target compiles and the Lean modules that bind them by `@[extern]` names.

## Use

Require it in `lakefile.lean`, pinned by commit; each pinned commit carries a tag `pin/<sha12>` here:

```lean
require «lean-deps» from git "https://github.com/rofrol/lean-deps" @ "<commit>"
```

Then, in the package's directory:

```
lake exe deps [--json] (<path|module> | --path PATH | --module MODULE)
```

- A path to a module's file, or a module's name, prints the module's imports (direct, transitive, and those outside the package's sources, not followed), its importers (direct, transitive), the importing tests (`Tests` and modules under it) and what the graph cannot know. Exit 0.
- Any other path prints `fallback: all` and its reason. Exit 0. Pass a changed file with `--path`: without it, an input is the module of that name when there is one, otherwise a path when it contains `/`, ends with `.lean` or names an existing file or directory, otherwise a module name.
- An unknown module, or a package whose graph cannot be built (a header the reader does not read whole, a `.lean` path that is no plain module name), fails naming it. Exit 1; a usage error exits 2.
- `--json` prints one object from the same graph for a module or the fallback (`DepsMain.lean` documents its fields); errors go to standard error only.

A check imports `Deps` and asks the same graph: `Deps.load dir`, then `Graph.imports`, `importsClosure`, `importers`, `importersClosure`, `importingTests`, `outside`, `resolvePath`.

## What it reads, and what it cannot know

- Sources: every `.lean` file under the package directory, `A/B.lean` being the module `A.B`, except `lakefile.lean`, directories starting with `.`, directories holding another package's lakefile, and symbolic links to directories; a symbolic link named `*.lean` fails the graph, as it is not followed. It assumes the libraries' source directory is the package's (Lake's default). A `.lean` file no library names is a module here too.
- Headers are read by a plain reader (`Deps/Header.lean` states its grammar), not Lean's parser: module names of ASCII letters, digits and `_`, no part starting with a digit; an escaped name `«…»` fails the graph rather than be missed.
- Not known: files read by name at run time (assets) or compile time (`include_str`), C files and the targets and flags `lakefile.lean` declares, runtime behaviour. An importing test is a test that imports the module, not one that checks it.

## Checks

`lake build`, `lake test`.

MIT licence.
