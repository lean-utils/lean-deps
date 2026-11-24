No required check builds a consumer package that requires lean-deps

bsc3dy's fix (the test library no longer claims `Tests.*` in a consumer's workspace) was checked only by hand: a scratch package in `/tmp/bsc3dy-consumer` with its own `Tests` and `Tests/Imports.lean`, requiring lean-deps by git at the commit, failed `lake test` at 052ba7673fcb ("no such file or directory ... .lake/packages/lean-deps/Tests/Imports.lean") and passed at the fix. Nothing in `lake test` here would catch a library of this package claiming a consumer's module name again. A fixture under `LeanDepsTests/Packages.lean` could write such a consumer requiring this checkout by path and run `lake build` in it, at the cost of a nested Lake build in the test suite.

Placed in Next by the coordinator 2026-11-24, after 5kb4u3: this check would have caught bsc3dy before grand-persuit's run met it.
