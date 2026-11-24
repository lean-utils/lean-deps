import Tests.Header
import Tests.Graph
import Tests.Packages

/-! `lake test`: the reader's and the graph's checks (`#guard`s, checked
when their modules compile) and the fixture packages (`Tests.Packages`),
run here. -/

def main : IO UInt32 := do
  let failures ← Tests.Packages.check
  for f in failures do IO.eprintln s!"FAIL {f}"
  if failures.isEmpty then
    IO.println "all checks passed"
    return 0
  return 1
