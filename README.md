# lean-deps

The import graph of a Lean workspace, for agents and checks: a library (`Deps`) and a command, `lake exe deps <path|module>`, that prints a module's direct and transitive imports and importers and the tests that import it, and `fallback: all` for a path it cannot resolve (a build file, a C header, an asset, an unknown path). Later: the C files a Lake target compiles and the Lean modules that bind them by `@[extern]` names.

Use: require it in `lakefile.lean`, pinned by commit; each pinned commit carries a tag `pin/<sha12>` here.

MIT licence.
