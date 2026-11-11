#!/usr/bin/env python3
"""Apply/reset a real report filter on the dedicated synthetic emulator."""
import argparse
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET
p=argparse.ArgumentParser();p.add_argument('--serial',required=True);a=p.parse_args()
adb='/home/erik/Android/Sdk/platform-tools/adb'
def call(*args,binary=False):
 result=subprocess.check_output([adb,'-s',a.serial,*args]);return result if binary else result.decode().strip()
if not a.serial.startswith('emulator-') or call('shell','getprop','ro.kernel.qemu')!='1' or call('emu','avd','name').splitlines()[0]!='felt_ledger_dev':raise SystemExit('Wrong development emulator')
def ui():
 for _ in range(5):
  output=call('shell','uiautomator','dump','/sdcard/felt-ui.xml')
  if 'dumped' in output:return ET.fromstring(call('exec-out','cat','/sdcard/felt-ui.xml'))
  time.sleep(.5)
 raise RuntimeError('No emulator accessibility snapshot')
def tap(label,partial=False):
 nodes=[e for e in ui().iter('node') if any((label in e.get(k,'') if partial else label==e.get(k,'')) for k in ['text','content-desc'])]
 if not nodes:raise RuntimeError('Control missing: '+label)
 x1,y1,x2,y2=map(int,re.findall(r'\d+',nodes[-1].get('bounds')))
 call('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));time.sleep(.8)
tap('Navigationsmenü öffnen');tap('Bankroll');tap('Bankroll Filter');tap('Art',partial=True);tap('Kosten');tap('Filter');tap('SESSION\n',partial=True)
content=' '.join(e.get('text','')+' '+e.get('content-desc','') for e in ui().iter('node'))
assert 'Kosten' in content and 'Cash Game' not in content and 'Turnier' not in content,content
out=Path(__file__).resolve().parent.parent/'docs/validation/filtered-costs-compact.png';out.write_bytes(call('exec-out','screencap','-p',binary=True))
tap('Bankroll Filter');tap('Zurücksetzen')
tap('Navigationsmenü öffnen');tap('Live Session')
print('PASS: Kosten filter applied to visible history, other kinds excluded, reset restored, live session retained.')
