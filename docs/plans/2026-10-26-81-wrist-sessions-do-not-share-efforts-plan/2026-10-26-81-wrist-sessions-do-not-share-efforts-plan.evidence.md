# Evidence — plan 81 (wrist sessions do not share efforts)

Reserved by the architect 2026-10-26. Implementers write baselines, suite outputs, red→green tables and footprints here; the plan holds only decisions and pointers.

- Base commit: `.work/2026-10-26-81/base.txt` (`56c3e56e3c6fb5b3d889010fae39e3bddfbf2dc7`).
- Lead's repro on base: `test/watch_second_session_same_exercise_repro_test.dart` fails — efforts of `s-w1` are `[]`, efforts of `s-w2` are `[sx-ex-bench]`, that effort holds three sets (`obs-sx-ex-bench-0/1/2-reps`).
