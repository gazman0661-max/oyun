from sim import *
base=dict(minutes=45,sessions=2,interval=1.2,eff=0.7,waste=0.3,stars=2.3,goal_cap=40,cap40=True,wheel=2,ad_gems=0.5,mult_rate=0.01,mult_cap=1.5,cost_scale=1)
def show(name,P,days=700):
    done,hist,mins,cpd,stall=run(P,days)
    print(f'{name:<26} town:{str(done["town"]):>4} lines:{str(done["lines"]):>4} duvar:{str(stall):>4} coin/gun {cpd:>6.0f} | '+' '.join(f'd{d}:ch{h[0]}/T{h[1]}/L{h[2]}/b{h[5]}/g{h[4]}' for d,h in hist.items() if d in (7,30,90,180)))
for nm,m,s_ in (('Gundelik 20dk',20,1),('HEDEF 45dk',45,2),('Yogun 120dk',120,3)):
    show(nm,dict(base,minutes=m,sessions=s_))
show('45dk atis 0.9s',dict(base,interval=0.9)); show('45dk atis 1.8s',dict(base,interval=1.8))
show('45dk reklam/cark yok',dict(base,wheel=0,ad_gems=0))
print('maliyet toplam: sehir',sum(BASE_COST)*8.25,'cizgi',2*sum(LINE),'slot',sum(SLOT))
