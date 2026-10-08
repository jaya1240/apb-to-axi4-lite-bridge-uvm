"""
Mutation check for handshake_cycle_model.py: seeds known bugs into the
modeled bridge and confirms the model's checks flag each one. A passing
model is only meaningful if it can also fail.

Usage:  python3 model/mutation_check.py
"""
import subprocess, sys, os

here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "handshake_cycle_model.py")).read()

mutations = {
    "PSLVERR ignores BRESP":         ("pready=1; pslverr=int(S['bresp']!=0)", "pready=1; pslverr=0"),
    "write strobes dropped":         ("s.wstrb=S['pstrb']", "s.wstrb=0xF"),
    "read data corrupted":           ("prdata=S['rdata']; pslverr=int(S['rresp']!=0)", "prdata=S['rdata']^1; pslverr=int(S['rresp']!=0)"),
    "address latched wrong":         ("s.addr=S['paddr']; s.wdata", "s.addr=S['paddr']^4; s.wdata"),
    "read/write direction swapped":  ("s.state = WRITE if S['pwrite'] else READ", "s.state = READ if S['pwrite'] else WRITE"),
    "bridge ignores W handshake":    ("done = (aw_hs or s.aw_done) and (w_hs or s.w_done)", "done = (aw_hs or s.aw_done)"),
}

all_caught = True
for name, (old, new) in mutations.items():
    assert old in src, f"mutation target not found: {name}"
    mutant = src.replace(old, new).replace("range(40)", "range(3)")
    tmp = os.path.join(here, "_mutant_tmp.py")
    open(tmp, "w").write(mutant)
    r = subprocess.run([sys.executable, tmp], capture_output=True, text=True)
    os.remove(tmp)
    last = (r.stdout.strip().splitlines() or [""])[-1]
    crashed = r.returncode != 0
    failing = "failing runs: 0" not in last
    caught = crashed or failing
    all_caught &= caught
    print(f"{name:32s} -> {'CAUGHT' if caught else 'MISSED'}  ({'checker crashed' if crashed else last})")

sys.exit(0 if all_caught else 1)
