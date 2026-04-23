# Session Handoffs

> **Purpose:** End-of-session notes so the next Claude session (or human) picks up cleanly without re-discovering state.
>
> **When to add:** At the end of any session that left work in-flight, made non-trivial changes, or uncovered info the next session needs. Use `/session` to add one.

---

## Template

```
## YYYY-MM-DD — <Session title>

**What shipped:**
- <change> — <file:line or commit>

**In flight (not yet shipped):**
- <what> — <blocker or next step>

**Gotchas the next session should know:**
- <anything surprising>

**Next session should probably:**
- <suggested next step>
```

---

<!-- Add new sessions above this line, newest first -->
