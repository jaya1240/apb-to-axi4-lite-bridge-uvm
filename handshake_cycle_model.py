"""
Cycle-accurate Python mirror of: apb_to_axi_bridge.sv FSM + apb_driver +
axi_driver (reactive) + both monitors + scoreboard rules + key SVA checks.
Sampling convention identical to the SV TB: processes resume at posedge
and see PRE-edge values; all writes are non-blocking (applied after every
process at this edge has run).
"""
import random, sys

IDLE, WRITE, BRESP, READ, RRESP = range(5)

class Bridge:
    def __init__(s):
        s.state = IDLE; s.addr=0; s.wdata=0; s.wstrb=0; s.write=0
        s.aw_done=0; s.w_done=0
    # combinational outputs given pre-edge inputs
    def comb(s, S):
        o = {}
        o['awvalid'] = int(s.state==WRITE and not s.aw_done)
        o['wvalid']  = int(s.state==WRITE and not s.w_done)
        o['bready']  = int(s.state==BRESP)
        o['arvalid'] = int(s.state==READ)
        o['rready']  = int(s.state==RRESP)
        o['awaddr']=o['araddr']=s.addr; o['wdata']=s.wdata; o['wstrb']=s.wstrb
        pready=0; prdata=0; pslverr=0
        if s.state==BRESP and S['bvalid']:
            pready=1; pslverr=int(S['bresp']!=0)
        elif s.state==RRESP and S['rvalid']:
            pready=1; prdata=S['rdata']; pslverr=int(S['rresp']!=0)
        o['pready']=pready; o['prdata']=prdata; o['pslverr']=pslverr
        return o
    def clock(s, S):
        st = s.state
        if st==IDLE:
            if S['psel'] and not S['penable']:
                s.addr=S['paddr']; s.wdata=S['pwdata']; s.wstrb=S['pstrb']; s.write=S['pwrite']
                s.aw_done=0; s.w_done=0
                s.state = WRITE if S['pwrite'] else READ
        elif st==WRITE:
            aw_hs = S['awvalid'] and S['awready']; w_hs = S['wvalid'] and S['wready']
            done = (aw_hs or s.aw_done) and (w_hs or s.w_done)
            if aw_hs: s.aw_done=1
            if w_hs:  s.w_done=1
            if done: s.state=BRESP
        elif st==BRESP:
            if S['bvalid'] and S['bready']: s.state=IDLE
        elif st==READ:
            if S['arvalid'] and S['arready']: s.state=RRESP
        elif st==RRESP:
            if S['rvalid'] and S['rready']: s.state=IDLE

