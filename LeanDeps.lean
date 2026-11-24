import LeanDeps.Header
import LeanDeps.Graph
import LeanDeps.Load

/-! lean-deps: the import graph of a Lean package's sources, for agents and
checks. `LeanDeps.load` reads a package directory into a `LeanDeps.Graph`
(`LeanDeps/Load.lean` says which files), whose imports and importers, direct
and transitive, and importing tests the command `lake exe deps` prints and a
consumer's checks query.

What it cannot know: it reads only import headers, so not the files a
module reads by name at run time (assets), at compile time (`include_str`),
or the C files and flags `lakefile.lean` builds with; nor runtime behaviour.
-/

namespace LeanDeps

/-- What the graph cannot know, as `lake exe deps` prints it. -/
def cannotKnow : Array String := #[
  "files read by name at run time (assets) or at compile time (include_str)",
  "C files, and the targets and flags lakefile.lean declares",
  "runtime behaviour: an importer may not use what it imports, a test may not check it"]

end LeanDeps
