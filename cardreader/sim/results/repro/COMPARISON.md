# Every criterion, this machine against RESULTS.md

Written by a comparison script from `repro/RESULTS.md` (this machine) and `../RESULTS.md`
(committed). Brackets are Wilson 95% intervals. "yes": each proportion lies inside the other's
interval; "overlap only": the intervals overlap but at least one point lies outside the other's
interval; no criterion had intervals that do not overlap. "time" counts rows with a card past its
bound (Walk 8 s, Turn 6 s). See ../REPRODUCTION.md.

| condition | rows | criterion | this machine | verdict | committed | verdict | verdicts | proportions agree |
|---|---|---|---|---|---|---|---|---|
| nominal | pre-registered | position (within 10 cm) | 452/455 = 99.3% [98.1, 99.8] | PASS | 449/455 = 98.7% [97.2, 99.4] | PASS | same | yes |
| nominal | pre-registered | heading (within 15 deg) | 452/455 = 99.3% [98.1, 99.8] | PASS | 449/455 = 98.7% [97.2, 99.4] | PASS | same | yes |
| nominal | pre-registered | falls (fell) | 0/455 = 0.0% [0.0, 0.8] | PASS | 0/455 = 0.0% [0.0, 0.8] | PASS | same | yes |
| nominal | pre-registered | time (a late card) | 0/455 = 0.0% [0.0, 0.8] | PASS | 0/455 = 0.0% [0.0, 0.8] | PASS | same | yes |
| nominal | pre-registered | ending badly (ended still, one sentence) | 2/2 = 100.0% [34.2, 100.0] | PASS | 6/6 = 100.0% [61.0, 100.0] | PASS | same | overlap only |
| nominal | Walk back | position (within 10 cm) | 400/403 = 99.3% [97.8, 99.7] | PASS | 400/403 = 99.3% [97.8, 99.7] | PASS | same | yes |
| nominal | Walk back | heading (within 15 deg) | 401/403 = 99.5% [98.2, 99.9] | PASS | 400/403 = 99.3% [97.8, 99.7] | PASS | same | yes |
| nominal | Walk back | falls (fell) | 0/403 = 0.0% [0.0, 0.9] | PASS | 0/403 = 0.0% [0.0, 0.9] | PASS | same | yes |
| nominal | Walk back | time (a late card) | 0/403 = 0.0% [0.0, 0.9] | PASS | 0/403 = 0.0% [0.0, 0.9] | PASS | same | yes |
| nominal | Walk back | ending badly (ended still, one sentence) | 2/2 = 100.0% [34.2, 100.0] | PASS | 3/3 = 100.0% [43.8, 100.0] | PASS | same | yes |
| nominal | every row (packs) | position (within 10 cm) | 208/209 = 99.5% [97.3, 99.9] | PASS | 208/209 = 99.5% [97.3, 99.9] | PASS | same | yes |
| nominal | every row (packs) | heading (within 15 deg) | 208/209 = 99.5% [97.3, 99.9] | PASS | 208/209 = 99.5% [97.3, 99.9] | PASS | same | yes |
| nominal | every row (packs) | falls (fell) | 0/209 = 0.0% [0.0, 1.8] | FAIL | 0/209 = 0.0% [0.0, 1.8] | FAIL | same | yes |
| nominal | every row (packs) | time (a late card) | 0/209 = 0.0% [0.0, 1.8] | PASS | 0/209 = 0.0% [0.0, 1.8] | PASS | same | yes |
| nominal | every row (packs) | ending badly (ended still, one sentence) | 1/1 = 100.0% [20.7, 100.0] | PASS | 1/1 = 100.0% [20.7, 100.0] | PASS | same | yes |
| randomized | pre-registered | position (within 10 cm) | 441/455 = 96.9% [94.9, 98.2] | PASS | 441/455 = 96.9% [94.9, 98.2] | PASS | same | yes |
| randomized | pre-registered | heading (within 15 deg) | 434/455 = 95.4% [93.0, 97.0] | PASS | 440/455 = 96.7% [94.6, 98.0] | PASS | same | yes |
| randomized | pre-registered | falls (fell) | 1/455 = 0.2% [0.0, 1.2] | FAIL | 0/455 = 0.0% [0.0, 0.8] | PASS | DIFFERENT | overlap only |
| randomized | pre-registered | time (a late card) | 0/455 = 0.0% [0.0, 0.8] | PASS | 0/455 = 0.0% [0.0, 0.8] | PASS | same | yes |
| randomized | pre-registered | ending badly (ended still, one sentence) | 9/9 = 100.0% [70.1, 100.0] | PASS | 7/7 = 100.0% [64.6, 100.0] | PASS | same | yes |
| randomized | Walk back | position (within 10 cm) | 392/403 = 97.3% [95.2, 98.5] | PASS | 390/403 = 96.8% [94.6, 98.1] | PASS | same | yes |
| randomized | Walk back | heading (within 15 deg) | 395/403 = 98.0% [96.1, 99.0] | PASS | 396/403 = 98.3% [96.5, 99.2] | PASS | same | yes |
| randomized | Walk back | falls (fell) | 0/403 = 0.0% [0.0, 0.9] | PASS | 0/403 = 0.0% [0.0, 0.9] | PASS | same | yes |
| randomized | Walk back | time (a late card) | 0/403 = 0.0% [0.0, 0.9] | PASS | 0/403 = 0.0% [0.0, 0.9] | PASS | same | yes |
| randomized | Walk back | ending badly (ended still, one sentence) | 6/6 = 100.0% [61.0, 100.0] | PASS | 5/5 = 100.0% [56.6, 100.0] | PASS | same | overlap only |
| randomized | every row (packs) | position (within 10 cm) | 161/209 = 77.0% [70.9, 82.2] | FAIL | 165/208 = 79.3% [73.3, 84.3] | FAIL | same | yes |
| randomized | every row (packs) | heading (within 15 deg) | 180/209 = 86.1% [80.8, 90.2] | FAIL | 186/208 = 89.4% [84.5, 92.9] | FAIL | same | yes |
| randomized | every row (packs) | falls (fell) | 0/209 = 0.0% [0.0, 1.8] | FAIL | 0/208 = 0.0% [0.0, 1.8] | FAIL | same | yes |
| randomized | every row (packs) | time (a late card) | 0/209 = 0.0% [0.0, 1.8] | PASS | 0/208 = 0.0% [0.0, 1.8] | PASS | same | yes |
| randomized | every row (packs) | ending badly (ended still, one sentence) | 1/1 = 100.0% [20.7, 100.0] | PASS | 3/3 = 100.0% [43.8, 100.0] | PASS | same | yes |
| randomized-10hz | pre-registered | position (within 10 cm) | 437/455 = 96.0% [93.8, 97.5] | PASS | 442/455 = 97.1% [95.2, 98.3] | PASS | same | yes |
| randomized-10hz | pre-registered | heading (within 15 deg) | 427/455 = 93.8% [91.2, 95.7] | FAIL | 441/455 = 96.9% [94.9, 98.2] | PASS | DIFFERENT | overlap only |
| randomized-10hz | pre-registered | falls (fell) | 0/455 = 0.0% [0.0, 0.8] | PASS | 0/455 = 0.0% [0.0, 0.8] | PASS | same | yes |
| randomized-10hz | pre-registered | time (a late card) | 1/455 = 0.2% [0.0, 1.2] | FAIL | 0/455 = 0.0% [0.0, 0.8] | PASS | DIFFERENT | overlap only |
| randomized-10hz | pre-registered | ending badly (ended still, one sentence) | 16/16 = 100.0% [80.6, 100.0] | PASS | 8/8 = 100.0% [67.6, 100.0] | PASS | same | yes |
| randomized-10hz | Walk back | position (within 10 cm) | 381/403 = 94.5% [91.9, 96.4] | FAIL | 374/403 = 92.8% [89.9, 94.9] | FAIL | same | yes |
| randomized-10hz | Walk back | heading (within 15 deg) | 385/403 = 95.5% [93.1, 97.2] | PASS | 387/403 = 96.0% [93.6, 97.5] | PASS | same | yes |
| randomized-10hz | Walk back | falls (fell) | 0/403 = 0.0% [0.0, 0.9] | PASS | 0/403 = 0.0% [0.0, 0.9] | PASS | same | yes |
| randomized-10hz | Walk back | time (a late card) | 1/403 = 0.2% [0.0, 1.4] | FAIL | 0/403 = 0.0% [0.0, 0.9] | PASS | DIFFERENT | overlap only |
| randomized-10hz | Walk back | ending badly (ended still, one sentence) | 12/12 = 100.0% [75.7, 100.0] | PASS | 15/15 = 100.0% [79.6, 100.0] | PASS | same | yes |
| randomized-10hz | every row (packs) | position (within 10 cm) | 153/209 = 73.2% [66.8, 78.8] | FAIL | 156/204 = 76.5% [70.2, 81.8] | FAIL | same | yes |
| randomized-10hz | every row (packs) | heading (within 15 deg) | 185/209 = 88.5% [83.5, 92.2] | FAIL | 181/204 = 88.7% [83.7, 92.4] | FAIL | same | yes |
| randomized-10hz | every row (packs) | falls (fell) | 0/209 = 0.0% [0.0, 1.8] | FAIL | 0/204 = 0.0% [0.0, 1.8] | FAIL | same | yes |
| randomized-10hz | every row (packs) | time (a late card) | 0/209 = 0.0% [0.0, 1.8] | PASS | 0/204 = 0.0% [0.0, 1.8] | PASS | same | yes |
| randomized-10hz | every row (packs) | ending badly (ended still, one sentence) | 9/9 = 100.0% [70.1, 100.0] | PASS | 5/5 = 100.0% [56.6, 100.0] | PASS | same | yes |
| stressed-10hz | pre-registered | position (within 10 cm) | 375/455 = 82.4% [78.7, 85.6] | FAIL | 395/455 = 86.8% [83.4, 89.6] | FAIL | same | overlap only |
| stressed-10hz | pre-registered | heading (within 15 deg) | 381/455 = 83.7% [80.1, 86.8] | FAIL | 397/455 = 87.3% [83.9, 90.0] | FAIL | same | overlap only |
| stressed-10hz | pre-registered | falls (fell) | 2/455 = 0.4% [0.1, 1.6] | FAIL | 0/455 = 0.0% [0.0, 0.8] | PASS | DIFFERENT | overlap only |
| stressed-10hz | pre-registered | time (a late card) | 0/455 = 0.0% [0.0, 0.8] | PASS | 0/455 = 0.0% [0.0, 0.8] | PASS | same | yes |
| stressed-10hz | pre-registered | ending badly (ended still, one sentence) | 39/39 = 100.0% [91.0, 100.0] | PASS | 26/26 = 100.0% [87.1, 100.0] | PASS | same | yes |
| stressed-10hz | Walk back | position (within 10 cm) | 332/403 = 82.4% [78.4, 85.8] | FAIL | 322/403 = 79.9% [75.7, 83.5] | FAIL | same | yes |
| stressed-10hz | Walk back | heading (within 15 deg) | 341/403 = 84.6% [80.8, 87.8] | FAIL | 339/403 = 84.1% [80.2, 87.4] | FAIL | same | yes |
| stressed-10hz | Walk back | falls (fell) | 0/403 = 0.0% [0.0, 0.9] | PASS | 0/403 = 0.0% [0.0, 0.9] | PASS | same | yes |
| stressed-10hz | Walk back | time (a late card) | 1/403 = 0.2% [0.0, 1.4] | FAIL | 0/403 = 0.0% [0.0, 0.9] | PASS | DIFFERENT | overlap only |
| stressed-10hz | Walk back | ending badly (ended still, one sentence) | 23/23 = 100.0% [85.7, 100.0] | PASS | 30/30 = 100.0% [88.6, 100.0] | PASS | same | yes |
| stressed-10hz | every row (packs) | position (within 10 cm) | 102/209 = 48.8% [42.1, 55.5] | FAIL | 100/227 = 44.1% [37.7, 50.6] | FAIL | same | yes |
| stressed-10hz | every row (packs) | heading (within 15 deg) | 126/209 = 60.3% [53.5, 66.7] | FAIL | 135/227 = 59.5% [53.0, 65.6] | FAIL | same | yes |
| stressed-10hz | every row (packs) | falls (fell) | 0/209 = 0.0% [0.0, 1.8] | FAIL | 0/227 = 0.0% [0.0, 1.7] | FAIL | same | yes |
| stressed-10hz | every row (packs) | time (a late card) | 0/209 = 0.0% [0.0, 1.8] | PASS | 0/227 = 0.0% [0.0, 1.7] | PASS | same | yes |
| stressed-10hz | every row (packs) | ending badly (ended still, one sentence) | 37/37 = 100.0% [90.6, 100.0] | PASS | 45/45 = 100.0% [92.1, 100.0] | PASS | same | yes |
| nominal-10hz | pre-registered | position (within 10 cm) | 198/200 = 99.0% [96.4, 99.7] | PASS | 198/200 = 99.0% [96.4, 99.7] | PASS | same | yes |
| nominal-10hz | pre-registered | heading (within 15 deg) | 198/200 = 99.0% [96.4, 99.7] | PASS | 198/200 = 99.0% [96.4, 99.7] | PASS | same | yes |
| nominal-10hz | pre-registered | falls (fell) | 0/200 = 0.0% [0.0, 1.9] | FAIL | 0/200 = 0.0% [0.0, 1.9] | FAIL | same | yes |
| nominal-10hz | pre-registered | time (a late card) | 0/200 = 0.0% [0.0, 1.9] | PASS | 0/200 = 0.0% [0.0, 1.9] | PASS | same | yes |
| nominal-10hz | pre-registered | ending badly (ended still, one sentence) | 2/2 = 100.0% [34.2, 100.0] | PASS | 2/2 = 100.0% [34.2, 100.0] | PASS | same | yes |
| nominal-10hz | Walk back | position (within 10 cm) | 36/36 = 100.0% [90.4, 100.0] | PASS | 36/36 = 100.0% [90.4, 100.0] | PASS | same | yes |
| nominal-10hz | Walk back | heading (within 15 deg) | 36/36 = 100.0% [90.4, 100.0] | PASS | 36/36 = 100.0% [90.4, 100.0] | PASS | same | yes |
| nominal-10hz | Walk back | falls (fell) | 0/36 = 0.0% [0.0, 9.6] | FAIL | 0/36 = 0.0% [0.0, 9.6] | FAIL | same | yes |
| nominal-10hz | Walk back | time (a late card) | 0/36 = 0.0% [0.0, 9.6] | PASS | 0/36 = 0.0% [0.0, 9.6] | PASS | same | yes |
| nominal-10hz | Walk back | ending badly | 0/0 | PASS | 0/0 | PASS | same | n/a (no rows) |
| nominal-50hz | pre-registered | position (within 10 cm) | 197/200 = 98.5% [95.7, 99.5] | PASS | 199/200 = 99.5% [97.2, 99.9] | PASS | same | overlap only |
| nominal-50hz | pre-registered | heading (within 15 deg) | 197/200 = 98.5% [95.7, 99.5] | PASS | 199/200 = 99.5% [97.2, 99.9] | PASS | same | overlap only |
| nominal-50hz | pre-registered | falls (fell) | 0/200 = 0.0% [0.0, 1.9] | FAIL | 0/200 = 0.0% [0.0, 1.9] | FAIL | same | yes |
| nominal-50hz | pre-registered | time (a late card) | 0/200 = 0.0% [0.0, 1.9] | PASS | 0/200 = 0.0% [0.0, 1.9] | PASS | same | yes |
| nominal-50hz | pre-registered | ending badly (ended still, one sentence) | 3/3 = 100.0% [43.8, 100.0] | PASS | 1/1 = 100.0% [20.7, 100.0] | PASS | same | yes |
| nominal-50hz | Walk back | position (within 10 cm) | 35/36 = 97.2% [85.8, 99.5] | PASS | 36/36 = 100.0% [90.4, 100.0] | PASS | same | overlap only |
| nominal-50hz | Walk back | heading (within 15 deg) | 35/36 = 97.2% [85.8, 99.5] | PASS | 36/36 = 100.0% [90.4, 100.0] | PASS | same | overlap only |
| nominal-50hz | Walk back | falls (fell) | 0/36 = 0.0% [0.0, 9.6] | FAIL | 0/36 = 0.0% [0.0, 9.6] | FAIL | same | yes |
| nominal-50hz | Walk back | time (a late card) | 0/36 = 0.0% [0.0, 9.6] | PASS | 0/36 = 0.0% [0.0, 9.6] | PASS | same | yes |
| nominal-50hz | Walk back | ending badly | 1/1 | PASS | 0/0 | PASS | same | n/a (no rows) |