def run(seed, n_xfers, mode):
    rnd = random.Random(seed)
    # bus registers driven by TB (non-DUT)
    R = dict(psel=0,penable=0,pwrite=0,paddr=0,pwdata=0,pstrb=0,
             awready=0,wready=0,bvalid=0,bresp=0,arready=0,rvalid=0,rdata=0,rresp=0)
    dut = Bridge()
    nba = {}
    def w(**kw): nba.update(kw)

    def delay():
        if mode=='fast': return 0
        if mode=='slow': return rnd.randint(5,15)
        return rnd.choice([0]*5+[1,2,3]*1+[4,8,12])

    # ---- stimulus ----
    items=[]
    for _ in range(n_xfers):
        wr = rnd.random()<0.5
        items.append(dict(addr=rnd.randrange(0,2**32)&~3, write=wr,
                          wdata=rnd.randrange(0,2**32),
                          strb=rnd.choice([0xF,0xF,0x3,0xC,0x0,0x5]) if wr else 0,
                          idle=rnd.choice([0,0,0,1,2,3,6,10])))
    done_apb=[]; 
    def resp_item():
        if mode=='err': r=rnd.choice([2,3])
        elif mode=='mixed': r=rnd.choices([0,2,3],[80,10,10])[0]
        else: r=0
        return dict(aw=delay(),w=delay(),ar=delay(),rd=delay(),resp=r,rdata=rnd.randrange(0,2**32))

    S = {}
    # ---- APB driver ----
    def apb_driver():
        w(psel=0,penable=0,pwrite=0,paddr=0,pwdata=0,pstrb=0)
        yield
        for it in items:
            if it['idle']>0:
                w(psel=0,penable=0)
                for _ in range(it['idle']): yield
            w(paddr=it['addr'],pwrite=int(it['write']),pwdata=it['wdata'],pstrb=it['strb'],psel=1,penable=0)
            yield
            w(penable=1)
            yield
            while not S['pready']: yield
            it['rdata']=S['prdata']; it['slverr']=S['pslverr']
            it['done']=True
            w(psel=0,penable=0)
    # ---- AXI reactive driver ----
    def accept(d, ready, valid):
        for _ in range(d): yield
        w(**{ready:1})
        yield
        while not S[valid]: yield
        w(**{ready:0})
    def par(*gens):
        alive=[True]*len(gens)
        while True:
            for i,g in enumerate(gens):
                if alive[i]:
                    try: next(g)
                    except StopIteration: alive[i]=False
            if not any(alive): return
            yield
    def axi_driver():
        w(awready=0,wready=0,bvalid=0,bresp=0,arready=0,rvalid=0,rdata=0,rresp=0)
        while True:
            while True:
                yield
                if S['awvalid'] or S['arvalid']: break
            is_write = S['awvalid']
            it = resp_item()
            if is_write:
                yield from par(accept(it['aw'],'awready','awvalid'), accept(it['w'],'wready','wvalid'))
                for _ in range(it['rd']): yield
                w(bvalid=1,bresp=it['resp'])
                yield
                while not S['bready']: yield
                w(bvalid=0)
            else:
                yield from accept(it['ar'],'arready','arvalid')
                for _ in range(it['rd']): yield
                w(rvalid=1,rdata=it['rdata'],rresp=it['resp'])
                yield
                while not S['rready']: yield
                w(rvalid=0)

    # ---- monitors ----
    apb_txns=[]; axi_txns=[]; errors=[]
    mon = dict(have_aw=0,have_w=0,w_addr=0,w_data=0,w_strb=0,r_addr=0,wait=0)
    prev = {}
    def monitors():
        if S['psel'] and S['penable']:
            if S['pready']:
                apb_txns.append(dict(addr=S['paddr'],write=S['pwrite'],wdata=S['pwdata'],strb=S['pstrb'],
                                     rdata=S['prdata'],slverr=S['pslverr'],waits=mon['wait']))
                mon['wait']=0
            else: mon['wait']+=1
        if S['awvalid'] and S['awready']: mon['w_addr']=S['awaddr']; mon['have_aw']=1
        if S['wvalid'] and S['wready']:   mon['w_data']=S['wdata']; mon['w_strb']=S['wstrb']; mon['have_w']=1
        if S['bvalid'] and S['bready']:
            if not (mon['have_aw'] and mon['have_w']): errors.append('B before AW/W')
            axi_txns.append(dict(write=1,addr=mon['w_addr'],wdata=mon['w_data'],wstrb=mon['w_strb'],resp=S['bresp']))
            mon['have_aw']=mon['have_w']=0
        if S['arvalid'] and S['arready']: mon['r_addr']=S['araddr']
        if S['rvalid'] and S['rready']:
            axi_txns.append(dict(write=0,addr=mon['r_addr'],rdata=S['rdata'],resp=S['rresp']))

    # ---- SVA-style checks ----
    def sva():
        for v,r in (('awvalid','awready'),('wvalid','wready'),('arvalid','arready')):
            if prev and prev[v] and not prev[r] and not S[v]: errors.append(f'{v} dropped before {r}')
        if prev and prev['bvalid'] and not prev['bready'] and not S['bvalid']: errors.append('bvalid dropped')
        if prev and prev['rvalid'] and not prev['rready'] and not S['rvalid']: errors.append('rvalid dropped')
        if (S['awvalid'] or S['wvalid'] or S['bvalid']) and (S['arvalid'] or S['rvalid']): errors.append('concurrent rd/wr')
        if prev and prev['psel'] and prev['penable'] and not prev['pready']:
            if not (S['psel'] and S['penable'] and S['pwrite']==prev['pwrite'] and S['paddr']==prev['paddr']):
                errors.append('APB access phase unstable')
        if prev and prev['psel'] and not prev['penable'] and not S['penable']: errors.append('setup >1 cycle')

    gens=[apb_driver(), axi_driver()]
    max_cycles = n_xfers*80+200
    for cyc in range(max_cycles):
        # pre-edge signal view
        S = dict(R); S.update(dut.comb(dict(R)))
        # dut comb depends on slave regs in R (already merged) -> recompute pready with full S
        S.update(dut.comb(S))
        monitors(); sva()
        nba.clear()
        for g in gens:
            try: next(g)
            except StopIteration: pass
        dut.clock(S)
        R.update(nba)
        prev = dict(S)
        if all(it.get('done') for it in items): 
            for _ in range(3):
                S = dict(R); S.update(dut.comb(R)); S.update(dut.comb(S)); monitors()
            break
    else:
        errors.append('DEADLOCK/timeout')

    # ---- scoreboard rules ----
    if len(apb_txns)!=len(axi_txns): errors.append(f'count mismatch apb={len(apb_txns)} axi={len(axi_txns)}')
    for i,(a,x) in enumerate(zip(apb_txns,axi_txns)):
        if a['write']!=x['write'] or a['addr']!=x['addr']: errors.append(f'#{i} dir/addr mismatch')
        if a['write'] and (a['wdata']!=x['wdata'] or a['strb']!=x['wstrb']): errors.append(f'#{i} wdata/strb mismatch')
        if a['slverr']!=int(x['resp']!=0): errors.append(f'#{i} slverr mismatch')
        if (not a['write']) and x['resp']==0 and a['rdata']!=x['rdata']: errors.append(f'#{i} rdata mismatch')
    # stimulus fidelity: what the DUT saw == what driver sent
    for i,(it,a) in enumerate(zip(items,apb_txns)):
        if (it['addr'],int(it['write']))!=(a['addr'],a['write']): errors.append(f'#{i} monitor != stimulus')
    return errors, len(apb_txns), cyc

bad=0; total=0
for mode in ('fast','mixed','err','slow'):
    for seed in range(40):
        e,n,c = run(seed, 60, mode); total+=n
        if e: bad+=1; print(mode, seed, e[:3])
print(f"transfers checked: {total}, failing runs: {bad}")
