import hashlib
import json
import os
import plistlib
import sys
from pathlib import Path

archive = Path(sys.argv[1])
info = plistlib.loads(Path(sys.argv[2]).read_bytes())
repository = os.environ['GITHUB_REPOSITORY']
tag = os.environ['GITHUB_REF_NAME']
if info['CFBundleIdentifier'] != 'com.laberthouman.macdownup':
    raise ValueError('Unexpected app bundle')
manifest = {
    'schemaVersion': 1,
    'version': info['CFBundleShortVersionString'],
    'build': int(info['CFBundleVersion']),
    'minimumSystemVersion': info['LSMinimumSystemVersion'],
    'releaseNotes': 'Новая сборка MacDownUp. Список изменений доступен в GitHub Releases.',
    'archiveURL': f'https://github.com/{repository}/releases/download/{tag}/MacDownUp.zip',
    'sha256': hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest(),
    'fileSize': archive.stat().st_size,
}
Path('app-update.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
