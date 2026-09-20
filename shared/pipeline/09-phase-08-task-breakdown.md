## Phase 8 — Task Breakdown

```
[ ] 1. <task> — <exact file path(s)> — concrete description of change
[ ] 2. <task> — <exact file path(s)> — concrete description of change
...
```

Order by dependency. Each task should be small and focused (one logical change).

### The graph decides the width (Deep tier)

Order is not enough when Phase 9 may fan out: write what each task **needs**, then read the shape.

```
[ ] 1. <root task> — <paths> — <change>
[ ] 2. <task> — <paths> — <change>   needs 1
[ ] 3. <task> — <paths> — <change>   needs 1
```

- A **leaf** is a task whose `needs` are all satisfied and which no other pending task needs.
- **Width = the number of independent leaves**, capped by `--max-agents`. Never more: an agent past
  the leaf count queues behind another and pays orchestration on top of the wait.
- A chain (`1 ← 2 ← 3`) has width 1 and fans out to nothing. **Say so** rather than splitting a
  dependent task to manufacture parallelism — that is how a slice lands on code that does not exist.
- The width, the cap and the bill go in the Phase 5 decision pack, before any of it is spent.

---

