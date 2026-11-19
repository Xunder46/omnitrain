# Evidence — plan 219

- P1 builder: `RecordsLinkRow`, the row in the populated list, `test/stats_records_link_test.dart`: green.
- Owner decision after P1: row only, the header icon goes (the row was built before that answer; the owner then agreed).
- P2 builder: icon removed, row closes the empty branch too, primer copy, six readers moved; readers green (primer 8, heading 15, records_and_trends 18, link 7, fuel 54, weight 12, ui_standards 41).
- Lead mutation pass (6): row never shows, missing in the empty state, tap does nothing, tap opens another screen, header icon back, primer label old: all KILLED, sources restored and compared.
- Review: APPROVE WITH FIXES (0 blocker, 1 major: `docs/README.md` Stats row still said the header opens Records & Trends; 1 minor: a comment citing a gap S-21902 does not assert); both fixed.
