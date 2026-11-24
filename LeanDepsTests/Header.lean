import Deps.Header

/-! The header reader (`Deps.Header.imports?`): the forms it reads, where
the header ends, and the forms it refuses rather than miss an import. -/

open Deps.Header

-- Imports up to the first command; a doc comment ends the header.
#guard imports? "import Game.Files\nimport Tests.Drive\n\n/-! doc -/\nimport Not.This\n" ==
  some #["Game.Files", "Tests.Drive"]
-- Comments (nested), `module`, `public`, `meta`, `import all`, a line break
-- inside an import.
#guard imports?
    "-- a comment\n/- a /- nested -/\nimport In.Comment\n-/\nmodule\n\npublic import A -- one\nmeta import\tC\nimport all D\n/- c -/ import\n  E\ndef x := 1\nimport F\n" ==
  some #["A", "C", "D", "E"]
#guard imports? "public meta import all A" == some #["A"]
#guard imports? "prelude\nimport Init.Prelude" == some #["Init.Prelude"]
#guard imports? "" == some #[]
#guard imports? "import A\nimport A" == some #["A"]
-- What Lean's lexer reads as inside a comment, or after the header's end,
-- is no import.
#guard imports? "/-/\nimport In.Comment\n-/\nimport A" == some #["A"]
#guard imports? "import A /-\nimport In.Comment\n-/" == some #["A"]
#guard imports? "/- c\n-/ #exit\nimport After.Exit" == some #[]
#guard imports? "import A/-x-/import B--y\nimport C" == some #["A", "B", "C"]
#guard imports? "/-! doc -/\nimport After.Doc" == some #[]
#guard imports? "@[simp] theorem t : True := trivial\nimport X" == some #[]
#guard imports? "import A /- never closed\nimport B" == some #["A"]
-- Refused, not read whole: an escaped name, a name the lexer ends early,
-- an `import` with no name, a word that only starts with a keyword.
#guard imports? "import A\nimport Tests.«B»\nimport C" == none
#guard imports? "import A#check Nat\nimport B" == none
#guard imports? "import /-- doc -/" == none
#guard imports? "import A\nimport" == none
#guard imports? "import A\nimport«Game».Fixed" == none
#guard imports? "import A\npublic import«B»" == none
-- The body is not lexed: a long word after the header costs nothing.
#guard imports? ("import A\ndef s := \"" ++ String.ofList (List.replicate 200000 'x') ++ "\"") == some #["A"]

#guard plainName "A.B_1.c" && !plainName "A..B" && !plainName "" && !plainName "A.«B»" &&
  !plainName "Ä"

-- One `all`, then a name that starts with no digit; `/--/` is a doc
-- comment for Lean's lexer too, so it ends the header.
#guard imports? "import all all A" == none
#guard imports? "import all" == none
#guard imports? "import A.1" == none
#guard imports? "import A.b1_" == some #["A.b1_"]
#guard imports? "/--/\nimport A" == some #[]
#guard !plainName "A.1" && plainName "_A.x9"
