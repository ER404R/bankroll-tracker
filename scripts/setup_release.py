"""Create a permanent private key and upload secrets; never print secret values."""
import base64
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
REPO = 'ER404R/bankroll-tracker'

def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

run('gh', 'repo', 'view', REPO, '--json', 'nameWithOwner')
private = ROOT / '.release-private'
private.mkdir(mode=0o700, exist_ok=True)
private.chmod(0o700)
key = private / 'release.jks'
credentials = private / 'credentials.json'
if key.exists() != credentials.exists():
    raise SystemExit('Incomplete signing backup. Restore the matching key/credentials; do not replace the key.')
if not key.exists():
    values = {'ANDROID_STORE_PASSWORD': secrets.token_urlsafe(40),
              'ANDROID_KEY_ALIAS': 'bankroll-tracker'}
    values['ANDROID_KEY_PASSWORD'] = values['ANDROID_STORE_PASSWORD']
    keytool = shutil.which('keytool') or '/home/erik/.local/share/android-studio/jbr/bin/keytool'
    env = dict(os.environ, **values)
    run(keytool, '-genkeypair', '-keystore', str(key), '-storetype', 'JKS',
        '-storepass:env', 'ANDROID_STORE_PASSWORD', '-keypass:env', 'ANDROID_KEY_PASSWORD',
        '-alias', values['ANDROID_KEY_ALIAS'], '-keyalg', 'RSA', '-keysize', '4096',
        '-validity', '10000', '-dname', 'CN=Bankroll Tracker', env=env)
    key.chmod(0o600)
    with credentials.open('x') as file:
        credentials.chmod(0o600)
        json.dump(values, file)
values = json.loads(credentials.read_text())
values['KEY_JKS'] = base64.b64encode(key.read_bytes()).decode('ascii')
for name, value in values.items():
    run('gh', 'secret', 'set', name, '--repo', REPO, input=value, text=True)
print('Signing secrets uploaded. Back up .release-private securely; keep it out of Git.')
