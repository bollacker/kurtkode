# Savings model for the kurtkode audit. Measured inputs (list price, per run) from the stores.
bank = dict(ling=0.00025, deepseek=0.00045, deepseek_charged=0.00183, haiku=0.00144, argon=0.0207)
hard = dict(ling=0.00031, haiku=0.00154, mercury=0.00087, argon=0.0349, sonnet=0.0229, opus=0.0458, gpt=0.0397, kimi=0.0287)
passr = dict(ling=0.981, deepseek=0.998, haiku=0.992, mercury=0.914, frontier=1.0)
print("== Static per-run savings, measured workloads (no quality loss detectable on these benchmarks) ==")
for name, tbl, fr in [("bank", bank, bank['argon']), ("hard", hard, hard['opus']), ("hard vs sonnet", hard, hard['sonnet'])]:
    for m in ('ling','haiku','mercury','deepseek','deepseek_charged'):
        if m in tbl:
            print(f"{name:14s} {m:17s} ${tbl[m]:.5f}  vs frontier ${fr:.4f}: saves {100*(1-tbl[m]/fr):5.1f}%   vs haiku ${tbl['haiku']:.5f}: saves {100*(1-tbl[m]/tbl['haiku']):6.1f}%")
print()
print("== Base-rate correction of detector precision ==")
def prec(recall, far, base):
    tp = recall*base; fp = far*(1-base); return tp/(tp+fp)
for label, recall, far in [("Haiku judge parent (cf5 enriched: 60/90, 2/114)",60/90,2/114),
                           ("Haiku reviewer (bank1 enriched: 56/56, 2/24)",1.0,2/24),
                           ("deepseek reviewer (51/55, 0/24 -> assume 0.5/24)",51/55,0.5/24),
                           ("Haiku judge parent on mercury (3/12, 6/128)",3/12,6/128)]:
    print(label)
    for base in (0.02,0.06,0.10,0.25):
        print(f"   base rate {base:4.0%}: precision {prec(recall,far,base):5.1%}")
print()
print("== Cascade economics at a 2% failure base rate (bank): cheap run + detector, escalate on fire ==")
def cascade(cheap, det, recall, far, base, up, upcost, pass_cheap, pass_up):
    fire = recall*base + far*(1-base)
    cost = cheap + det + fire*upcost
    # passes: cheap passes not fired keep; fired ones get up's pass
    passes = (1-base)*(1-far) + fire*pass_up  # approx (fired failures become up's pass)
    return cost, passes
for det_name, det, recall, far in [("grounded checks (free; 16%/31%)",0.0,0.16,0.007),
                                   ("Haiku judge parent $0.00112",0.00112,0.667,0.0175),
                                   ("deepseek reviewer $0.0001",0.0001,0.93,0.02),
                                   ("perfect oracle",0.0,1.0,0.0),
                                   ("2nd ling run, agreement (placeholder r=0.5 far=0.05)",0.00025,0.5,0.05)]:
    c,p = cascade(bank['ling'],det,recall,far,0.019,'haiku',bank['haiku'],0.981,0.992)
    print(f"{det_name:52s} cost ${c:.5f} ({100*c/bank['haiku']:5.1f}% of Haiku)  pass {p:.3%}  (always ling: $0.00025, 98.1%; always Haiku: $0.00144, 99.2%)")
