#!/usr/bin/env python3
"""Create one private trial signer outside the repository. Never log its key."""
import argparse
import base64
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--directory', required=True, type=Path)
args = parser.parse_args()
directory = args.directory.expanduser().resolve()
repo = Path(__file__).resolve().parents[1]
if directory == repo or repo in directory.parents:
    parser.error('Use a private directory outside the repository')
os.umask(0o077)
directory.mkdir(parents=True, exist_ok=True, mode=0o700)
key = directory / 'orchardatlas-trial.keystore'
secret = directory / 'orchardatlas.signing-secret.txt'
if key.exists() or secret.exists():
    parser.error('Signing files already exist; keep using the original key')
subprocess.run(['keytool', '-genkeypair', '-keystore', str(key), '-storepass', 'android',
                '-keypass', 'android', '-alias', 'androiddebugkey', '-keyalg', 'RSA',
                '-keysize', '2048', '-validity', '10000', '-dname', 'CN=OrchardAtlas Trial'], check=True)
key.chmod(0o600)
fd = os.open(secret, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as output:
    output.write(base64.b64encode(key.read_bytes()).decode())
print('Private signer created. Keep both files safe and do not commit or share them.')
print('Paste the contents of ' + str(secret) + ' into repository Actions secret ANDROID_TRIAL_DEBUG_KEYSTORE_BASE64.')
