import Lake
open Lake DSL

-- A warning fails the build: fix the code it names, never turn a linter off.
package «lean-deps» where
  testDriver := "tests"
  leanOptions := #[⟨`warningAsError, true⟩]

/-- The library a consumer's checks import (`Deps.lean`). -/
@[default_target] lean_lib Deps

/-- `lake exe deps <path|module>`: a module's imports and importers
(`DepsMain.lean`). -/
@[default_target] lean_exe deps where
  root := `DepsMain

/-- The test modules under `LeanDepsTests/`, which the `tests` runner
imports. Lake resolves a module name in every package of the workspace, so
in a consumer that requires this package a library here claims the names its
roots and globs match: the tests take this package's own name, never a
generic one such as `Tests`, which a consumer's own tests may use. -/
lean_lib LeanDepsTestModules where
  globs := #[.submodules `LeanDepsTests]

/-- `lake test`: the library's checks and the built `deps` run on fixture
packages (`LeanDepsTests.lean`). -/
lean_exe tests where
  root := `LeanDepsTests
  needs := #[deps]
