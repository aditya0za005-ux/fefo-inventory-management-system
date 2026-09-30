#!/usr/bin/env python3
"""Deterministic FEFO-vs-LIFO simulation. No claimed numbers are embedded."""
import argparse, json, random

def simulate(batches, qty, strategy):
    stock=[dict(x) for x in batches]
    order=range(len(stock)) if strategy=='FEFO' else range(len(stock)-1,-1,-1)
    remaining=qty
    for i in order:
        take=min(stock[i]['qty'],remaining); stock[i]['qty']-=take; remaining-=take
        if remaining==0: break
    return stock

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--runs',type=int,default=1000); ap.add_argument('--seed',type=int,default=42); ap.add_argument('--reservation',type=int,default=50); args=ap.parse_args()
    rng=random.Random(args.seed); results={}
    for strategy in ('FEFO','LIFO'):
        total_near=0; total_left=0
        for _ in range(args.runs):
            batches=[{'days':d,'qty':rng.randint(50,250)} for d in (3,8,15,25,60,90)]
            total_near += sum(x['qty'] for x in batches if x['days']<=30)
            left=simulate(batches,args.reservation,strategy)
            total_left += sum(x['qty'] for x in left if x['days']<=30)
        results[strategy]={'near_expiry_remaining':total_left/args.runs,'near_expiry_initial':total_near/args.runs,'near_expiry_percentage_left':(100*total_left/total_near if total_near else 0)}
    print(json.dumps({'runs':args.runs,'seed':args.seed,'reservation':args.reservation,'results':results},indent=2))
if __name__=='__main__': main()
