#!/usr/bin/env python3
"""Publish only APKs signed by the restored trial key, with verified identity."""
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess

PACKAGE = 'com.orchardatlas.orchard_atlas.trial'


def validate_identity(report, badging, expected_digest, version_name, version_code):
    # apksigner versions use either "Signer #1" or "V2 Signer" prefixes.
    digests = re.findall(r'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})(?![0-9a-fA-F])', report)
    if not digests or {d.lower() for d in digests} != {expected_digest.lower()}:
        raise ValueError('Actual APK certificate does not match the restored permanent signing key. APK publication refused.')
    match = re.search(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging, re.MULTILINE)
    if not match:
        raise ValueError('Cannot read APK package identity. APK publication refused.')
    package, code, name = match.groups()
    if (package, code, name) != (PACKAGE, str(version_code), version_name):
        raise ValueError('Actual APK package/version does not match the requested trial build. APK publication refused.')
    return {'package': package, 'versionCode': int(code), 'versionName': name,
            'certificateSha256': digests[0].lower()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=pathlib.Path, required=True)
    parser.add_argument('--keystore', type=pathlib.Path, required=True)
    parser.add_argument('--build-tools', type=pathlib.Path, required=True)
    parser.add_argument('--version-name', required=True)
    parser.add_argument('--version-code', type=int, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    candidates = [p for p in args.build_tools.glob('*/apksigner')
                  if (p.parent / 'aapt').is_file()]
    if not candidates:
        raise SystemExit('Android apksigner and aapt are required to verify the APK.')
    signer = max(candidates, key=lambda p: tuple(int(x) for x in re.findall(r'\d+', p.parent.name)))
    # This verifies the finished artifact, not merely the keystore or build input.
    report = subprocess.check_output([str(signer), 'verify', '--verbose', '--print-certs', str(args.apk)], text=True)
    badging = subprocess.check_output([str(signer.parent / 'aapt'), 'dump', 'badging', str(args.apk)], text=True)
    certificate = subprocess.check_output(['keytool', '-exportcert', '-keystore', str(args.keystore),
                                           '-storepass', 'android', '-alias', 'androiddebugkey'])
    try:
        identity = validate_identity(report, badging, hashlib.sha256(certificate).hexdigest(),
                                     args.version_name, args.version_code)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    sha1 = re.search(r'certificate SHA-1 digest:\s*([0-9a-fA-F]{40})(?![0-9a-fA-F])', report)
    if not sha1:
        raise SystemExit('Cannot read the actual APK certificate SHA-1 digest.')
    identity['certificateSha1'] = sha1.group(1).lower()
    identity['apkSha256'] = hashlib.sha256(args.apk.read_bytes()).hexdigest()
    args.output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.apk, args.output / 'OrchardAtlas-trial.apk')
    (args.output / 'VERSION.txt').write_text(f"Version {identity['versionName']} ({identity['versionCode']})\n")
    def colon_hex(value):
        return ':'.join(value[i:i+2].upper() for i in range(0, len(value), 2))
    (args.output / 'SIGNING_CERTIFICATE.txt').write_text(
        'Verified from the actual APK:\nSHA1: ' + colon_hex(identity['certificateSha1']) +
        '\nSHA256: ' + colon_hex(identity['certificateSha256']) + '\n')
    (args.output / 'SHA256SUMS.txt').write_text(identity['apkSha256'] + '  OrchardAtlas-trial.apk\n')
    (args.output / 'APK_IDENTITY.json').write_text(json.dumps(identity, indent=2) + '\n')
    (args.output / 'UPDATING.txt').write_text(
        'Keep the installed app until its orchard data is safely backed up.\n'
        'Trials through 0.38.0 could use temporary debug signing keys despite the bundled certificate file.\n'
        'Android cannot update those installations with a different signer.\n'
        'Back up through the app or scripts/backup-installed-trial.py before a one-time reinstall.\n'
        'Subsequent APKs with this same verified signer and a higher versionCode update in place.\n'
        'Full instructions: https://github.com/akjeffrey/OrchardAtlas/blob/main/docs/drive-backup-and-updates.md\n')
    print('Verified APK identity: ' + json.dumps(identity, sort_keys=True))


if __name__ == '__main__':
    main()
