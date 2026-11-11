#!/usr/bin/env python3
"""Add 25 synthetic preview sessions only to this project's dedicated emulator."""
import datetime as dt
import json
from pathlib import Path
import sqlite3
import subprocess

adb = '/home/erik/Android/Sdk/platform-tools/adb'
serial = 'emulator-5580'
package = 'de.feltledger.felt_ledger'
def call(*args, **kwargs):
    return subprocess.check_output([adb, '-s', serial, *args], **kwargs)
assert call('shell', 'getprop', 'ro.kernel.qemu').strip() == b'1'
assert call('emu', 'avd', 'name').splitlines()[0] == b'felt_ledger_dev'
call('shell', 'am', 'force-stop', package)
path = Path('/tmp/felt-preview.db')
original = call('exec-out', 'run-as', package, 'cat', 'databases/felt_ledger.db')
Path('/tmp/felt-before-preview.db').write_bytes(original)
path.write_bytes(original)
now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
def stamp(value):
    return value.isoformat().replace('+00:00', 'Z')
def money(value):
    return round(value * 10000)
with sqlite3.connect(path) as db:
    db.execute('PRAGMA foreign_keys=ON')
    bank = db.execute("SELECT id FROM definitions WHERE category='bankroll' LIMIT 1").fetchone()[0]
    definitions = [
        ('location', {'id':'preview-club','name':'Demo · Pokerclub','currency':'EUR','type':'Casino'}),
        ('location', {'id':'preview-home','name':'Demo · Home Game','currency':'EUR','type':'Home Game'}),
        ('location', {'id':'preview-online','name':'Demo · Online','currency':'EUR','type':'Online'}),
        ('game', {'id':'preview-holdem','name':'Texas Holdem','limit':'NL','smallBlind':money(.5),'bigBlind':money(1)}),
        ('game', {'id':'preview-omaha','name':'Omaha','limit':'PL','smallBlind':money(1),'bigBlind':money(2)}),
    ]
    for category, value in definitions:
        db.execute('INSERT OR IGNORE INTO definitions VALUES(?,?,?)', (value['id'],category,json.dumps(value)))
    profits = [85,-100,140,35,-75,210,-50,60,-100,325,45,-80,170,-50,95,220,-100,30,-65,150,75,-100,260,-40,120]
    for i, profit in enumerate(profits):
        tournament = i % 4 == 1
        omaha = i % 5 == 2 and not tournament
        start = now - (dt.timedelta(minutes=20) if i==0 else dt.timedelta(days=i*3,hours=5))
        end = now - dt.timedelta(minutes=5) if i==0 else start + dt.timedelta(hours=3, minutes=(i%3)*15)
        buy = 50 if tournament else 100
        rebuy = 50 if (i%5==0 or profit < -buy) else 0
        invested = buy + rebuy
        events=[]
        for j, ratio in enumerate([.85,1.2,.7,1.4,1.1], start=1):
            at = start + (end-start)*j/6
            if rebuy and j==3:
                events.append({'kind':'rebuy','at':stamp(at),'value':money(rebuy)})
            capital = buy + (rebuy if j>=3 else 0)
            stack = max(0, capital + profit*(j/6) + (ratio-1)*buy)
            events.append({'kind':'stack','at':stamp(at),'value':money(stack)})
        events.append({'kind':'note','at':stamp(start+(end-start)/3),'note':'Synthetische Vorschau-Session'})
        entry = {'id':f'preview-session-{i:02d}','bankroll':bank,'currency':'EUR',
                 'kind':'Turnier' if tournament else 'Cash Game',
                 'location':['preview-club','preview-home','preview-online'][i%3],
                 'game':'preview-omaha' if omaha else 'preview-holdem',
                 'smallBlind':money(1 if omaha else .5),'bigBlind':money(2 if omaha else 1),
                 'start':stamp(start),'end':stamp(end),'buyIn':money(buy),
                 'cashOut':money(invested+profit),'rebuys':1 if rebuy else 0,
                 'rebuyCost':money(rebuy),'breakSeconds':0,'tableSize':'Short-Handed',
                 'events':events,'notes':'Nur synthetische Beispieldaten für die Emulator-Vorschau.'}
        db.execute('INSERT OR REPLACE INTO entries VALUES(?,?,?)',(entry['id'],bank,json.dumps(entry)))
    assert db.execute("SELECT count(*) FROM entries WHERE id LIKE 'preview-session-%'").fetchone()[0] == 25
    assert db.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    total=db.execute('SELECT count(*) FROM entries').fetchone()[0]
call('push',str(path),'/data/local/tmp/felt-preview.db')
call('shell','run-as',package,'cp','/data/local/tmp/felt-preview.db','databases/felt_ledger.db')
call('shell','rm','/data/local/tmp/felt-preview.db')
call('shell','am','start','-n',package+'/.MainActivity')
print(json.dumps({'addedSyntheticSessions':25,'totalEntries':total,'device':serial,'avd':'felt_ledger_dev'}, indent=2))
