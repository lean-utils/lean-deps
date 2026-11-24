import Deps.Load

/-! The pure graph (`Deps.Graph`): closures both ways through chains and a
cycle, modules outside the graph, the test filter, and paths resolved to
modules or to the fallback. -/

open Deps

def fixture : Graph :=
  match Graph.ofModules #[
    { name := "Lib.A", file := "Lib/A.lean", imports := #["Lib.B", "Std.Data.HashMap"] },
    { name := "Lib.B", file := "Lib/B.lean", imports := #["Lib.C"] },
    { name := "Lib.C", file := "Lib/C.lean", imports := #["Init"] },
    { name := "Lib.X", file := "Lib/X.lean", imports := #["Lib.Y"] },
    { name := "Lib.Y", file := "Lib/Y.lean", imports := #["Lib.X"] },
    { name := "Tests", file := "Tests.lean", imports := #["Tests.A"] },
    { name := "Tests.A", file := "Tests/A.lean", imports := #["Lib.A"] },
    { name := "TestsLike", file := "TestsLike.lean", imports := #["Lib.C"] }] with
  | .ok g => g
  | .error _ => { modules := {}, importersOf := {} }

#guard fixture.names.size == 8
#guard fixture.imports "Lib.A" == #["Lib.B", "Std.Data.HashMap"]
#guard fixture.outside "Lib.A" == #["Std.Data.HashMap"]
-- Forward: a chain, with the modules outside the graph its members import.
#guard fixture.importsClosure "Lib.A" == #["Init", "Lib.B", "Lib.C", "Std.Data.HashMap"]
#guard fixture.importsClosure "Init" == #[]
-- Reverse: a chain, through a test runner.
#guard fixture.importers "Lib.C" == #["Lib.B", "TestsLike"]
#guard fixture.importersClosure "Lib.C" == #["Lib.A", "Lib.B", "Tests", "Tests.A", "TestsLike"]
#guard fixture.importersClosure "Init" == #["Lib.A", "Lib.B", "Lib.C", "Tests", "Tests.A", "TestsLike"]
-- A cycle ends, and the module is not in its own closure.
#guard fixture.importsClosure "Lib.X" == #["Lib.Y"]
#guard fixture.importersClosure "Lib.X" == #["Lib.Y"]
-- The test filter: `Tests` and modules under it, not a name that only
-- starts so.
#guard fixture.importingTests "Lib.C" == #["Tests", "Tests.A"]
#guard fixture.importingTests "Tests.A" == #["Tests"]
#guard isTest "Tests" && isTest "Tests.A.B" && !isTest "TestsLike" && !isTest "Lib.Tests"

-- A name two modules share is refused.
#guard match Graph.ofModules #[{ name := "A", file := "A.lean", imports := #[] },
    { name := "A", file := "x/A.lean", imports := #[] }] with
  | .error _ => true
  | .ok _ => false

-- Paths: a module's file, with or without `./`; anything else falls back.
def isModule (t : Target) (name : String) : Bool :=
  match t with
  | .module m => m.name == name
  | .fallback _ => false

def isFallback : Target → Bool
  | .fallback _ => true
  | .module _ => false

#guard isModule (fixture.resolvePath "Lib/A.lean") "Lib.A"
#guard isModule (fixture.resolvePath "./Lib/./A.lean") "Lib.A"
#guard isModule (fixture.resolvePath "Tests.lean") "Tests"
#guard isFallback (fixture.resolvePath "lakefile.lean")
#guard isFallback (fixture.resolvePath "Lib/c/x.c")
#guard isFallback (fixture.resolvePath "assets/")
#guard isFallback (fixture.resolvePath "Lib/Gone.lean")
#guard isFallback (fixture.resolvePath "Lib/../Lib/A.lean")
#guard isFallback (fixture.resolvePath "Lib.A.lean")

#guard moduleOfPath "A/B/C.lean" == some "A.B.C"
#guard moduleOfPath "./A.lean" == some "A"
#guard moduleOfPath "A/B.C.lean" == none
#guard moduleOfPath "A/x.c" == none
#guard moduleOfPath "A/1.lean" == none
#guard moduleOfPath "1A/B.lean" == none
