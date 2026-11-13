import importlib.util
import io
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('yaml_tools', ROOT / 'scripts/yaml-tools.py')
yaml_tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(yaml_tools)


class PublicationEventTests(unittest.TestCase):
    def test_only_tag_push_can_enter_publication_job(self):
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        job = workflow.split('\n  publish:\n', 1)[1]
        condition = next(line.strip()[4:] for line in job.splitlines()
                         if line.startswith('    if: '))
        # Evaluate the actual simple GitHub condition against event contexts;
        # no workflow, network request, signing or publication is executed.
        expression = condition.replace('&&', 'and').replace('||', 'or')
        for event, ref_type, expected in [
            ('pull_request', 'branch', False),
            ('workflow_dispatch', 'branch', False),
            ('workflow_dispatch', 'tag', False),
            ('push', 'branch', False),
            ('push', 'tag', True),
        ]:
            with self.subTest(event=event, ref_type=ref_type):
                context = SimpleNamespace(event_name=event, ref_type=ref_type)
                self.assertEqual(eval(expression, {'__builtins__': {}}, {'github': context}), expected)


class YamsCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / 'cache'
        self.cache.mkdir()
        self.output = self.root / 'swiftpm-output'
        self.output.mkdir()
        (self.output / 'libYams.a').write_bytes(b'library')
        module = self.output / 'Yams.swiftmodule'
        module.mkdir()
        (module / 'arm64-apple-macos.swiftmodule').write_bytes(b'module')
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w:gz') as archive:
            for name, content in {
                'LICENSE': b'fixture license',
                'Sources/CYaml/include/module.modulemap': b'module CYaml {}',
                'Sources/CYaml/include/yaml.h': b'header',
                'Sources/CYaml/include/CYaml.h': b'header',
            }.items():
                entry = tarfile.TarInfo('Yams-' + yaml_tools.VERSION + '/' + name)
                entry.size = len(content)
                archive.addfile(entry, io.BytesIO(content))
        archive_bytes = data.getvalue()
        (self.cache / 'source.tar.gz').write_bytes(archive_bytes)
        self.identity = {
            'swift': '/fixture/toolchain/bin/swift',
            'version': 'Swift fixture 1',
            'sdk': '/fixture/sdk',
            'sdk_version': '1.0',
        }
        self.builds = []
        patches = [
            patch.dict(yaml_tools.os.environ, {'PREVIEWMD_YAML_TOOLS_DIR': str(self.cache)}),
            patch.object(yaml_tools, 'ARCHIVE_SHA256', yaml_tools.hashlib.sha256(archive_bytes).hexdigest()),
            patch.object(yaml_tools.licenses, 'YAMS_LICENSE_SHA256', yaml_tools.hashlib.sha256(b'fixture license').hexdigest()),
            patch.object(yaml_tools.licenses, 'source_files'),
            patch.object(yaml_tools.shutil, 'which', side_effect=lambda _: self.identity['swift']),
            patch.object(yaml_tools.subprocess, 'check_output', side_effect=self.command_output),
            patch.object(yaml_tools.subprocess, 'run', side_effect=lambda args, **kwargs: self.builds.append(args)),
            patch.object(yaml_tools.urllib.request, 'urlopen', side_effect=AssertionError('network forbidden')),
        ]
        for mock in patches:
            mock.start()
            self.addCleanup(mock.stop)

    def command_output(self, args, **kwargs):
        if '--show-bin-path' in args:
            return str(self.output)
        if '--version' in args:
            return self.identity['version']
        if '--show-sdk-path' in args:
            return self.identity['sdk']
        if '--show-sdk-version' in args:
            return self.identity['sdk_version']
        self.fail('Unexpected command: ' + repr(args))

    def test_complete_cache_reuses_build_but_toolchain_changes_rebuild(self):
        yaml_tools.build()
        self.assertEqual(len(self.builds), 1)
        yaml_tools.build()
        self.assertEqual(len(self.builds), 1)
        for field in self.identity:
            with self.subTest(changed=field):
                before = len(self.builds)
                self.identity[field] += '-changed'
                yaml_tools.build()
                self.assertEqual(len(self.builds), before + 1)
                command = self.builds[-1]
                self.assertEqual(command[0], self.identity['swift'])
                self.assertEqual(command[command.index('--sdk') + 1], self.identity['sdk'])
        before = len(self.builds)
        with patch.object(yaml_tools, 'TARGET', 'arm64-apple-macosx14.0'):
            yaml_tools.build()
        self.assertEqual(len(self.builds), before + 1)
        self.assertIn('arm64-apple-macosx14.0', self.builds[-1])

    def test_missing_module_or_c_headers_cannot_use_warm_cache(self):
        yaml_tools.build()
        for relative in ['modules/Yams.swiftmodule',
                         'modules/Yams.swiftmodule/arm64-apple-macos.swiftmodule', 'include/module.modulemap',
                         'include/CYaml.h', 'include/yaml.h', 'libYams.a']:
            with self.subTest(missing=relative):
                target = self.cache / relative
                if target.is_dir():
                    shutil.rmtree(target)
                else:
                    target.unlink()
                before = len(self.builds)
                yaml_tools.build()
                self.assertEqual(len(self.builds), before + 1)
                self.assertTrue(target.exists())

    def test_failed_rebuild_does_not_mark_new_toolchain_as_cached(self):
        yaml_tools.build()
        stamp = (self.cache / 'build-stamp').read_bytes()
        self.identity['version'] += '-changed'
        with patch.object(yaml_tools.subprocess, 'run', side_effect=RuntimeError('compiler failed')):
            with self.assertRaisesRegex(RuntimeError, 'compiler failed'):
                yaml_tools.build()
        self.assertEqual((self.cache / 'build-stamp').read_bytes(), stamp)
        before = len(self.builds)
        yaml_tools.build()
        self.assertEqual(len(self.builds), before + 1)


if __name__ == '__main__':
    unittest.main()
