import LeanDeps
import Lean.Data.Json

/-! Fixture packages written to a fresh directory under `.lake/`: `LeanDeps.load`
on them (which files are sources, which headers fail the graph) and the
built `deps` command run in them (its output, `--json`, the fallback,
unknown modules, exit codes). -/

namespace LeanDepsTests.Packages

open LeanDeps
open Lean (Json)

/-- Writes `files` (path relative to `dir`, text) under `dir`, which is
removed first. -/
def writePackage (dir : System.FilePath) (files : List (String × String)) : IO Unit := do
  if ← dir.pathExists then IO.FS.removeDirAll dir
  for (rel, text) in files do
    let path := dir / rel
    if let some parent := path.parent then IO.FS.createDirAll parent
    IO.FS.writeFile path text

/-- A package with a library, a test runner and its tests, a C file, an
asset, and directories that are no sources (hidden, another package). -/
def mainPackage : List (String × String) := [
  ("lakefile.lean", "import Lake\n"),
  ("Lib/A.lean", "import Lib.B\nimport Std.Data.HashMap\n"),
  ("Lib/B.lean", "module -- a comment\n\npublic import Lib.C\n\n/-! doc -/\n"),
  ("Lib/C.lean", "def c := 1\n"),
  ("Lib/c/x.c", "int x;\n"),
  ("Main.lean", "import Lib.C\n"),
  ("Tests.lean", "import Tests.A\n"),
  ("Tests/A.lean", "import Lib.A\n"),
  ("assets/a.txt", "asset\n"),
  (".hidden/Z.lean", "import Lib.C\n"),
  ("sub/lakefile.toml", "name = \"sub\"\n"),
  ("sub/S.lean", "import Lib.C\n")]

