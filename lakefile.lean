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

/-- The test modules under `Tests/`, which the `tests` runner imports. -/
lean_lib TestModules where
  globs := #[.submodules `Tests]

/-- `lake test`: the library's checks and the built `deps` run on fixture
packages (`Tests.lean`). -/
lean_exe tests where
  root := `Tests
  needs := #[deps]
