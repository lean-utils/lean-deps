import Deps.Header
import Deps.Graph

/-! The graph of a package directory, read from its files, and the module a
path or a name given on the command line is.

The sources are the package directory's `.lean` files, as Lake finds a
library whose source directory is the package's (the default `srcDir`, the
one every owner repository uses): `A/B/C.lean` is the module `A.B.C`. Not
read: `lakefile.lean` at the top, directories whose name starts with `.`
(`.lake`, `.git`), directories holding a `lakefile.lean` or `lakefile.toml`
(another package), and symbolic links to directories; a symbolic link
named `*.lean` fails the graph (`load`), as it is not followed. This is the package's
source import graph, not the modules a Lake target builds: a `.lean` file
no library's roots or globs name is a module here too, and a library with
another `srcDir` is not read as Lake reads it. -/

namespace Deps

/-- The module `rel`, a path relative to the package directory, names:
`A/B.lean` → `A.B`; none for a file that is not Lean, or whose path is no
plain module name (`Header.plainName`; `A.B.lean` would read as the same
module as `A/B.lean`). -/
def moduleOfPath (rel : System.FilePath) : Option String :=
  let parts := rel.components.filter (· != ".")
  match parts.getLast? with
  | none => none
  | some last =>
    if !last.endsWith ".lean" then none else
    let parts := parts.dropLast ++ [(last.dropEnd 5).toString]
    if parts.all fun p => !p.contains '.' && Header.plainName p then some (".".intercalate parts)
    else none

/-- A `.lean` entry under the package directory, relative to it: a file, or
a symbolic link, which this library does not follow. -/
inductive Source where
  | file (rel : System.FilePath)
  | symlink (rel : System.FilePath)

/-- The `.lean` entries under `dir` as paths relative to it (`rel`, which
`dir` is), in the order read, with the rules of this module's doc comment.
Partial only as a walk of a tree is: symbolic links to directories are not
followed, so it ends. -/
partial def sources (dir : System.FilePath) (rel : System.FilePath := ".") : IO (Array Source) := do
  let mut out := #[]
  for e in ← dir.readDir do
    if rel == "." && e.fileName == "lakefile.lean" then continue
    let relPath := if rel == "." then System.FilePath.mk e.fileName else rel / e.fileName
    match (← e.path.symlinkMetadata).type with
    | .dir =>
      if e.fileName.startsWith "." then continue
      if (← (e.path / "lakefile.lean").pathExists) || (← (e.path / "lakefile.toml").pathExists) then continue
      out := out ++ (← sources e.path relPath)
    | .symlink =>
      if e.fileName.endsWith ".lean" then out := out.push (.symlink relPath)
    | _ =>
      if e.fileName.endsWith ".lean" then out := out.push (.file relPath)
  return out

/-- The graph of the package directory `dir` (this module's doc comment
says which files it reads), or the reasons it cannot be built: a Lean file
whose path is no plain module name, or whose header is not read whole
(`Header.imports?`), or a `.lean` symbolic link (its module's imports would
otherwise be missed). An error reading the directory or a file is thrown. -/
def load (dir : System.FilePath) : IO (Except (Array String) Graph) := do
  let mut errors := #[]
  let mut modules := #[]
  let found ← sources dir
  let links := sorted (found.filterMap fun | .symlink r => some r.toString | .file _ => none)
  for rel in links do
    errors := errors.push s!"{rel} is a symbolic link, which lean-deps does not follow"
  for rel in sorted (found.filterMap fun | .file r => some r.toString | .symlink _ => none) do
    let rel := System.FilePath.mk rel
    match moduleOfPath rel with
    | none => errors := errors.push s!"{rel} is no plain module name (each directory and the file's stem of ASCII letters, digits and _, not starting with a digit)"
    | some name =>
      match Header.imports? (← IO.FS.readFile (dir / rel)) with
      | none => errors := errors.push s!"{rel}: its header is not read whole (a form lean-deps does not read, such as an escaped name «…»)"
      | some imports => modules := modules.push { name, file := rel, imports }
  if !errors.isEmpty then return .error errors
  match Graph.ofModules modules with
  | .ok g => return .ok g
  | .error e => return .error #[e]

/-- What a command-line input names: a module of the graph, or nothing the
graph can answer for, with the reason, for which every check applies
(`fallback: all`). -/
inductive Target where
  | module (m : Module)
  | fallback (reason : String)
  deriving Repr, BEq

/-- The target of `path`, relative to the package directory and without
`..` (`./A/B.lean` and `A/B.lean` are the same): the module whose file it
is, otherwise a fallback (`lakefile.lean`, a C file, a directory, an asset,
a file that is no module of the graph). A lookup in the graph as it was
loaded: the files are not read again. -/
def Graph.resolvePath (g : Graph) (path : System.FilePath) : Target :=
  let parts := path.components.filter fun p => p != "." && p != ""
  if parts.contains ".." then .fallback s!"{path} leaves the package directory" else
  match moduleOfPath (System.mkFilePath parts) with
  | some name =>
    match g.find? name with
    | some m => if m.file.components == parts then .module m else .fallback s!"{path} is no module of the package's sources"
    | none => .fallback s!"{path} is no module of the package's sources"
  | none => .fallback s!"{path} is no Lean module of the package's sources"

end Deps
