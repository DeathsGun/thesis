# verify_independent.py
#
# Unabhaengige Nachrechnung der Kennzahlen aus scan_analysis.R, direkt aus
# all.ndjson und ohne Rueckgriff auf R-Zwischenergebnisse. Zweck ist der
# Nachweis, dass die in der Arbeit berichteten Zahlen aus den Rohdaten
# reproduzierbar sind und nicht von der Implementierung abhaengen.
#
# Reproduziert (Stand 2026-09-08): Buckets 446/569/505/171/3/24,
# Layer 1 = 1015 (59,1 %), Layer 2 = 1494 (87,0 %), direkter Hard Floor
# = 236 (13,74 %), neuer Hard Floor = 688 (40,0 %), Viabilitaet 744 (43,3 %)
# mit unterer Schranke 672 (39,1 %), Uebergangsmatrix identisch zu
# transition_matrix.csv.
#
# Zusaetzlich beantwortet: Identitaetspruefung der beiden 236er-Mengen und
# die Klassifikation auf Skriptebene.
#
# Aufruf: python3 verify_independent.py   (erwartet all.ndjson im selben Ordner)

import json, collections
import os
P=os.path.join(os.path.dirname(os.path.abspath(__file__)),"all.ndjson")
scripts=[]; contents={}; imports=[]
for line in open(P, encoding="utf-8"):
    line=line.strip()
    if not line: continue
    r=json.loads(line); t=r.get("type")
    if t=="script": scripts.append(r)
    elif t=="content": contents[r["contentHash"]]=r
    elif t=="import": imports.append(r)
print("raw: scripts=%d contents=%d imports=%d"%(len(scripts),len(contents),len(imports)))

# 2.5 drop minified
min_h={h for h,c in contents.items() if c.get("likelyMinified")}
print("likelyMinified contents=%d"%len(min_h))
contents={h:c for h,c in contents.items() if h not in min_h}
scripts=[s for s in scripts if s["contentHash"] not in min_h]
imports=[i for i in imports if i["contentHash"] not in min_h]
print("after drop: scripts=%d contents=%d imports=%d"%(len(scripts),len(contents),len(imports)))

def bucket(c):
    if c.get("usesDynamicCode"): return "dynamic-code"
    if c.get("usesNodeGlobals"): return "node-globals"
    if c.get("usesNodeBuiltins"): return "node-builtins"
    if c.get("usesPackages"): return "packages-only"
    if c.get("selfContained"): return "self-contained"
    return "unknown"
cb={h:bucket(c) for h,c in contents.items()}
LV=["self-contained","packages-only","node-globals","node-builtins","dynamic-code","unknown"]
rank={b:i for i,b in enumerate(LV)}
sb=[(s["tenantId"], cb.get(s["contentHash"],"unknown"), s["scriptId"], s["contentHash"]) for s in scripts]
hardest={}
for tid,b,_,_ in sb:
    if tid not in hardest or rank[b]>rank[hardest[tid]]: hardest[tid]=b
N=len(hardest); print("\ntotal_tenants=%d"%N)
tc=collections.Counter(hardest.values())
for b in LV: print("  %-15s %5d  %.1f%%"%(b,tc[b],100*tc[b]/N))
layer1={t for t,b in hardest.items() if b in ("self-contained","packages-only")}
print("layer1 (no shims) = %d  %.1f%%"%(len(layer1),100*len(layer1)/N))

# tenant -> contentHash
t_of=collections.defaultdict(set)
for s in scripts: t_of[s["tenantId"]].add(s["contentHash"])
h_tenants=collections.defaultdict(set)
for s in scripts: h_tenants[s["contentHash"]].add(s["tenantId"])

# 7a shimmable
SHIM={"process.env","node:Buffer"}
ng_h={h for h,b in cb.items() if b=="node-globals"}
tfeat=collections.defaultdict(set)
for h in ng_h:
    fs=[f for f in (contents[h].get("runtimeFeatures") or []) if not str(f).startswith("commonjs:")]
    for t in h_tenants.get(h,()):
        tfeat[t].update(fs)
ng_tenants={t for t,b in hardest.items() if b=="node-globals"}
shim_only=sum(1 for t in ng_tenants if t in tfeat and tfeat[t]<=SHIM)
print("\nnode-globals-hardest tenants=%d, shimmable_only=%d  (%.1f%% of them)"%(len(ng_tenants),shim_only,100*shim_only/len(ng_tenants)))
l2=len(layer1)+shim_only
print("Layer 2 = %d / %d = %.1f%%"%(l2,N,100*l2/N))

HARD={"fs","https","http","net","tls","dns","dgram","child_process","os","tty","readline","v8","perf_hooks","diagnostics_channel","cluster","worker_threads"}
builtin_pairs=set()
for i in imports:
    if i.get("category")=="builtin":
        for t in h_tenants.get(i["contentHash"],()): builtin_pairs.add((t,i["package"]))
any_builtin={t for t,_ in builtin_pairs}
direct_hard={t for t,p in builtin_pairs if p in HARD}
print("\n7b direct hard floor = %d / %d = %.2f%%   (soft-only=%d, any-builtin=%d)"%(len(direct_hard),N,100*len(direct_hard)/N,len(any_builtin)-len(direct_hard),len(any_builtin)))

