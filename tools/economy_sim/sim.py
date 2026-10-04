import math, random, itertools
R=[0,1,2,3,5,8,13,21,34]          # coinReward by tier 1..8
def M(L):                         # merge coins to build a level-L ball from level-1 units
    return sum((2**(L-n))*R[n] for n in range(2,L+1))
U=lambda L:2**(L-1)
BASE_COST=[450, 1050, 2000, 3600, 6000, 9600, 15000, 21000, 28500, 39000]
STAR_REQ=[1,2,4,6,9,12,15,18,20,22]
UP_MIN=[1,10,30,90,240,480,900,1560,2520,4200]
PROD=[0,3,5,7,10,13,17,21,26,31,37]
LINE=[900,1750,3200,5400,9000,14300,21600,30000,40800,55200,74400,99600,132000,174000,228000]
SLOT=[1800,5000]
DAILY=[50,75,100,150,200,300,500]
def kind(c):
    if c>=5 and c%10==0: return 'boss'
    if c>=5 and c%5==0: return 'easy'
    return 'normal'
def raw_goal(c):
    pos=((c-1)%8)+1; cyc=(c-1)//8
    if cyc==0: return (TAB0[0] if TAB0[0] else ([6,9,12,18,25,30,35,40] if CAP40[0] else [6,9,12,18,25,32,42,50]))[pos-1]
    return 10+pos*5+cyc*20
def goal(c, cap=None):
    r=raw_goal(c)
    if cap: r=min(r,cap)
    k=kind(c)
    return max(5,round(r*0.7)) if k=='easy' else max(5,round(r*0.5)) if k=='boss' else r
def diffT(c):
    t=min(1.0,(c-1)/40); return t*0.4 if kind(c)=='easy' else t
