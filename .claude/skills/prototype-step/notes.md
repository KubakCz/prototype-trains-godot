# Writing the notes up

Read this once the step is built and verified. Writing the notes up is expected, not optional -
but each kind goes in one place:

- **`.claude/rules/<area>.md`** gets **anything you learned the hard way** - a Godot trap, a
  silent failure, an hour lost to something that looked like it worked - in the rule file for the
  area it bites (or a new rule file with its own `paths:` and a row in CLAUDE.md's rule table).
  Keep the entry in the voice of the others, including what it cost; that is what makes it stick.
- **CLAUDE.md** gets only what every session needs before it knows it needs it: a trap any
  script could hit, a new directory in the layout, a row in the docs table. It has a size budget
  (its last section); stay under it. No subsystem walkthroughs, no area-specific traps.
- **`docs/architecture.md`** gets new classes in the class map and new scenes in the scene list.
- **`docs/<subsystem>.md`** gets how the thing you just built actually works and *why it is that
  way*: the rules, the cases that look like bugs and are not, and the decisions you took.
  Extend the existing file if your step extended that subsystem; add a new one, and a row in
  CLAUDE.md's "Where things are written down" table, if the step introduced a subsystem of its own.
- **`docs/further_development.md`** gets what your step leaves for a later one, under that
  step's heading: seams you deliberately left, limits the next implementer will hit, decisions
  already taken that they should not re-open. Delete the notes you have just made obsolete by
  building the thing they were about.
- **`prototype_goals.md` gets nothing** but the *(done)* marker on the step. If your step changed
  what a later step should be, write that in `docs/further_development.md` and mention it in
  conversation.
- **`tests/README.md`** gets anything new about running or writing the suite; `tests/suites.md`
  a row per new suite (the test-writer adds those).

When a step supersedes something these files describe - a placeholder replaced, a rule changed -
**edit the old text out** rather than adding a note beside it. Two descriptions of one rule is
how a doc starts lying.
