#!/usr/bin/env python3
"""Verify emitted metadata, binaries and real Sparkle preferences in an isolated app."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import uuid

ROOT=Path(__file__).resolve().parent.parent
app=Path(sys.argv[1]).resolve()
config=json.loads((ROOT/'release.json').read_text())
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
expected={
 'CFBundleIdentifier':config['bundleID'], 'CFBundleVersion':config['build'],
 'CFBundleShortVersionString':config['version'], 'SUFeedURL':config['feedURL'],
 'SUPublicEDKey':config['publicEDKey'], 'SUEnableAutomaticChecks':True,
 'SUAutomaticallyUpdate':True, 'SUScheduledCheckInterval':14400,
 'SUEnableSystemProfiling':False, 'SURequireSignedFeed':True,
 'SUVerifyUpdateBeforeExtraction':True, 'SUSignedFeedFailureExpirationInterval':0,
}
for key,value in expected.items():
 if info.get(key)!=value: raise SystemExit(f'Unexpected {key}: {info.get(key)}')
assert 'SUAllowsAutomaticUpdates' not in info
extension=app/'Contents/PlugIns/PreviewMDQuickLook.appex'
ext_info=plistlib.loads((extension/'Contents/Info.plist').read_bytes())
assert ext_info['CFBundleVersion']==config['build']
assert ext_info['CFBundleIdentifier']==config['bundleID']+'.quick-look'
sparkle=app/'Contents/Frameworks/Sparkle.framework/Versions/B'
for binary in [app/'Contents/MacOS/PreviewMD', extension/'Contents/MacOS/PreviewMDQuickLook', sparkle/'Sparkle',sparkle/'Autoupdate',sparkle/'Updater.app/Contents/MacOS/Updater']:
 assert subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()=='arm64'
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
subprocess.run([sys.executable,str(ROOT/'scripts/licenses.py'),'verify','--app',str(app)],check=True)
# Sparkle stores preferences in its host bundle domain. A unique disposable bundle
# tests actual persistence without changing the installed app's preference domain.
domain=config['bundleID']+'.settings-test.'+uuid.uuid4().hex
try:
 with tempfile.TemporaryDirectory(prefix='preview-md-settings-') as directory:
  copy=Path(directory)/'PreviewMD.app'
  subprocess.run(['ditto',str(app),str(copy)],check=True)
  test_info=dict(info,CFBundleIdentifier=domain)
  (copy/'Contents/Info.plist').write_bytes(plistlib.dumps(test_info))
  subprocess.run(['codesign','--force','--sign','-','--timestamp=none',str(copy)],check=True)
  for stage in ['fresh','relaunch','resume']:
   subprocess.run([str(copy/'Contents/MacOS/PreviewMD'),'--updates-smoke',stage],check=True,timeout=30)
finally:
 subprocess.run(['defaults','delete',domain],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
print('Built metadata, arm64 components, signatures, notices and isolated updater preferences passed.')
