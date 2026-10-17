#!/usr/bin/env python3
"""Save legacy debug-trial orchard preferences through Android Debug Bridge."""
import argparse
import datetime
import json
import os
import subprocess
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('output', help='New private JSON backup file (must not exist)')
args = parser.parse_args()
root = 'orchard-atlas-phone-trial-v1'
uid = 'local-phone-trial'
def included(key):
    return key in [root, 'orchard-atlas-trial-orchards', 'trial-selected:'+uid, 'task-sort:'+uid] or key.startswith(root+':orchard:') or key.startswith('map-default:'+uid+':')
raw = subprocess.check_output(['adb', 'exec-out', 'run-as', 'com.orchardatlas.orchard_atlas.trial', 'cat', 'shared_prefs/FlutterSharedPreferences.xml'])
records = {}
for entry in ET.fromstring(raw):
    key = entry.attrib.get('name', '').removeprefix('flutter.')
    if entry.tag == 'string' and included(key):
        records[key] = entry.text or ''
if root not in records:
    raise SystemExit('No trial orchard snapshot found. Do not uninstall the app.')
# Detect incomplete/corrupt source snapshots before writing the migration backup.
for key,value in records.items():
    if key.startswith(root) or key == 'orchard-atlas-trial-orchards':
        json.loads(value)
archive = {'format':'OrchardAtlasBackup','version':1,'createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'records':records}
fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as output:
    json.dump(archive, output, ensure_ascii=False)
print('Saved a private OrchardAtlas backup. Copy it to Drive, verify it is available, and keep another copy before uninstalling.')
