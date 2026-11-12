import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import release

class Response:
    def __init__(self,body): self.body=body
    def __enter__(self): return self
    def __exit__(self,*args): pass
    def read(self): return self.body

class PreviousFeedTests(unittest.TestCase):
    def test_previous_feed_preserves_exact_hash_and_source(self):
        body=b'<rss><channel/></rss>'
        with tempfile.TemporaryDirectory() as directory, patch.object(release.urllib.request,'urlopen',return_value=Response(body)) as read:
            path=Path(directory)/'previous.xml'
            release.previous(path)
            state=json.loads(path.with_suffix('.state.json').read_text())
            self.assertEqual(path.read_bytes(),body)
            self.assertEqual(state['previousFeedSHA256'],hashlib.sha256(body).hexdigest())
            self.assertEqual(state['sourceURL'],release.config()['feedURL'])
            read.assert_called_once()

    def test_first_build_can_bootstrap_only_missing_feed_and_missing_release(self):
        data=release.config(); data['build']=data['firstReleaseBuild']
        mock=patch.object(release, 'config', return_value=data)
        mock.start(); self.addCleanup(mock.stop)
        missing=HTTPError('url',404,'missing',{},None)
        with tempfile.TemporaryDirectory() as directory, patch.object(release.urllib.request,'urlopen',side_effect=[missing,missing]) as read:
            path=Path(directory)/'previous.xml'
            release.previous(path)
            self.assertEqual(read.call_count,2)
            self.assertFalse(path.exists())
        with tempfile.TemporaryDirectory() as directory, patch.object(release.urllib.request,'urlopen',side_effect=[missing,Response(b'{}')]), self.assertRaisesRegex(ValueError,'published release'):
            release.previous(Path(directory)/'previous.xml')

    def test_later_missing_feed_does_not_reset_history(self):
        data=release.config(); data['build']=str(int(data['firstReleaseBuild'])+1)
        with tempfile.TemporaryDirectory() as directory, patch.object(release,'config',return_value=data), patch.object(release.urllib.request,'urlopen',side_effect=HTTPError('url',404,'missing',{},None)) as read, self.assertRaisesRegex(ValueError,'established'):
            release.previous(Path(directory)/'previous.xml')
        read.assert_called_once()

    def test_network_and_access_errors_do_not_bootstrap(self):
        for error in [HTTPError('url',503,'unavailable',{},None),URLError('offline'),HTTPError('url',403,'forbidden',{},None)]:
            with self.subTest(error=error), tempfile.TemporaryDirectory() as directory, patch.object(release.urllib.request,'urlopen',side_effect=error) as read, self.assertRaises(type(error)):
                release.previous(Path(directory)/'previous.xml')
            read.assert_called_once()

    def test_metadata_preserves_document_types_and_secure_updater_defaults(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'Info.plist'; release.write_plist(path)
            values=release.plistlib.loads(path.read_bytes())
            self.assertTrue(values['CFBundleDocumentTypes'])
            self.assertEqual(values['CFBundleIdentifier'],release.ACCOUNT)
            self.assertTrue(values['SUEnableAutomaticChecks'])
            self.assertTrue(values['SUAutomaticallyUpdate'])
            self.assertEqual(values['SUScheduledCheckInterval'],14400)
            self.assertTrue(values['SURequireSignedFeed'])
            self.assertEqual(values['SUSignedFeedFailureExpirationInterval'],0)
            self.assertNotIn('SUAllowsAutomaticUpdates',values)

    def test_urls_cannot_publish_into_another_repository(self):
        for key in ['feedURL','downloadURL']:
            data=release.config(); data[key]='https://example.invalid/update'
            with patch.object(release.json,'loads',return_value=data), self.assertRaises(ValueError): release.config()

if __name__=='__main__': unittest.main()
