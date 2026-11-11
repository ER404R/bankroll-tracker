#!/usr/bin/env python3
"""Capture synthetic app evidence and verify real process-death recovery."""
import argparse
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import time
import xml.etree.ElementTree as ET

parser=argparse.ArgumentParser()
parser.add_argument('--serial',required=True)
a=parser.parse_args()
root=Path(__file__).resolve().parent.parent
out=root/'docs/validation'
adb='/home/erik/Android/Sdk/platform-tools/adb'
package='de.feltledger.felt_ledger'
def call(*args,binary=False):
    value=subprocess.check_output([adb,'-s',a.serial,*args])
    return value if binary else value.decode().strip()
if not a.serial.startswith('emulator-') or call('shell','getprop','ro.kernel.qemu')!='1' or call('emu','avd','name').splitlines()[0]!='felt_ledger_dev':
    raise SystemExit('Only the verified dedicated emulator is permitted.')
def ui():
    for _ in range(5):
        result=call('shell','uiautomator','dump','/sdcard/felt-ui.xml')
        if 'dumped' in result:
            return ET.fromstring(call('exec-out','cat','/sdcard/felt-ui.xml'))
        time.sleep(.5)
    raise RuntimeError('Emulator accessibility snapshot unavailable')
def tap(label,partial=False):
    tree=ui()
    matches=[e for e in tree.iter('node') if any((label in e.get(k,'') if partial else label==e.get(k,'')) for k in ['text','content-desc'])]
    if not matches:
        raise RuntimeError('UI item not visible: '+label)
    coords=list(map(int,re.findall(r'\d+',matches[-1].get('bounds'))))
    call('shell','input','tap',str((coords[0]+coords[2])//2),str((coords[1]+coords[3])//2))
    time.sleep(.8)
def navigate(label):
    tap('Navigationsmenü öffnen');tap(label)
def screen(name):
    (out/name).write_bytes(call('exec-out','screencap','-p',binary=True))
def snapshot(name):
    path=Path('/tmp')/('felt-'+name+'.db')
    path.write_bytes(call('exec-out','run-as',package,'cat','databases/felt_ledger.db',binary=True))
    with sqlite3.connect(path) as db:
        entries=db.execute('SELECT COUNT(*) FROM entries').fetchone()[0]
        row=db.execute("SELECT payload FROM state WHERE key='live'").fetchone()
        live=json.loads(row[0]) if row else None
        prefs=db.execute("SELECT payload FROM state WHERE key='preferences'").fetchone()
    return {'entries':entries,'live':live,'preferences':json.loads(prefs[0]) if prefs else None}

call('shell','wm','size','720x1595');call('shell','wm','density','280')
print(call('install','-r',str(root/'build/app/outputs/flutter-apk/app-debug.apk')),flush=True)
call('shell','am','force-stop',package)
call('shell','am','start','-n',package+'/.MainActivity')
time.sleep(3)
for _ in range(12):
    if any(e.get('content-desc')=='Navigationsmenü öffnen' for e in ui().iter('node')): break
    time.sleep(1)
screen('home-large.png')
navigate('Live Session')
initial=snapshot('initial')
if initial['live'].get('pausedAt'):
    tap('Fortsetzen')
rebuy_count=initial['live'].get('rebuys',0)
tap('Rebuy');screen('rebuy-prompt-large.png');call('shell','input','text','20');call('shell','input','keyevent','61');call('shell','input','text','35');call('shell','input','keyevent','4');tap('Speichern')
tap('Pause starten')
before=snapshot('before-process-death')
assert before['live']['rebuys']==rebuy_count+1 and before['live']['pausedAt']
screen('live-paused-large.png')
call('shell','am','force-stop',package)
call('shell','am','start','-n',package+'/.MainActivity')
time.sleep(3)
navigate('Live Session')
after=snapshot('after-process-death')
assert before==after, 'Persisted facts changed across process death'
assert any('Session pausiert' in (e.get('text','')+e.get('content-desc','')) for e in ui().iter('node'))
screen('live-recovered-large.png')
navigate('Bankroll');screen('bankroll-large.png')
tap('SESSION\n',partial=True);screen('sessions-large.png');tap('ÜBERBLICK\n',partial=True)
navigate('Settings');screen('settings-large.png')
call('shell','input','keyevent','4');time.sleep(.8)
navigate('Account');screen('account-large.png')
call('shell','input','keyevent','4');time.sleep(.8)
call('shell','wm','size','320x640');call('shell','wm','density','160');time.sleep(2)
navigate('Bankroll');screen('bankroll-compact.png')
tap('SESSION\n',partial=True);screen('sessions-compact.png');tap('ÜBERBLICK\n',partial=True)
navigate('Live Session');screen('live-recovered-compact.png')
summary={'serial':a.serial,'avd':'felt_ledger_dev','large':'720x1595 @280dpi','compact':'320x640 @160dpi','entryCount':after['entries'],'liveId':after['live']['id'],'rebuys':after['live']['rebuys'],'paused':True,'processDeathRecovery':'same entries, live record, events and preferences before/after'}
(out/'process-recovery.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2),flush=True)
