#!/usr/bin/env python3
"""Run synthetic integration checks only on the dedicated Felt Ledger emulator."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--target', choices=['app_test','report_review_test'], default='app_test')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
adb = '/home/erik/Android/Sdk/platform-tools/adb'
flutter = '/home/erik/.local/share/flutter/bin/flutter'
dart = '/home/erik/.local/share/flutter/bin/dart'

def device(*command, **kwargs):
    return subprocess.check_output([adb, '-s', args.serial, *command], text=True, **kwargs).strip()

if not args.serial.startswith('emulator-'):
    raise SystemExit('Only an explicitly named emulator is permitted.')
if device('shell', 'getprop', 'ro.kernel.qemu') != '1':
    raise SystemExit('Target is not a verified emulator.')
if device('emu', 'avd', 'name').splitlines()[0] != 'felt_ledger_dev':
    raise SystemExit('Use only the dedicated felt_ledger_dev AVD: tests reset its synthetic data.')

env = {**os.environ, 'JAVA_HOME': '/home/erik/.local/share/android-studio/jbr', 'ANDROID_HOME': '/home/erik/Android/Sdk'}
subprocess.run([flutter, '--no-version-check', 'build', 'apk', '--debug', '--target=integration_test/' + args.target + '.dart'], cwd=root, env=env, check=True)
print(device('install', '-t', '-r', str(root / 'build/app/outputs/flutter-apk/app-debug.apk')), flush=True)
device('shell', 'pm', 'grant', 'de.feltledger.felt_ledger', 'android.permission.POST_NOTIFICATIONS')
device('shell', 'am', 'force-stop', 'de.feltledger.felt_ledger')
device('logcat', '-c')
device('shell', 'am', 'start', '-n', 'de.feltledger.felt_ledger/.MainActivity')
match = None
for _ in range(30):
    logs = device('logcat', '-d', '-s', 'flutter')
    match = re.search(r'The Dart VM service is listening on http://127\.0\.0\.1:(\d+)/(\S+)', logs)
    if match:
        break
    time.sleep(1)
if not match:
    raise SystemExit('The emulator did not expose its Flutter VM service.')
device('forward', 'tcp:8678', 'tcp:' + match[1])
env['VM_SERVICE_URL'] = 'http://127.0.0.1:8678/' + match[2]
# Some emulator VM startups briefly reset the forwarded WebSocket. Retry only
# connection failures, never a failed app assertion.
for attempt in range(3):
    time.sleep(2)
    device('forward', 'tcp:8678', 'tcp:' + match[1])
    result = subprocess.run([dart, 'test_driver/integration_test.dart'], cwd=root, env=env, capture_output=True, text=True, timeout=180)
    output = result.stdout + result.stderr
    print(output, flush=True)
    if result.returncode == 0:
        break
    if 'Service connection disposed' not in output and 'SocketException' not in output:
        raise SystemExit(result.returncode)
else:
    raise SystemExit('Emulator VM connection failed after three attempts.')
