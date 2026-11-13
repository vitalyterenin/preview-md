from pathlib import Path
import json
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import licenses

class LicenseTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        for name in [*licenses.FILES,'release.json']:
            shutil.copyfile(licenses.ROOT/name,self.root/name)
        self.patcher=patch.object(licenses,'ROOT',self.root); self.patcher.start(); self.addCleanup(self.patcher.stop)
        self.app=self.root/'PreviewMD.app'
        metadata=self.app/'Contents/Frameworks/Sparkle.framework/Resources/Info.plist'
        metadata.parent.mkdir(parents=True)
        metadata.write_bytes(plistlib.dumps({'CFBundleShortVersionString':'2.10.1'}))
        self.upstream=self.root/'sparkle-license.txt'
        notices=(self.root/'THIRD_PARTY_NOTICES.md').read_text()
        self.upstream.write_text(notices.split('```text\n',1)[1].split('```',1)[0])

    def test_notices_survive_app_only_install_and_match_disk_image(self):
        licenses.install(self.app,self.upstream)
        image=self.root/'image'; image.mkdir()
        copy=image/self.app.name; shutil.copytree(self.app,copy)
        licenses.stage_distribution(copy,image)
        licenses.verify_distribution(image,self.app.name)
        installed=self.root/'installed'/self.app.name
        shutil.copytree(copy,installed); shutil.rmtree(image)
        licenses.verify_bundle(installed)
        (installed/'Contents/Resources/Licenses/NOTICE').unlink()
        with self.assertRaises(FileNotFoundError): licenses.verify_bundle(installed)

    def test_changed_or_missing_license_and_dependency_notices_fail(self):
        for name in licenses.FILES:
            path=self.root/name; original=path.read_bytes(); path.write_bytes(b'incomplete')
            try:
                with self.assertRaises(ValueError): licenses.source_files()
            finally: path.write_bytes(original)
        self.upstream.write_text('a different upstream license')
        with self.assertRaises(ValueError): licenses.install(self.app,self.upstream)

    def test_cmark_revision_and_complete_copying_are_required(self):
        path=self.root/'THIRD_PARTY_NOTICES.md'; original=path.read_text()
        for damaged in (original.replace(licenses.CMARK_REVISION, 'wrong-revision'),
                        original.replace('Copyright (c) 2014, John MacFarlane', 'Omitted copyright')):
            path.write_text(damaged)
            with self.assertRaises(ValueError): licenses.source_files()
        path.write_text(original)
        licenses.source_files()

    def test_yaml_and_bundled_libyaml_notices_are_complete(self):
        path=self.root/'THIRD_PARTY_NOTICES.md'; original=path.read_text()
        for marker in ('## Yams 6.2.2', 'Copyright (c) 2016 JP Simard.', 'Copyright (c) 2017-2020 Ingy döt Net'):
            path.write_text(original.replace(marker, 'omitted'))
            with self.assertRaises(ValueError): licenses.source_files()
        path.write_text(original)
        licenses.source_files()

    def test_wrong_embedded_sparkle_version_and_unapproved_license_fail(self):
        licenses.install(self.app,self.upstream)
        metadata=self.app/'Contents/Frameworks/Sparkle.framework/Resources/Info.plist'
        metadata.write_bytes(plistlib.dumps({'CFBundleShortVersionString':'1.0'}))
        with self.assertRaises(ValueError): licenses.verify_bundle(self.app)
        data=json.loads((self.root/'release.json').read_text()); data['license']='MIT'
        (self.root/'release.json').write_text(json.dumps(data))
        with self.assertRaises(ValueError): licenses.source_files()

if __name__=='__main__': unittest.main()
