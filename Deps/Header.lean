/-! The imports a Lean file's header names, read by a plain reader of the
header, not by Lean's parser: so the library imports nothing of `Lean` and
does not change with Lean's internal API between nightlies. Ported from
grand-persuit's `Tests/Imports.lean`.

The supported header: whitespace, line comments (`--`) and block comments
(`/- … -/`, nested as Lean's lexer nests them), the words `module`,
`prelude`, `public`, `meta` and `import` (with one `all` after it), and
module names whose parts are ASCII letters, digits and `_` (`plainName`).
The header ends at the first other word, at a doc or module comment (an
opener followed by `-` or `!`, `/--/` included, as Lean's lexer reads it) or
at the end of the file. Any other form (an escaped name `«A».B`, a name the
lexer would end early, as in `A#check`, a part starting with a digit, an
`import` with no name after it, a second `all`, a word that only starts with a header keyword, as in `import«A»`) makes the
header *not read whole*: `imports?` then answers none, never a list that
might miss an import. -/

namespace Deps.Header

/-- Whether `s` is a module name this reader reads: dot-separated parts,
each of ASCII letters, digits and `_`, not starting with a digit. Lean
accepts more (a part in `«»`, Unicode letters, subscripts); those are
refused here. -/
def plainName (s : String) : Bool :=
  (s.splitOn ".").all fun p =>
    !p.isEmpty && !p.front.isDigit && p.all fun c => c.isAlphanum || c == '_'

/-- `cs` after the block comment it is `depth` levels inside, as Lean's
lexer nests them: each `/-` opens one more level, each `-/` closes one. -/
def skipComment : Nat → List Char → List Char
  | 0, cs => cs
  | d + 1, '-' :: '/' :: cs => skipComment d cs
  | d + 1, '/' :: '-' :: cs => skipComment (d + 2) cs
  | d + 1, _ :: cs => skipComment (d + 1) cs
  | _ + 1, [] => []

/-- A word, `acc` reversed before the rest: the characters up to whitespace
or a comment's start, and what follows them. -/
def word (acc : List Char) : List Char → List Char × List Char
  | [] => (acc.reverse, [])
  | '-' :: '-' :: cs => (acc.reverse, '-' :: '-' :: cs)
  | '/' :: '-' :: cs => (acc.reverse, '/' :: '-' :: cs)
  | c :: cs => if c.isWhitespace then (acc.reverse, c :: cs) else word (c :: acc) cs

/-- The next word of `cs` and what follows it, whitespace and comments
skipped; none at the end. A doc comment (a block comment's opener followed
by `-` or `!`) is a command, not a comment: it is returned as one word,
which ends the header. `fuel` bounds the steps, each of which takes at
least one character. -/
def nextWord : Nat → List Char → Option (String × List Char)
  | 0, _ | _, [] => none
  | n + 1, '-' :: '-' :: cs => nextWord n (cs.dropWhile (· != '\n'))
  | n + 1, '/' :: '-' :: cs => match cs with
    | c :: _ => if c == '-' || c == '!' then some ("/-" ++ c.toString, []) else nextWord n (skipComment 1 cs)
    | [] => none
  | n + 1, c :: cs =>
    if c.isWhitespace then nextWord n cs else
    let (w, rest) := word [] (c :: cs)
    some (String.ofList w, rest)

/-- The words of a header other than `import`, passed over. -/
def headerWords : List String := ["module", "prelude", "public", "meta"]

/-- Where the reader is in the header: between commands of the header, after
`import`, or after `import all`, where only a module name may follow. -/
inductive At where
  | top
  | afterImport
  | afterAll
  deriving BEq

/-- The imports at the head of `cs`, before `acc` reversed, and whether the
header was read whole (the module's doc comment states the grammar). `fuel`
bounds the steps of `nextWord` too: each word takes at least one character,
so after `k` words `fuel` is still above the characters left. -/
def headerOf (acc : List String) : Nat → At → List Char → List String × Bool
  | 0, _, _ => (acc.reverse, false)
  | n + 1, pos, cs =>
    match nextWord (n + 1) cs with
    | none => (acc.reverse, pos == .top)
    | some (w, rest) =>
      match pos with
      | .afterImport =>
        if w == "all" then headerOf acc n .afterAll rest
        else if plainName w then headerOf (w :: acc) n .top rest
        else (acc.reverse, false)
      | .afterAll =>
        if w != "all" && plainName w then headerOf (w :: acc) n .top rest
        else (acc.reverse, false)
      | .top =>
        if w == "import" then headerOf acc n .afterImport rest
        else if w ∈ headerWords then headerOf acc n .top rest
        else (acc.reverse, !("import" :: headerWords).any fun (k : String) => w.startsWith k)

/-- The modules the header of the Lean source `text` imports, in the
header's order, each once; none when the header is not read whole (the
module's doc comment says which forms are read). A header never closed by a
command (a block comment left open) is read up to where the comment
opens, as Lean reads it before it fails to compile the file. -/
def imports? (text : String) : Option (Array String) :=
  match headerOf [] (text.length + 1) .top text.toList with
  | (imports, true) => some imports.eraseDups.toArray
  | (_, false) => none

end Deps.Header
