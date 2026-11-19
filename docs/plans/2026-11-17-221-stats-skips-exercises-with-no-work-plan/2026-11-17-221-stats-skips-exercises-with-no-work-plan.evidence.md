# Evidence — plan 221

- P1 builder: guard + zero-skip in `computeExerciseMetrics`, 5 tests: green; two readers red (S-1010, S-1017), rewritten in fix 1.
- Lead mutation pass (3): zero-skip removed, guard removed, skips every exercise: all KILLED.
- Review: APPROVE WITH FIXES; dead branch and stale comment removed; instrument readers re-run green (118).
