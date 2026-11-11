"""Reject wrong architectures and private reference files before publishing."""
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as apk:
    names = apk.namelist()
    abis = {name.split('/')[1] for name in names if name.startswith('lib/') and name.endswith('.so')}
    if abis != {'arm64-v8a'}:
        raise SystemExit(f'Unexpected APK architectures: {sorted(abis)}')
    forbidden = [name for name in names if any(part in name.lower() for part in (
        'docs/reference/', 'docs/validation/', '.jks', '.keystore', 'spec.md', 'agents.md',
    ))]
    if forbidden:
        raise SystemExit(f'Private files in APK: {forbidden}')
print('ARM64 architecture and private-file checks passed.')