FHB={"axios","node-fetch","isomorphic-fetch","ofetch"}
FSH={"@dvelop-sdk/dms","@dvelop-sdk/business-objects","@dvelop-sdk/identityprovider","@dvelop-sdk/task","@dvelop-sdk/core"}
CHK=FHB|FSH
bare=set()
for i in imports:
    if i.get("category")=="bare":
        for t in h_tenants.get(i["contentHash"],()): bare.add((t,i["package"]))
npm_t={t for t,_ in bare}; pkgs={p for _,p in bare}
ck_pairs=[(t,p) for t,p in bare if p in CHK]
ck_t={t for t,_ in ck_pairs}
print("coverage: %d of %d packages, %d/%d pairs (%.1f%%), %d/%d npm tenants (%.1f%%)"%(
    len(CHK),len(pkgs),len(ck_pairs),len(bare),100*len(ck_pairs)/len(bare),len(ck_t),len(npm_t),100*len(ck_t)/len(npm_t)))
fetch_hard={t for t,p in bare if p in FHB}
by_t=collections.defaultdict(set)
for t,p in bare: by_t[t].add(p)
unresolved={t for t,ps in by_t.items() if not (ps & CHK)}
print("fetch_hard tenants=%d, transitive-unresolved tenants=%d"%(len(fetch_hard),len(unresolved)))
new_hard=direct_hard|fetch_hard
print("new hard floor = %d / %d = %.1f%%"%(len(new_hard),N,100*len(new_hard)/N))

def newcls(t):
    if t in new_hard: return "hard-floor"
    o=hardest[t]
    if o=="node-globals": return "shimmable (node-globals)"
    if o=="node-builtins": return "shimmable (soft builtins only)"
    if o in ("self-contained","packages-only"): return "V8-viable (layer 1)"
    return "unknown"
M=collections.Counter((hardest[t],newcls(t)) for t in hardest)
print("\nTRANSITION MATRIX")
for o in LV:
    for (oo,nn),v in sorted(M.items(), key=lambda kv:-kv[1]):
        if oo==o: print("  %-15s -> %-32s %5d"%(oo,nn,v))
print("  matrix sum = %d"%sum(M.values()))
nc=collections.Counter(newcls(t) for t in hardest)
for k,v in sorted(nc.items(), key=lambda kv:-kv[1]): print("  NEW %-32s %5d  %.1f%%"%(k,v,100*v/N))

lo=layer1-(fetch_hard|unresolved); hi=layer1-fetch_hard
print("\ninterval: lower=%d (%.1f%%)  upper=%d (%.1f%%)  unresolved-in-layer1=%d"%(
    len(lo),100*len(lo)/N,len(hi),100*len(hi)/N,len(layer1&unresolved)))

# --- OPEN CHECK 2: the two 236 ---
cell=[t for t in hardest if hardest[t]=="node-globals" and t in new_hard]
A=direct_hard; B=set(cell)
print("\n=== CHECK: the two 236 ===")
print("A = 7b direct-hard-floor      : %d"%len(A))
print("B = matrix cell node-globals  : %d"%len(B))
print("A == B ? %s   |A&B|=%d  |A-B|=%d  |B-A|=%d"%(A==B,len(A&B),len(A-B),len(B-A)))

# --- OPEN CHECK 4: script level ---
sh_hard=set()
for i in imports:
    if i.get("category")=="builtin" and i["package"] in HARD: sh_hard.add(i["contentHash"])
    if i.get("category")=="bare" and i["package"] in FHB: sh_hard.add(i["contentHash"])
def script_class(h):
    if h in sh_hard: return "hard-floor"
    b=cb.get(h,"unknown")
    if b=="node-globals": return "shimmable"
    if b=="node-builtins": return "shimmable (soft)"
    if b in ("self-contained","packages-only"): return "V8-viable"
    if b=="dynamic-code": return "hard-floor"
    return "unknown"
sc=collections.Counter(script_class(s["contentHash"]) for s in scripts)
tot=len(scripts)
print("\n=== SCRIPT LEVEL (script versions, n=%d) ==="%tot)
for k,v in sorted(sc.items(), key=lambda kv:-kv[1]): print("  %-18s %5d  %.1f%%"%(k,v,100*v/tot))
per=collections.defaultdict(lambda:[0,0])
for s in scripts:
    t=s["tenantId"]; per[t][1]+=1
    if script_class(s["contentHash"])=="hard-floor": per[t][0]+=1
hf=[(t,per[t][0],per[t][1]) for t in new_hard if t in per]
print("hard-floor tenants with script data: %d"%len(hf))
d=collections.Counter(b for _,b,_ in hf)
print("blocking scripts per hard-floor tenant:")
for k in sorted(d): print("   %2d blocking : %4d tenants"%(k,d[k]))
one=[x for x in hf if x[1]==1]
onemulti=[x for x in one if x[2]>1]
print("exactly 1 blocking script: %d   of those with >1 script total: %d"%(len(one),len(onemulti)))
blocked=sum(b for _,b,_ in hf); tots=sum(c for _,_,c in hf)
print("scripts of hard-floor tenants: %d total, %d blocking (%.1f%%)"%(tots,blocked,100*blocked/tots))
