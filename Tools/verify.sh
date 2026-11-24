#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p .build
swiftc Sources/InstallerCatalog.swift Sources/InstallerOptions.swift \
  Sources/InstallerDownloadManager.swift Sources/IPSWCatalog.swift \
  Sources/MacCompatibility.swift Sources/SystemOverview.swift \
  Sources/WebCatalog.swift Sources/AppUpdates.swift \
  Tools/FixtureProtocol.swift Tools/Verify.swift \
  -parse-as-library -framework AppKit -framework CryptoKit -o .build/verify
.build/verify
python3 - <<'PY'
from pathlib import Path
expected = {'27', '26', '15', '14', '13', '12', '11'} | {f'10.{i}' for i in range(16)}
actual = {p.stem for p in Path('Resources/Wallpapers').glob('*.jpg')}
assert actual == expected, f'Missing wallpapers: {expected - actual}'
print('PASS: Все 23 системных обоев встроены')
PY
