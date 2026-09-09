# sensitivity_minified.py
#
# Robustheitspruefung zum Filter DROP_MINIFIED aus scan_analysis.R.
# Rechnet die Kernkennzahlen einmal mit und einmal ohne die als
# likelyMinified markierten Inhalte und weist aus, wie viele Mandanten
# dabei die Klasse wechseln.
#
# Ergebnis (Stand 2026-09-08): 43,3 % gegen 42,2 % Viabilitaet,
# 40,0 % gegen 40,7 % Hard Floor, 28 Mandanten wechseln die Klasse.
# Die Grundgesamtheit 1.718 gegen 1.743 unterscheidet sich um genau die
# 25 Mandanten, deren Skripte vollstaendig minifiziert sind.

import json, collections, os
P=os.path.join(os.path.dirname(os.path.abspath(__file__)),"all.ndjson")
S=[];C={};I=[]
for line in open(P,encoding="utf-8"):
    line=line.strip()
    if not line: continue
    r=json.loads(line);t=r.get("type")
    if t=="script":S.append(r)
    elif t=="content":C[r["contentHash"]]=r
    elif t=="import":I.append(r)
HARD={"fs","https","http","net","tls","dns","dgram","child_process","os","tty","readline","v8","perf_hooks","diagnostics_channel","cluster","worker_threads"}
FHB={"axios","node-fetch","isomorphic-fetch","ofetch"}
FSH={"@dvelop-sdk/dms","@dvelop-sdk/business-objects","@dvelop-sdk/identityprovider","@dvelop-sdk/task","@dvelop-sdk/core"}
CHK=FHB|FSH
LV=["self-contained","packages-only","node-globals","node-builtins","dynamic-code","unknown"]
rank={b:i for i,b in enumerate(LV)}
def run(drop):
    mh={h for h,c in C.items() if c.get("likelyMinified")}
    cs={h:c for h,c in C.items() if not(drop and h in mh)}
    sc=[s for s in S if not(drop and s["contentHash"] in mh)]
    im=[i for i in I if not(drop and i["contentHash"] in mh)]
    def bk(c):
        if c.get("usesDynamicCode"):return "dynamic-code"
        if c.get("usesNodeGlobals"):return "node-globals"
        if c.get("usesNodeBuiltins"):return "node-builtins"
        if c.get("usesPackages"):return "packages-only"
        if c.get("selfContained"):return "self-contained"
        return "unknown"
    cb={h:bk(c) for h,c in cs.items()}
    ht=collections.defaultdict(set)
    for s in sc: ht[s["contentHash"]].add(s["tenantId"])
    hardest={}
    for s in sc:
        t=s["tenantId"];b=cb.get(s["contentHash"],"unknown")
        if t not in hardest or rank[b]>rank[hardest[t]]: hardest[t]=b
    N=len(hardest)
    bp=set();bare=set()
    for i in im:
        for t in ht.get(i["contentHash"],()):
            if i.get("category")=="builtin": bp.add((t,i["package"]))
            elif i.get("category")=="bare": bare.add((t,i["package"]))
    dh={t for t,p in bp if p in HARD}
    fh={t for t,p in bare if p in FHB}
    nh=dh|fh
    by=collections.defaultdict(set)
    for t,p in bare: by[t].add(p)
    unres={t for t,ps in by.items() if not(ps&CHK)}
    l1={t for t,b in hardest.items() if b in("self-contained","packages-only")}
    viable=l1-nh
    return dict(N=N,scripts=len(sc),l1=len(l1),hard=len(nh),viable=len(viable),
                lo=len(l1-(fh|unres)),cls={t:("hard-floor" if t in nh else ("V8-viable" if hardest[t] in("self-contained","packages-only") else "other")) for t in hardest})
a=run(True);b=run(False)
for nm,r in (("DROP_MINIFIED=TRUE",a),("DROP_MINIFIED=FALSE",b)):
    print("%-20s tenants=%d scripts=%d layer1=%d viable=%d (%.1f%%) hard=%d (%.1f%%) lower=%d (%.1f%%)"%(
        nm,r["N"],r["scripts"],r["l1"],r["viable"],100*r["viable"]/r["N"],r["hard"],100*r["hard"]/r["N"],r["lo"],100*r["lo"]/r["N"]))
ch=[t for t in a["cls"] if t in b["cls"] and a["cls"][t]!=b["cls"][t]]
print("tenants whose class changes when minified scripts are kept: %d"%len(ch))
print("  of those, viable->hard-floor: %d"%sum(1 for t in ch if a["cls"][t]=="V8-viable" and b["cls"][t]=="hard-floor"))
print("  viable->other: %d"%sum(1 for t in ch if a["cls"][t]=="V8-viable" and b["cls"][t]=="other"))
print("tenants present only in FALSE run: %d"%len(set(b["cls"])-set(a["cls"])))