/-- A symbolic link `link` to `target`, both relative to `dir` (`ln -s`;
Lean's library makes none). -/
def symlink (dir : System.FilePath) (target link : String) : IO Unit := do
  let out ← IO.Process.output { cmd := "ln", args := #["-s", target, link], cwd := some dir }
  unless out.exitCode == 0 do throw (IO.userError s!"ln -s {target} {link}: {out.stderr}")

/-- The result of the built `deps` run in `dir` with `args`. -/
def deps (dir : System.FilePath) (args : Array String) : IO IO.Process.Output := do
  let exe := (← IO.appPath).parent.getD "." / "deps"
  IO.Process.output { cmd := exe.toString, args, cwd := some dir }

/-- The failure `msg` unless `ok`. -/
def expect (ok : Bool) (msg : String) : Array String := if ok then #[] else #[msg]

/-- A run of `deps` that exits `code` and whose standard output is `out`. -/
def expectRun (dir : System.FilePath) (args : Array String) (code : UInt32) (out : String) :
    IO (Array String) := do
  let r ← deps dir args
  return expect (r.exitCode == code && r.stdout == out)
    s!"deps {args}: expected exit {code} and\n{out}\ngot exit {r.exitCode} and\n{r.stdout}{r.stderr}"

/-- The field `key` of a JSON object, rendered compactly. -/
def field (j : Json) (key : String) : String :=
  match j.getObjVal? key with
  | .ok v => v.compress
  | .error _ => "(missing)"

def checkMain (root : System.FilePath) : IO (Array String) := do
  let dir := root / "main"
  writePackage dir mainPackage
  let mut failures := #[]
  match ← LeanDeps.load dir with
  | .error es => failures := failures.push s!"load main: {es}"
  | .ok g =>
    failures := failures ++ expect (g.names == #["Lib.A", "Lib.B", "Lib.C", "Main", "Tests", "Tests.A"])
      s!"main's modules: {g.names}"
    failures := failures ++ expect (g.importingTests "Lib.C" == #["Tests", "Tests.A"])
      s!"tests importing Lib.C: {g.importingTests "Lib.C"}"
  let libC := "module Lib.C\nfile Lib/C.lean\ntest: no\nimports, direct:\n  (none)\n" ++
    "imports, transitive:\n  (none)\nimports outside the package's sources (not followed):\n  (none)\n" ++
    "importers, direct:\n  Lib.B\n  Main\nimporters, transitive:\n  Lib.A\n  Lib.B\n  Main\n  Tests\n  Tests.A\n" ++
    "importing tests:\n  Tests\n  Tests.A\ncannot know:\n" ++
    String.join (cannotKnow.toList.map (s!"  {·}\n"))
  failures := failures ++ (← expectRun dir #["Lib.C"] 0 libC)
  failures := failures ++ (← expectRun dir #["Lib/C.lean"] 0 libC)
  failures := failures ++ (← expectRun dir #["--path", "./Lib/C.lean"] 0 libC)
  failures := failures ++ (← expectRun dir #["--module", "Lib.C"] 0 libC)
  let abs ← IO.FS.realPath (dir / "Lib" / "C.lean")
  failures := failures ++ (← expectRun dir #[abs.toString] 0 libC)
  -- The fallback, with its reason.
  for p in ["lakefile.lean", "Lib/c/x.c", "assets", "assets/a.txt", "Lib/Gone.lean", "sub/S.lean",
      ".hidden/Z.lean", "../x.lean"] do
    let r ← deps dir #[p]
    failures := failures ++ expect (r.exitCode == 0 && r.stdout.startsWith "fallback: all\nreason: ")
      s!"deps {p}: expected the fallback, got exit {r.exitCode}:\n{r.stdout}{r.stderr}"
  -- A module's name is the module, also when a directory has that name.
  let r ← deps dir #["Tests"]
  failures := failures ++ expect (r.exitCode == 0 && r.stdout.startsWith "module Tests\nfile Tests.lean\ntest: yes\n")
    s!"deps Tests: {r.stdout}{r.stderr}"
  -- A deleted file without `/` reads as a module unless passed by `--path`.
  failures := failures ++ (← expectRun dir #["--path", "x.c"] 0
    "fallback: all\nreason: x.c is no Lean module of the package's sources\n")
  -- Unknown modules and usage errors.
  for (args, code) in [(#["x.c"], 1), (#["Nope.X"], 1), (#["--module", "Lib/C.lean"], 1),
      (#[], 2), (#["--bogus"], 2), (#["Lib.A", "Lib.B"], 2), (#["--path"], 2),
      (#["--path", "--json"], 2), (#["--module", "--json"], 2), (#["--json", "--path", "-x"], 2)] do
    let r ← deps dir args
    failures := failures ++ expect (r.exitCode == code && r.stdout.isEmpty && !r.stderr.isEmpty)
      s!"deps {args}: expected exit {code} with an error only, got exit {r.exitCode}:\n{r.stdout}{r.stderr}"
  -- `--json`, from the same graph.
  let r ← deps dir #["--json", "Lib.A"]
  match Json.parse r.stdout with
  | .error e => failures := failures.push s!"deps --json Lib.A: {e}: {r.stdout}"
  | .ok j =>
    let imports := j.getObjValD "imports"
    let importers := j.getObjValD "importers"
    failures := failures ++ expect (field j "status" == "\"ok\"" && field j "module" == "\"Lib.A\"" &&
        field j "file" == "\"Lib/A.lean\"" && field j "test" == "false" &&
        field imports "direct" == "[\"Lib.B\",\"Std.Data.HashMap\"]" &&
        field imports "transitive" == "[\"Lib.B\",\"Lib.C\",\"Std.Data.HashMap\"]" &&
        field imports "outside" == "[\"Std.Data.HashMap\"]" &&
        field importers "direct" == "[\"Tests.A\"]" &&
        field importers "transitive" == "[\"Tests\",\"Tests.A\"]" &&
        field j "importingTests" == "[\"Tests\",\"Tests.A\"]" && r.exitCode == 0)
      s!"deps --json Lib.A: {r.stdout}"
  let r ← deps dir #["Tests/A.lean", "--json"]
  failures := failures ++ expect (r.exitCode == 0 && (Json.parse r.stdout).toOption.any fun j =>
      field j "status" == "\"ok\"" && field j "test" == "true" &&
      field (j.getObjValD "imports") "transitive" == "[\"Lib.A\",\"Lib.B\",\"Lib.C\",\"Std.Data.HashMap\"]" &&
      field j "cannotKnow" == (Json.arr (cannotKnow.map Json.str)).compress)
    s!"deps Tests/A.lean --json: {r.stdout}"
  let r ← deps dir #["--json", "lakefile.lean"]
  failures := failures ++ expect (r.exitCode == 0 && (Json.parse r.stdout).toOption.any fun j =>
      field j "status" == "\"fallback\"" && field j "fallback" == "\"all\"" &&
      field j "input" == "\"lakefile.lean\"" &&
      field j "reason" == "\"lakefile.lean is no module of the package's sources\"" &&
      field j "cannotKnow" == (Json.arr (cannotKnow.map Json.str)).compress)
    s!"deps --json lakefile.lean: {r.stdout}"
  return failures

/-- Packages whose graph cannot be built: `LeanDeps.load` names the file, and
`deps` fails naming it, for any input. -/
def checkBroken (root : System.FilePath) : IO (Array String) := do
  let mut failures := #[]
  for (name, files, links, culprit) in [
      ("escaped", [("Lib/A.lean", "import «Lib».B\n"), ("Lib/B.lean", "")], [], "Lib/A.lean"),
      ("dotted", [("Lib/A.B.lean", ""), ("Lib/C.lean", "")], [], "Lib/A.B.lean"),
      ("digit", [("Lib/1.lean", ""), ("Lib/C.lean", "")], [], "Lib/1.lean"),
      ("linked", [("Lib/C.lean", "")], [("Lib/C.lean", "Alias.lean")], "Alias.lean")] do
    let dir := root / name
    writePackage dir files
    for (target, link) in links do symlink dir target link
    match ← LeanDeps.load dir with
    | .ok _ => failures := failures.push s!"load {name}: built a graph"
    | .error es =>
      failures := failures ++ expect (es.size == 1 && es.all (·.startsWith culprit)) s!"load {name}: {es}"
    for input in ["Lib.C", "lakefile.lean"] do
      let r ← deps dir #[input]
      failures := failures ++ expect (r.exitCode == 1 && r.stdout.isEmpty && (r.stderr.splitOn culprit).length > 1)
        s!"deps {input} in {name}: expected exit 1 naming {culprit}, got exit {r.exitCode}:\n{r.stdout}{r.stderr}"
  return failures

/-- Symbolic links that are no sources: a root `lakefile.lean` that is a
link is still the build file, and a link to a directory is not followed. -/
def checkLinks (root : System.FilePath) : IO (Array String) := do
  let dir := root / "links"
  writePackage dir [("Lib/C.lean", "")]
  -- A link to a module's file: the build file all the same, also by its
  -- absolute path, whose last part is not resolved.
  symlink dir "Lib/C.lean" "lakefile.lean"
  symlink dir "Lib" "Linked"
  let mut failures := #[]
  match ← LeanDeps.load dir with
  | .error es => failures := failures.push s!"load links: {es}"
  | .ok g => failures := failures ++ expect (g.names == #["Lib.C"]) s!"links' modules: {g.names}"
  failures := failures ++ (← expectRun dir #["--path", "lakefile.lean"] 0
    "fallback: all\nreason: lakefile.lean is no module of the package's sources\n")
  let r ← deps dir #[((← IO.FS.realPath dir) / "lakefile.lean").toString]
  failures := failures ++ expect (r.exitCode == 0 && r.stdout.startsWith "fallback: all\n")
    s!"deps on the linked lakefile's absolute path: {r.stdout}{r.stderr}"
  -- An absolute path through a linked directory is resolved in its directory.
  let r ← deps dir #[((← IO.FS.realPath dir) / "Linked" / "C.lean").toString]
  failures := failures ++ expect (r.exitCode == 0 && r.stdout.startsWith "module Lib.C\n")
    s!"deps through Linked: {r.stdout}{r.stderr}"
  return failures

/-- Every failure of this module's checks, run in fixture packages under
`.lake/test-packages/<pid>`, removed afterwards. -/
def check : IO (Array String) := do
  let root := (← IO.currentDir) / ".lake" / "test-packages" / toString (← IO.Process.getPID)
  try
    return (← checkMain root) ++ (← checkBroken root) ++ (← checkLinks root)
  finally
    if ← root.pathExists then IO.FS.removeDirAll root

end LeanDepsTests.Packages
