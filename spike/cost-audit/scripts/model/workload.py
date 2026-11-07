# Realistic-workload savings model for the kurtkode audit. All per-run prices are measured list prices from the stores
# (bank: cf6/bank1; hard tier: cf3a/cf3b); class C is modeled as 10x a hard-tier run (unmeasured: flagged).
import itertools
price = {  # $/run by class: A short lookup (bank), B small edit (hard tier), C long task (10x hard tier)
 'ling':   dict(A=0.00025, B=0.00031, C=0.0031),
 'haiku':  dict(A=0.00144, B=0.00154, C=0.0154),
 'sonnet': dict(A=0.0214,  B=0.0229,  C=0.229),
 'argon':  dict(A=0.0207,  B=0.0349,  C=0.349),
 'opus':   dict(A=0.0428,  B=0.0458,  C=0.458),
}
passr = {'ling':dict(A=0.981,B=0.993,C=None), 'haiku':dict(A=0.992,B=0.993,C=None),
         'sonnet':dict(A=1.0,B=1.0,C=0.98),'argon':dict(A=1.0,B=1.0,C=0.98),'opus':dict(A=1.0,B=1.0,C=0.98)}
mix = dict(A=10, B=6, C=4)   # runs per developer-day (defined mix; sensitivity below)
def day(policy, cheapC=0.85):
    """policy: dict class->model, or callable. Returns ($/day, expected failures/day)."""
    cost=fails=0.0
    for c,n in mix.items():
        m = policy[c]
        p = passr[m][c] if passr[m][c] is not None else cheapC
        cost += n*price[m][c]; fails += n*(1-p)
    return cost, fails
def cascade_day(cheap='ling', up='haiku', recall=0.3, far=0.01, cheapC=0.85, classes=('A','B'), restC='sonnet', review=0.0001):
    cost=fails=0.0
    for c,n in mix.items():
        if c in classes:
            base = 1-(passr[cheap][c] if passr[cheap][c] is not None else cheapC)
            fire = recall*base + far*(1-base)
            cost += n*(price[cheap][c] + review + fire*price[up][c])
            fails += n*(base*(1-recall) + fire*(1-passr[up][c] if passr[up][c] else 0.1))
        else:
            cost += n*price[restC][c]; fails += n*(1-passr[restC][c])
    return cost, fails
rows=[]
for name,pol in [("always Opus",dict(A='opus',B='opus',C='opus')),("always Sonnet (session model)",dict(A='sonnet',B='sonnet',C='sonnet')),
                 ("always argon",dict(A='argon',B='argon',C='argon')),("always Haiku",dict(A='haiku',B='haiku',C='haiku')),
                 ("always ling (C at 85%)",dict(A='ling',B='ling',C='ling')),
                 ("A,B on ling; C on Sonnet",dict(A='ling',B='ling',C='sonnet')),
                 ("A,B on Haiku; C on Sonnet",dict(A='haiku',B='haiku',C='sonnet'))]:
    c,f=day(pol); rows.append((name,c,f))
for name,kw in [("cheap-first A,B + grounded-signal escalation to Haiku; C Sonnet",dict(recall=0.3,far=0.01)),
                ("cheap-first A,B + deepseek review trigger (r=.75,far=.02); C Sonnet",dict(recall=0.75,far=0.02)),
                ("cheap-first A,B + perfect trigger; C Sonnet",dict(recall=1.0,far=0.0))]:
    c,f=cascade_day(**kw); rows.append((name,c,f))
base=dict((r[0],r[1]) for r in rows)
print(f"{'policy':70s} {'$/day':>9s} {'fails/day':>9s} {'vs Opus':>8s} {'vs Sonnet':>9s} {'vs Haiku':>8s}")
for name,c,f in rows:
    print(f"{name:70s} {c:9.4f} {f:9.2f} {100*(1-c/base['always Opus']):7.1f}% {100*(1-c/base['always Sonnet (session model)']):8.1f}% {100*(1-c/base['always Haiku']):7.1f}%")
print("\nSensitivity: share of class C (long tasks) and cheap pass rate on C, policy 'A,B on ling; C on Sonnet' vs always Sonnet")
for nC in (0,2,4,8,12):
    mix['C']=nC
    c1,_=day(dict(A='ling',B='ling',C='sonnet')); c0,_=day(dict(A='sonnet',B='sonnet',C='sonnet'))
    print(f"  C={nC:2d}/day: saves {100*(1-c1/c0):5.1f}% of the Sonnet bill; class C is {100*nC*price['sonnet']['C']/c0 if c0 else 0:5.1f}% of it")
mix['C']=4
print("\nAll-ling incl. C, failures/day by cheap pass rate on C:")
for pC in (0.7,0.8,0.9,0.95):
    c,f=day(dict(A='ling',B='ling',C='ling'),cheapC=pC); print(f"  pass {pC:.2f}: ${c:.4f}/day, {f:.2f} failures/day (Sonnet: {day(dict(A='sonnet',B='sonnet',C='sonnet'))[1]:.2f})")
