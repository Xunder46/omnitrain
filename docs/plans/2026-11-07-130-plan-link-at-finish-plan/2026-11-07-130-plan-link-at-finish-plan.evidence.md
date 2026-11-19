# Evidence — 130: a plan the wrist starts is marked done when the workout finishes

All numbers below were observed by the lead (Claude), not copied from an agent's report.

| Check | Observed |
|---|---|
| Builder run | `20261107-165332-crew-builder-app`, 10 m 7 s, brief with exact production text; three new `onLifecycle`/`_linkPlanAtEnd` pieces, five old tests re-pinned, S-13030..S-13038 added (Mock and Hive) |
| Lead's mutation pass (bridge file, backup outside the tree, restored and `cmp`-identical) | M1 link at report → KILLED; M2 no origin guard → KILLED; M3 no row-exists gate → KILLED; M5 abandoned not forgotten → KILLED; M7 skip when the phone ended it → KILLED; M4a no `isCompleted` gate → **SURVIVED**; M4b no `linkedSessionId` gate → **SURVIVED**; M6 completed not forgotten → **SURVIVED** |
| Closing the survivors (lead wrote the tests) | M4a/M4b: S-13035's one fixture was both completed and linked, so each arm hid behind the other; now one test per arm (completed with no link; linked and not completed). M6: S-13033 used a recorder that also wrote the plan, so the plan gate stopped the second delivery; now a recorder that writes nothing, so only the bridge's own forgetting can stop it. All three re-run → KILLED |
| `flutter test test/watch_session_import_test.dart` | `+72: All tests passed!` |
| Full `flutter test` (900 s cap) | `+7043 ~2: All tests passed!` (includes plan 131's S-13040) |
| `flutter analyze` | 181 issues (baseline) |
| Invariant grep | no match |
| `flutter test test/ui_standards_contract_test.dart test/docs_indexing_contract_test.dart` | `+54: All tests passed!` |
| `plan-lint.py after` | clean |

Not run: any device or simulator. Owner check: finish a wrist-started planned workout and see the plan done on the phone's calendar; discard one and see it stay planned.
