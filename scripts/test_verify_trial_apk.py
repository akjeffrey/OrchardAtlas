"""Regression checks for the actual-APK signing mismatch found in phone trials."""
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('verify_trial', pathlib.Path(__file__).with_name('verify-trial-apk.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

PERMANENT = 'f197f6e853747a0c64d1871f47a295110c007a7e6844cf25b44b660529b65c5c'
TEMPORARY = '51f3cf7e40993cc78af2eef9dc8d6080e4f1cf77b3b8a4562c1cc9f0209f847b'
BADGING = "package: name='com.orchardatlas.orchard_atlas.trial' versionCode='39' versionName='0.39.0' platformBuildVersionCode='36'\n"


class VerifyIdentity(unittest.TestCase):
    def check_identity(self, digest=PERMANENT, badging=BADGING, prefix='V2 Signer'):
        return module.validate_identity(f'{prefix}: certificate SHA-256 digest: {digest}\n', badging, PERMANENT, '0.39.0', 39)

    def test_accepts_current_and_older_apksigner_formats(self):
        for prefix in ['V2 Signer', 'Signer #1']:
            with self.subTest(prefix=prefix):
                self.assertEqual(self.check_identity(prefix=prefix)['certificateSha256'], PERMANENT)

    def test_refuses_the_observed_temporary_debug_certificate(self):
        with self.assertRaisesRegex(ValueError, 'certificate does not match'):
            self.check_identity(digest=TEMPORARY)

    def test_refuses_missing_or_multiple_signers(self):
        for report in ['', f'V2 Signer: certificate SHA-256 digest: {PERMANENT}\nSigner #2: certificate SHA-256 digest: {TEMPORARY}']:
            with self.subTest(report=report), self.assertRaises(ValueError):
                module.validate_identity(report, BADGING, PERMANENT, '0.39.0', 39)

    def test_refuses_wrong_package_or_build_identity(self):
        for badging in ['', BADGING.replace('.trial', ''), BADGING.replace("versionCode='39'", "versionCode='38'"), BADGING.replace('0.39.0', '0.38.0')]:
            with self.subTest(badging=badging), self.assertRaises(ValueError):
                self.check_identity(badging=badging)


if __name__ == '__main__':
    unittest.main()
