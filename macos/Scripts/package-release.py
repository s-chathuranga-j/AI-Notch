#!/usr/bin/env python3
"""Package the locally built release into a drag-to-Applications disk image."""
from pathlib import Path
import hashlib
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
app = root / 'build/Build/Products/Release/AI Notch.app'
if not app.is_dir():
    raise SystemExit('Run make release before packaging.')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
architectures = subprocess.check_output(
    ['lipo', '-archs', str(app / 'Contents/MacOS/AI Notch')], text=True).split()
if set(architectures) != {'arm64', 'x86_64'}:
    raise SystemExit('Run make release to build a universal update for Apple Silicon and Intel.')
tools = root / 'build/SourcePackages/artifacts/sparkle/Sparkle/bin'
public_key = subprocess.check_output(
    [str(tools / 'generate_keys'), '--account', 'com.fourforge.ainotch', '-p'], text=True).strip()
if public_key != info.get('SUPublicEDKey'):
    raise SystemExit('The Sparkle signing key does not match this app. Restore the original signing key.')
output = root / 'build/releases'
output.mkdir(parents=True, exist_ok=True)
dmg = output / f'AI-Notch-{version}-macOS-universal.dmg'
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
feed = output / 'appcast.xml'
download_prefix = f'https://github.com/s-chathuranga-j/AI-Notch/releases/download/macos-v{version}/'
with tempfile.TemporaryDirectory(prefix='ainotch-appcast-') as directory:
    shutil.copy2(dmg, Path(directory) / dmg.name)
    generated_feed = Path(directory) / 'appcast.xml'
    subprocess.run([str(tools / 'generate_appcast'), '--account', 'com.fourforge.ainotch',
                    '--download-url-prefix', download_prefix, '--maximum-deltas', '0',
                    '-o', str(generated_feed), directory], check=True)
    enclosure = ET.parse(generated_feed).find('./channel/item/enclosure')
    if (enclosure is None or enclosure.get('url') != download_prefix + dmg.name
            or not enclosure.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature')
            or enclosure.get('length') != str(dmg.stat().st_size)):
        raise SystemExit('Generated update feed failed validation; do not publish it.')
    shutil.copy2(generated_feed, feed)
print(f'Installer: {dmg}')
print(f'Signed update feed: {feed}')
