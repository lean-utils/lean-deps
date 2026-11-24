import Deps
import Lean.Data.Json

/-! `lake exe deps [--json] (<path|module> | --path PATH | --module MODULE)`,
run in a package's directory: the module's direct and transitive imports and
importers and the tests that import it (`Deps.Graph`), as grouped plain text
or, with `--json`, one JSON object.

- An input without `--path` or `--module` is the module of that name when
  the graph has one; otherwise a path when it contains `/`, ends with
  `.lean` or names an existing file or directory; otherwise a module name.
- A path to a module's file answers for that module; any other path
  (`lakefile.lean`, a C file, `assets/`, a deleted file) prints
  `fallback: all` and its reason, and exits 0: the graph cannot say what it
  affects. Pass a changed file by `--path`: a deleted `x.c` would otherwise
  read as the module name `x.c`. A path starting with a dash is passed
  with `./` before it.
- A module name not among the package's modules fails, exit 1, as does a
  package whose graph cannot be built (`Deps.load`). A usage error exits 2.
  Both print only to standard error, also with `--json`.

The JSON object: `{"status": "ok", "module", "file", "test", "imports":
{"direct", "transitive", "outside"}, "importers": {"direct", "transitive"},
"importingTests", "cannotKnow"}`, or `{"status": "fallback", "fallback":
"all", "input", "reason", "cannotKnow"}`. The module lists are sorted;
transitive lists hold the direct ones and never the module itself;
`outside` are the direct imports outside the package's sources, not
followed. -/

open Deps
open Lean (Json)

/-- What the command was asked. -/
structure Request where
  json : Bool
  input : String
  /-- `some true` for `--path`, `some false` for `--module`, none to decide
  from the input. -/
  asPath : Option Bool

/-- The request of `args`, or a usage error. An option's operand never
starts with `-`, so `--path --json` is refused rather than read as a path. -/
def parseArgs : List String → Bool → Option Request → Except String Request
  | [], _, some r => .ok r
  | [], _, none => .error "no input"
  | "--json" :: rest, _, r => parseArgs rest true (r.map ({ · with json := true }))
  | "--path" :: p :: rest, json, none =>
    if p.startsWith "-" then .error s!"--path needs a path, not {p}"
    else parseArgs rest json (some { json, input := p, asPath := some true })
  | "--module" :: m :: rest, json, none =>
    if m.startsWith "-" then .error s!"--module needs a module, not {m}"
    else parseArgs rest json (some { json, input := m, asPath := some false })
  | a :: rest, json, none =>
    if a.startsWith "-" then .error s!"unknown option or missing operand: {a}"
    else parseArgs rest json (some { json, input := a, asPath := none })
  | a :: _, _, some _ => .error s!"one input only, and {a} is another"

def usage : String :=
  "usage: lake exe deps [--json] (<path|module> | --path PATH | --module MODULE)"

/-- `path` relative to `base`, both absolute; none when it is not under
`base`. -/
def relativeTo (base path : System.FilePath) : Option System.FilePath :=
  let b := base.components.filter (· != "")
  let p := path.components.filter (· != "")
  if p.take b.length == b then some (System.mkFilePath ("." :: p.drop b.length)) else none

/-- The target of the path `input`, read from the current directory. An
absolute path is made relative to it with symbolic links resolved in its
directory, not in its last part, which keeps the name the graph knows. -/
def targetOfPath (g : Graph) (input : String) : IO Target := do
  let path := System.FilePath.mk input
  if !path.isAbsolute then return g.resolvePath path
  let cwd ← IO.FS.realPath (← IO.currentDir)
  let real : System.FilePath ← match path.parent, path.fileName with
    | some parent, some name =>
      if ← parent.isDir then pure ((← IO.FS.realPath parent) / name) else pure path
    | _, _ => pure path
  match relativeTo cwd real with
  | some rel => return g.resolvePath rel
  | none => return .fallback s!"{input} is outside the package directory {cwd}"
def lines (title : String) (xs : Array String) : String :=
  let body := if xs.isEmpty then "  (none)\n" else String.join (xs.toList.map (s!"  {·}\n"))
  s!"{title}:\n{body}"

def textOf (g : Graph) (m : Module) : String :=
  s!"module {m.name}\nfile {m.file}\ntest: {if isTest m.name then "yes" else "no"}\n" ++
  lines "imports, direct" (g.imports m.name) ++
  lines "imports, transitive" (g.importsClosure m.name) ++
  lines "imports outside the package's sources (not followed)" (g.outside m.name) ++
  lines "importers, direct" (g.importers m.name) ++
  lines "importers, transitive" (g.importersClosure m.name) ++
  lines "importing tests" (g.importingTests m.name) ++
  lines "cannot know" cannotKnow

def strs (xs : Array String) : Json := Json.arr (xs.map Json.str)

def jsonOf (g : Graph) (m : Module) : Json :=
  Json.mkObj [
    ("status", "ok"), ("module", m.name), ("file", m.file.toString), ("test", isTest m.name),
    ("imports", Json.mkObj [("direct", strs (g.imports m.name)),
      ("transitive", strs (g.importsClosure m.name)), ("outside", strs (g.outside m.name))]),
    ("importers", Json.mkObj [("direct", strs (g.importers m.name)),
      ("transitive", strs (g.importersClosure m.name))]),
    ("importingTests", strs (g.importingTests m.name)), ("cannotKnow", strs cannotKnow)]

def fallbackJson (input reason : String) : Json :=
  Json.mkObj [("status", "fallback"), ("fallback", "all"), ("input", input), ("reason", reason),
    ("cannotKnow", strs cannotKnow)]

def main (args : List String) : IO UInt32 := do
  let req ← match parseArgs args false none with
    | .ok r => pure r
    | .error e => IO.eprintln s!"deps: {e}\n{usage}"; return 2
  let g ← match ← Deps.load "." with
    | .ok g => pure g
    | .error es =>
      IO.eprintln s!"deps: the import graph cannot be built:\n{"\n".intercalate (es.toList.map ("  " ++ ·))}"
      return 1
  let asPath ← match req.asPath with
    | some b => pure b
    | none => pure (!g.contains req.input && (req.input.contains '/' ||
        req.input.endsWith ".lean" || (← (System.FilePath.mk req.input).pathExists)))
  let target ← if asPath then targetOfPath g req.input else
    pure <| match g.find? req.input with
      | some m => .module m
      | none => .fallback ""
  match target with
  | .module m =>
    IO.print (if req.json then (jsonOf g m).compress ++ "\n" else textOf g m)
    return 0
  | .fallback reason =>
    if !asPath then
      IO.eprintln s!"deps: unknown module {req.input}: no module of the package's sources has that name"
      return 1
    IO.print (if req.json then (fallbackJson req.input reason).compress ++ "\n"
      else s!"fallback: all\nreason: {reason}\n")
    return 0
