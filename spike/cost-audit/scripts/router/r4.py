import sys
sys.path.insert(0, sys.argv[1])
from common import md
# (label, mix, $/run, passes, runs) from repro/per_model_stats.md
B=[("ling-3.0-flash","bank+hard pooled (cf2+cf6+cf3a)",0.00024,884,899),
   ("deepseek-v4-flash-0731#off @ $0.00045","bank+hard pooled",0.00045,892,900),
   ("deepseek-v4-flash-0731#off @ $0.00183","bank+hard pooled",0.00183,892,900),
   ("mercury-2.5","cf2+cf3a (no cf6; harder mix)",0.00060,395,420),
   ("claude-haiku-5.5","bank+hard pooled",0.00132,894,900)]
H=[("ling-3.0-flash","hard tier (cf3a)",0.00031,139,140),
   ("claude-haiku-5.5","hard tier (cf3a)",0.00154,139,140),
   ("claude-sonnet-5.5","hard tier (cf3b)",0.02286,42,42),
   ("gemini-4-argon","hard tier (cf3b)",0.03488,42,42),
   ("claude-opus-5.5","hard tier (cf3b)",0.04582,42,42)]
R=[]
for blk in (B,H):
    lc,lk,ln=blk[0][2],blk[0][3],blk[0][4]; lp=lk/ln; lcps=lc/lp
    for name,mix,c,k,n in blk:
        p=k/n; cps=c/p; m=cps/lcps
        # Laplace-smoothed pass for 100% cells
        ps=(k+1)/(n+2)
        be=(c-lc)/(p-lp) if p>lp else None
        casc=lc+(1-lp)*c
        R.append((name,mix,f"{c:.5f}",f"{100*p:.1f}% ({k}/{n}; Laplace {100*ps:.1f}%)",f"{cps:.5f}",
                  "–" if name.startswith("ling") else f"{m:.2f}×",
                  "–" if name.startswith("ling") else (f"${be:.3f}" if be is not None else "never (not more reliable)"),
                  "–" if name.startswith("ling") else f"{casc:.5f} ({100*(lp+(1-lp)*p):.2f}%)"))
out=["# R4. Price sensitivity of the pool's ordering (arithmetic only)\n",
"Cost per success (CPS) = mean $/run ÷ pass rate (the expected spend per success if failures are detected and retried on the same model). 'ling price × to tie' = how far ling's price must rise before the row's model has the lower CPS (= CPS_row / CPS_ling); values < 1× mean the row is already cheaper per success. 'Break-even failure cost' = the cost of one undetected failure F at which always-row equals always-ling in expected cost, (c_row − c_ling) / (p_row − p_ling): routing to the dearer model pays only if a silent failure costs more than this. 'Cascade' = ling first, escalate the failures (assumes failures are detected) to the row's model: expected $/task and pass. Rows are compared with ling on the same task mix (pooled block vs ling pooled; hard block vs ling on cf3a).\n",
md(["model","task mix","mean $/run","pass rate","$/success","ling price × to tie","break-even failure cost","cascade ling→row: $/task (pass)"],R),
"\nCaveats: frontier pass rates are 42/42 (95% one-sided lower bound ≈ 93%); the break-even for them uses the observed 100%, so with Laplace smoothing (97.7%) Opus/Sonnet would not beat ling's 99.3% at all on the hard tier. mercury-2.5's mix excludes cf6. The pass-rate gaps (≤ 1 pt) rest on 6–15 failures per model, so break-even figures carry roughly ±50% uncertainty."]
open(sys.argv[2],"w").write("\n".join(out)+"\n"); print("\n".join(out))
