import Lake
open Lake DSL

-- A warning fails the build: fix the code it names, never turn a linter off.
-- Lake resolves a module name in every package of the workspace
-- (`Package.isBuildableModule`): in a consumer that requires this package, a
-- library here claims the names its roots and globs match and an executable
-- its root. So every module name a target here claims is named after this
-- package (`LeanDeps`, `LeanDepsMain`, `LeanDepsTests`), never a generic
-- name such as `Deps` or `Tests`, which a consumer's own modules may use.
package «lean-deps» where
  testDriver := "tests"
  leanOptions := #[⟨`warningAsError, true⟩]

/-- The library a consumer's checks import (`LeanDeps.lean`). -/
@[default_target] lean_lib LeanDeps

/-- `lake exe deps <path|module>`: a module's imports and importers
(`LeanDepsMain.lean`). -/
@[default_target] lean_exe deps where
  root := `LeanDepsMain

/-- The test modules under `LeanDepsTests/`, which the `tests` runner
imports. -/
lean_lib LeanDepsTestModules where
  globs := #[.submodules `LeanDepsTests]

/-- `lake test`: the library's checks and the built `deps` run on fixture
packages (`LeanDepsTests.lean`). It needs every default target, so that
`lake test` alone, the gate `.rr2/check` runs, also builds what `lake build`
builds; a new default target goes into `needs` too. -/
lean_exe tests where
  root := `LeanDepsTests
  needs := #[LeanDeps, deps]
