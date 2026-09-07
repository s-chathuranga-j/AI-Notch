#!/usr/bin/env python3
"""Package the locally built release into a drag-to-Applications disk image."""
from pathlib import Path
import hashlib
import platform
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
app = root / 'build/Build/Products/Release/AI Notch.app'
if not app.is_dir():
    raise SystemExit('Run make release before packaging.')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
output = root / 'build/releases'
output.mkdir(parents=True, exist_ok=True)
dmg = output / f'AI-Notch-{version}-macOS-{platform.machine()}.dmg'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
with tempfile.TemporaryDirectory(prefix='ainotch-package-') as directory:
    stage = Path(directory)
    subprocess.run(['ditto', str(app), str(stage / app.name)], check=True)
    (stage / 'Applications').symlink_to('/Applications')
    subprocess.run(['hdiutil', 'create', '-volname', 'AI Notch', '-srcfolder', str(stage),
                    '-ov', '-format', 'UDZO', str(dmg)], check=True)
subprocess.run(['hdiutil', 'verify', str(dmg)], check=True)
digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
dmg.with_suffix('.dmg.sha256').write_text(f'{digest}  {dmg.name}\n')
print(f'Installer: {dmg}')
