# Walk lead from the system identification

Written by `walk_lead_from_sysid.py` from `cardreader/sim/sysid/raw/` (the step trials, three per level). Median [min to max] over trials. Lead = odometry coast + odometry speed x (half the client's frame gap + half the 20 Hz control tick); frame gaps from sysid.md (60 ms at 20 Hz, 101 ms at 10 Hz).

| command | trials | odometry coast (m) | trunk coast (m) | odometry speed (m/s) | 99% of coast after (s) | odometry / trunk distance | lead at 20 Hz (m) | lead at 10 Hz (m) |
|---|---|---|---|---|---|---|---|---|
| +0.300 | 3 | 0.008 [0.006 to 0.008] | 0.007 [0.007 to 0.009] | 0.095 [0.095 to 0.096] | 0.24 [0.19 to 0.26] | 1.012 [1.010 to 1.015] | 0.013 [0.012 to 0.014] | 0.015 [0.014 to 0.016] |
| +0.350 | 3 | 0.013 [0.013 to 0.016] | 0.014 [0.012 to 0.016] | 0.115 [0.114 to 0.116] | 0.17 [0.12 to 0.20] | 1.008 [1.006 to 1.016] | 0.020 [0.020 to 0.023] | 0.022 [0.022 to 0.025] |
| +0.400 | 3 | 0.014 [0.013 to 0.016] | 0.013 [0.010 to 0.018] | 0.135 [0.133 to 0.137] | 0.16 [0.15 to 0.20] | 1.001 [0.997 to 1.013] | 0.021 [0.020 to 0.023] | 0.024 [0.023 to 0.026] |
| -0.350 | 3 | 0.027 [0.026 to 0.031] | 0.029 [0.027 to 0.032] | 0.141 [0.141 to 0.143] | 0.76 [0.76 to 0.81] | 0.956 [0.956 to 0.961] | 0.035 [0.034 to 0.039] | 0.038 [0.037 to 0.042] |
| -0.400 | 3 | 0.039 [0.039 to 0.040] | 0.039 [0.038 to 0.040] | 0.163 [0.162 to 0.163] | 0.64 [0.61 to 0.65] | 0.956 [0.951 to 0.959] | 0.048 [0.048 to 0.049] | 0.052 [0.051 to 0.053] |

Chosen for duck-card-loop/2, at Studio's 10 Hz:

- `back_approach_m` 0.052: the -0.40 row's lead at 10 Hz (Walk back sends 0.40 at every speed).
- `approach_m` 0.022: the +0.35 row's lead at 10 Hz (Normal; Slow 0.015 and Fast 0.024 are within a centimetre).
- `back_settle_s` 0.8: odometry covers 99% of its coast within 0.61 to 0.65 s at -0.40, plus one 10 Hz frame gap (p95 120 ms).
- `settle_s` 0.4: 99% within 0.15 to 0.26 s forward, plus one frame gap.
- `lead_m` [0.0, 0.12]: a coast is never negative here, and the top is a bit more than twice the largest lead above.

Odometry under-counts walking back by about 4.4% against the trunk (the "odometry / trunk distance" column). That is not in the lead: the controller closes on odometry and cannot see it.
