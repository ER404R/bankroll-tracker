#!/usr/bin/env python3
"""Read-only UI review of the normal APK on this project's emulator."""
import json,re,sqlite3,subprocess,time
from pathlib import Path
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parent.parent
out=root/'docs/validation'
adb='/home/erik/Android/Sdk/platform-tools/adb'
serial='emulator-5580';package='de.feltledger.felt_ledger'
def call(*args):return subprocess.check_output([adb,'-s',serial,*args])
assert call('shell','getprop','ro.kernel.qemu').strip()==b'1'
assert call('emu','avd','name').splitlines()[0]==b'felt_ledger_dev'
def ui():
    for _ in range(5):
        if b'dumped' in call('shell','uiautomator','dump','/sdcard/felt-review-ui.xml'):
            return ET.fromstring(call('exec-out','cat','/sdcard/felt-review-ui.xml'))
    raise RuntimeError('No accessibility tree')
def tap(label,partial=False):
    matches=[e for e in ui().iter('node') if any((label in e.get(k,'') if partial else label==e.get(k,'')) for k in ['text','content-desc'])]
    if not matches:raise RuntimeError('Not visible: '+label)
    x1,y1,x2,y2=map(int,re.findall(r'\d+',matches[-1].get('bounds')))
    call('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));time.sleep(.5)
def navigate(label):tap('Navigationsmenü öffnen');tap(label)
def tab(label):
    for _ in range(3):
        try:tap(label+'\n',True);return
        except RuntimeError:call('shell','input','swipe','650','180','150','180','300')
    raise RuntimeError('Missing tab '+label)
def screen(name): (out/name).write_bytes(call('exec-out','screencap','-p'))
def records():
    path=Path('/tmp/felt-report-review.db');path.write_bytes(call('exec-out','run-as',package,'cat','databases/felt_ledger.db'))
    with sqlite3.connect(path) as db:return db.execute('SELECT id,payload FROM entries ORDER BY id').fetchall()
call('shell','am','force-stop',package)
before=records()
print(call('install','-r',str(root/'artifacts/felt-ledger-0.1.3-debug.apk')).decode(),flush=True)
call('shell','wm','size','720x1595');call('shell','wm','density','280')
call('shell','am','start','-n',package+'/.MainActivity')
for _ in range(10):
    if any(e.get('content-desc')=='Navigationsmenü öffnen' for e in ui().iter('node')):break
    time.sleep(1)
screen('reports-home-large.png')
assert all('Bearbeiten' not in e.get('content-desc','') and 'Löschen' not in e.get('content-desc','') for e in ui().iter('node'))
navigate('Bankroll');screen('reports-overview-large.png')
tab('DIAGRAMME');screen('reports-months-large.png')
tap('Letzte 12 Monate',True);tap('Letzte 3 Monate');screen('reports-quarter-large.png')
call('shell','input','swipe','360','1350','360','500','400');time.sleep(.5);screen('reports-years-large.png')
tab('TREND');screen('reports-trend-large.png')
tap('CASH GAME');screen('reports-trend-cash-large.png')
tap('TURNIER');screen('reports-trend-tournament-large.png')
tap('GESAMT');tap('FÜLLUNG');screen('reports-trend-fill-large.png')
call('shell','wm','size','320x640');call('shell','wm','density','160');time.sleep(1)
screen('reports-trend-compact.png')
navigate('Home');screen('reports-home-compact.png')
call('shell','am','force-stop',package)
assert records()==before,'Existing financial records changed during visual review'
call('shell','wm','size','720x1595');call('shell','wm','density','280')
call('shell','am','start','-n',package+'/.MainActivity')
print(json.dumps({'emulator':serial,'entriesPreserved':len(before),'large':'720x1595 @280dpi','compact':'320x640 @160dpi','leftOpen':'Home'},indent=2),flush=True)
