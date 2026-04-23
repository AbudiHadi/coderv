# Known Issues & Recurring Bugs

> **Purpose:** Stop solving the same problem twice. Every time a non-obvious bug is fixed, log it here with symptom, root cause, and fix.
>
> **When to add:** After any bug fix where (a) the cause was non-obvious, (b) the same symptom could recur, or (c) the debugging took more than 15 minutes.

---

## Template

```
## KI-NNN: <Symptom in user's words>

**First seen:** YYYY-MM-DD
**Last seen:** YYYY-MM-DD
**Status:** open | fixed in commit <hash>

### Symptom
What the user/tester sees.

### Root cause
The actual bug — not a description of the fix.

### Fix
What was changed. File paths + line ranges.

### Prevention
What pattern or check would have caught this earlier? (Tests? Lint rule? Type? Review checklist?)

### Related
- ADR-NNN if relevant
- Other KI-NNN if part of a family
```

---

<!-- Add new entries above this line, newest first -->
