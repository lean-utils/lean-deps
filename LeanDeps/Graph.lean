import Std.Data.HashMap
import Std.Data.HashSet

/-! The import graph of a package's sources: its modules, each with its file
and the imports its header names, and the edges both ways. Pure: `LeanDeps.load`
reads a directory into one. Module names are strings (`Game.Files`). -/

namespace LeanDeps

/-- A module of the package's sources: its name, its file relative to the
package directory (`Game/Files.lean`) and the modules its header imports, in
the header's order, each once. -/
structure Module where
  name : String
  file : System.FilePath
  imports : Array String
  deriving Repr, BEq, Inhabited

/-- The graph: the package's modules by name and, for each name any of them
imports, the modules importing it. A name imported but not among the modules
(the toolchain's `Init`, `Std`, `Lean`, a dependency's, or a module whose file
is missing) is *outside* the graph: an edge to it is kept, and it is not
followed. -/
structure Graph where
  modules : Std.HashMap String Module
  importersOf : Std.HashMap String (Array String)

/-- `xs` sorted, for output that does not depend on hashing or file order. -/
def sorted (xs : Array String) : Array String := xs.qsort (· < ·)

/-- The graph of `ms`; fails naming the first module name that two of them
share. -/
def Graph.ofModules (ms : Array Module) : Except String Graph := do
  let mut modules : Std.HashMap String Module := {}
  let mut importersOf : Std.HashMap String (Array String) := {}
  for m in ms do
    if let some other := modules[m.name]? then
      throw s!"module {m.name} is both {other.file} and {m.file}"
    modules := modules.insert m.name m
    for i in m.imports do
      importersOf := importersOf.alter i fun
        | some a => some (a.push m.name)
        | none => some #[m.name]
  return { modules, importersOf }

/-- The module named `name`, if it is one of the graph's. -/
def Graph.find? (g : Graph) (name : String) : Option Module := g.modules[name]?

/-- Whether `name` is one of the graph's modules. -/
def Graph.contains (g : Graph) (name : String) : Bool := g.modules.contains name

/-- The graph's module names, sorted. -/
def Graph.names (g : Graph) : Array String := sorted (g.modules.toArray.map (·.1))

/-- The modules `name` imports directly, sorted: the graph's and those
outside it. Empty for a name outside the graph, whose imports are not known. -/
def Graph.imports (g : Graph) (name : String) : Array String :=
  sorted ((g.find? name).map (·.imports) |>.getD #[])

/-- The graph's modules that import `name` directly, sorted. -/
def Graph.importers (g : Graph) (name : String) : Array String :=
  sorted (g.importersOf[name]?.getD #[])

/-- The names reachable from `start` by one or more steps of `next`, other
than `start` itself. `bound` bounds the rounds: each round that goes on adds
a new name with successors, so one more than the number of names with
successors is enough. -/
def reach (next : String → Array String) (bound : Nat) (start : String) : Array String := Id.run do
  let mut seen : Std.HashSet String := {}
  let mut frontier := next start
  for _ in [0:bound] do
    let mut fresh := #[]
    for m in frontier do
      unless seen.contains m do
        seen := seen.insert m
        fresh := fresh.push m
    if fresh.isEmpty then break
    frontier := fresh.flatMap next
  return sorted ((seen.erase start).toArray)

/-- The modules `name` imports directly or through the graph's modules it
imports, sorted, `name` excluded: the graph's modules it reaches, and the
modules outside the graph that any of these import (not followed further). -/
def Graph.importsClosure (g : Graph) (name : String) : Array String :=
  reach g.imports (g.modules.size + 1) name

/-- The graph's modules that import `name` directly or through other
modules of the graph, sorted, `name` excluded. -/
def Graph.importersClosure (g : Graph) (name : String) : Array String :=
  reach g.importers (g.modules.size + 1) name

/-- Whether `name` is a test module: `Tests` or a module under it. A name,
not a claim about what `lake test` runs. -/
def isTest (name : String) : Bool := name == "Tests" || name.startsWith "Tests."

/-- The test modules (`isTest`) that import `name` directly or through
other modules of the graph, sorted: the tests that import it, which says
nothing about what they check of it. -/
def Graph.importingTests (g : Graph) (name : String) : Array String :=
  (g.importersClosure name).filter isTest

/-- The modules `name` imports directly that are outside the graph, sorted. -/
def Graph.outside (g : Graph) (name : String) : Array String :=
  (g.imports name).filter (!g.contains ·)

end LeanDeps
