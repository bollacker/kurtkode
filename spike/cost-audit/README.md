# Cost audit working papers (2026-10-26)

Scratch material behind `COST_AUDIT.md` at the repository root. Nothing here is product code.

- `scripts/repro/`: parse the eval stores (`census.py`, `stats.py`), judge calibration (`judges.py`), review-sim
  reproduction (`reviewsim.py`). Run from the repository root with `python3 -I`.
- `scripts/detectors/`: E1–E4 (cross-model agreement, self-consistency, where the money goes, failure clustering).
- `scripts/router/`: R1–R4 (oracle routing headroom, kNN vs prior, difficulty signals, price flips).
- `scripts/model/`: the savings and base-rate arithmetic (`savings.py`, `workload.py`).
- `working-papers/`: the subagents' full reports: claims extracted from the docs, the code audit, the literature
  bibliography, the experiment write-ups with full tables, the reproduced per-model statistics and judge calibration.

The scripts write their intermediate data under a scratch folder (see each script's paths); they read
`eval-results/runs/` only and change nothing.
