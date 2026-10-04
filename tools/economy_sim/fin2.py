from sim import *
base=dict(minutes=45,sessions=2,interval=1.2,eff=0.7,waste=0.3,stars=2.3,wheel=2,ad_gems=0.5,mult_rate=0.01,mult_cap=1.5,cost_scale=1,goal_cap=20,tab0=[5,7,9,11,13,15,17,20])
for nm,m,s_ in (('Gundelik 20dk',20,1),('HEDEF 45dk',45,2),('Yogun 120dk',120,3)):
    done,hist,mins,cpd,stall=run(dict(base,minutes=m,sessions=s_),700)
    print(f'{nm:<16} town {done["town"]} lines {done["lines"]} duvar {stall} coin/gun {cpd:.0f} |',' '.join(f'd{d}:ch{h[0]}/T{h[1]}/g{h[4]}' for d,h in hist.items() if d in (7,30,90,180)))
print('t=1 normal bolum (ch200):',[round(x,1) for x in chapter(201,base,0)[1:3]],' boss ch200:',[round(x,1) for x in chapter(200,base,0)[1:3]])