CAP40=[False]
TAB0=[None]
MULT=[0.03,3.0]
def coin_mult(c): return min(MULT[1],1+MULT[0]*((c-1)//8))
def per_order(c):
    k=kind(c); t=diffT(c)
    w=[0,0,8,35,35,22] if k=='boss' else [30-20*t,25-10*t,20+2*t,13+10*t,8+14*t,4+16*t]
    tot=sum(w); ec=eu=0
    for i,wi in enumerate(w):
        L=i+1; p=wi/tot
        rew=R[L]*(2 if k=='boss' else 1)
        ec+=p*(rew+M(L)); eu+=p*U(L)
    if k!='boss' and c>=6:
        pr=0.12+0.18*t
        rc=ru=0
        for L in (3,4,5):
            rc+=(1.25*R[L]+M(L))/3; ru+=U(L)/3
        ec=(1-pr)*ec+pr*rc; eu=(1-pr)*eu+pr*ru
    return ec,eu
def chapter(c,P,luck):
    g=goal(c,P.get('goal_cap')); ec,eu=per_order(c)
    coins=g*ec*(1+P['waste'])*coin_mult(c)
    l2=0.25+luck*0.02
    spawn=(1-l2)+2*l2
    throws=g*eu/(spawn*P['eff'])
    minutes=throws*P['interval']/60+0.5
    return g,coins,minutes,throws
def run(P,days=540,verbose=False):
    MULT[0]=P.get('mult_rate',0.03); MULT[1]=P.get('mult_cap',3.0); CAP40[0]=P.get('cap40',False); TAB0[0]=P.get('tab0')
    CS=P.get('cost_scale',1.0)
    coins=0;gems=5;c=1;energy=5.0
    lv=[0]*6; end=[0.0]*6; builders=1
    thr=luck=slot=0
    wstars=[0.0]*6
    hist={}
    tot_minutes=0
    done={'town':None,'lines':None,'all':None}
    wk={'o':0,'m':0,'c':0}; mo={'o':0,'m':0,'c':0}
    sess_hours={1:[19],2:[9,20],3:[8,14,21]}[P['sessions']]
    last_hour=None; sumcoin=0; chap_days=[]; stalled=[0]; stall_day=None
    for d in range(days):
        day_o=day_m=0; day_c=0
        for si,h in enumerate(sess_hours):
            now=d*24+h
            # completions
            for w in range(6):
                if end[w]>0 and end[w]<=now: lv[w]+=1; end[w]=0
            # energy regen since last
            if last_hour is not None: energy=min(5.0,energy+(now-last_hour)*6)
            last_hour=now
            budget=P['minutes']/P['sessions']
            limit=P['minutes']/P['sessions']*1.25
            while budget>0 and energy>=1:
                g,cc,mins,thrs=chapter(c,P,luck)
                if mins>limit:
                    # DUVAR: yeni bolum seansa sigmiyor -> en yuksek sigan eski bolumu tekrar oyna (sadece coin)
                    cf=c-1
                    while cf>1 and (chapter(cf,P,luck)[2]>limit or kind(cf)!='normal'): cf-=1
                    g,cc,mins,thrs=chapter(cf,P,luck)
                    energy-=1; energy=min(5.0,energy+mins/10)
                    budget-=mins; tot_minutes+=mins
                    coins+=cc; day_c+=cc; day_o+=g; day_m+=thrs*0.6
                    stalled[0]+=1
                    continue
                energy-=1; energy=min(5.0,energy+mins/10)
                budget-=mins; tot_minutes+=mins
                coins+=cc; day_c+=cc; day_o+=g; day_m+=thrs*0.6
                # first clear extras
                if c<=3: coins+=[150,250,400][c-1]
                gems+=(1 if c<=20 else 0)+(3 if c%5==0 else 0)+(3 if kind(c)=='boss' else 0)
                if kind(c)=='boss': coins+=500
                wstars[((c-1)//8)%6]+=P['stars']
                c+=1
            # production collect
            gap=24/P['sessions']
            for w in range(6):
                rate=PROD[lv[w]]*(100+25*w)//100
                coins+=min(rate*gap, rate*8)
            # spend
            while True:
                opts=[]
                busy=sum(1 for e in end if e>0)
                for w in range(6):
                    if lv[w]<10 and end[w]==0 and busy<builders and c>=8*w+1 and wstars[w]>=STAR_REQ[lv[w]]:
                        cost=int(BASE_COST[lv[w]]*(100+15*w)//100//10*10*CS)
                        if coins>=cost: opts.append((cost,'t',w))
                if thr<15 and coins>=LINE[thr]*CS: opts.append((int(LINE[thr]*CS),'thr',0))
                if luck<15 and coins>=LINE[luck]*CS: opts.append((int(LINE[luck]*CS),'luck',0))
                if slot<2 and coins>=SLOT[slot]*CS: opts.append((int(SLOT[slot]*CS),'slot',0))
                if not opts: break
                cost,k,w=min(opts)
                coins-=cost
                if k=='t': end[w]=now+UP_MIN[lv[w]]*(100+10*w)/100/60
                elif k=='thr': thr+=1
                elif k=='luck': luck+=1
                else: slot+=1
            # builders
            if builders==1 and gems>=250: gems-=250; builders=2
            elif builders==2 and gems>=700: gems-=700; builders=3
        # daily extras
        coins+=DAILY[d%7]
        ok_o=day_o>=40; ok_m=day_m>=120; ok_c=day_c>=900
        coins+=150*ok_o+120*ok_m+200*ok_c
        for k,v in (('o',day_o),('m',day_m),('c',day_c)):
            wk[k]+=v; mo[k]+=v
        coins+=P['wheel']*179; gems+=P['wheel']*0.54+P['ad_gems']*6
        gems+=0.7  # daily day7 gems /7
        if (d+1)%7==0:
            coins+=800*(wk['o']>=200)+600*(wk['m']>=650)+1000*(wk['c']>=5500)
            gems+=5*((wk['o']>=200)+(wk['m']>=650)+(wk['c']>=5500)); wk={'o':0,'m':0,'c':0}
        if (d+1)%30==0:
            coins+=3000*(mo['o']>=800)+2200*(mo['m']>=2600)+4000*(mo['c']>=22000)
            gems+=15*((mo['o']>=800)+(mo['m']>=2600)+(mo['c']>=22000)); mo={'o':0,'m':0,'c':0}
        sumcoin+=day_c
        if stall_day is None and stalled[0]>0: stall_day=d+1
        if done['town'] is None and sum(lv)>=60: done['town']=d+1
        if done['lines'] is None and thr>=15 and luck>=15 and slot>=2: done['lines']=d+1
        if done['all'] is None and done['town'] and done['lines']: done['all']=d+1
        if d+1 in (7,30,90,180,360,540): hist[d+1]=(c-1,sum(lv),thr+luck,int(coins),int(gems),builders)
    return done,hist,tot_minutes/days,sumcoin/days,stall_day
if __name__=='__main__':
    base=dict(minutes=45,sessions=2,interval=1.2,eff=0.7,waste=0.3,stars=2.3,goal_cap=None,wheel=2,ad_gems=0.5)
    print('goal/time by chapter (interval 1.2s, eff .7):')
    for c in (1,5,9,17,25,41,81,161):
        g,cc,m,t=chapter(c,base,0)
        print(f' ch{c:>4} goal {g:>4} coins {cc:>8.0f} minutes {m:>6.1f} coin/min {cc/m:>6.0f}')
