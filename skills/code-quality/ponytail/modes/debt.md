# Ponytail Debt

Every deliberate ponytail shortcut carries a `ponytail:` comment naming its
ceiling and upgrade path. Collect them into one ledger so a deferral cannot
quietly become permanent.

## Scan

Search the repo for comment markers, skipping `node_modules`, `.git`, and build
output. Pattern: `(#|//) ?ponytail:` (add other comment prefixes if the stack
uses them).

Each hit is one ledger row. Requiring the comment prefix keeps prose that merely
mentions the convention out of the ledger.

## Output

One row per marker, grouped by file:

`<file>:<line>, <what was simplified>. ceiling: <the limit named>. upgrade: <the trigger to revisit>.`

The convention is `ponytail: <ceiling>, <upgrade path>`, so pull the ceiling and
trigger straight from the comment. Owner per row: `git blame -L<line>,<line>`.

Flag rot risk: any `ponytail:` comment naming no upgrade path or trigger gets a
`no-trigger` tag — those are the ones that silently rot.

End with `<N> markers, <M> with no trigger.` Nothing found:
`No ponytail: debt. Clean ledger.`

## Boundaries

Reads and reports only, changes nothing. Persist it only on request (e.g.
`PONYTAIL-DEBT.md`). One-shot.
