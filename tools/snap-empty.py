#!/usr/bin/env python3
"""Capture only the isolated preview's windows, using the runner's capture permission."""
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parent.parent
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / '.impeccable/review' / f'empty-{time.time_ns()}'
output.mkdir(parents=True, exist_ok=False)
languages = [os.environ['APP_LANGUAGE']] if os.environ.get('APP_LANGUAGE') else ['en', 'zh-Hans']

with tempfile.TemporaryDirectory(prefix='syllapace-window-review-', dir='/tmp') as temporary:
    app = Path(temporary) / 'Syllapace Preview.app'
    subprocess.run(['ditto', str(root / 'build/Syllapace.app'), str(app)], check=True)
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info['CFBundleIdentifier'] = 'app.syllapace.preview.capture'
    info['CFBundleName'] = 'Syllapace Preview'
    plist.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
    try:
        for language in languages:
            shots = output / language
            shots.mkdir()
            log = output / f'{language}.log'
            command = ['open', '-W', '-n', '-a', str(app), '--stderr', str(log), '--stdout', str(log)]
            for key, value in {
                'APP_DEMO': '1', 'APP_STORE': str(Path(temporary) / f'{language}.json'),
                'APP_SNAPSHOT': str(shots), 'APP_SNAPSHOT_EMPTY': '1',
                'APP_SNAPSHOT_EXTERNAL': '1', 'APP_LANGUAGE': language,
            }.items():
                command += ['--env', f'{key}={value}']
            process = subprocess.Popen(command)
            deadline = time.monotonic() + 120
            while process.poll() is None:
                if time.monotonic() > deadline:
                    raise RuntimeError('Preview timed out')
                for layout in shots.glob('*-layout.json'):
                    png = layout.with_name(layout.name.replace('-layout.json', '.png'))
                    if png.exists():
                        continue
                    measurement = json.loads(layout.read_text())
                    window_id = str(int(measurement['window']['number']))
                    subprocess.run(['/usr/sbin/screencapture', '-x', '-o', '-l', window_id, str(png)], check=True)
                time.sleep(0.05)
            report = log.read_text()
            if process.returncode or 'SNAPSHOT done' not in report or 'Capture failed' in report or 'fallback' in report:
                raise RuntimeError(report)
            assert len(list(shots.glob('*.png'))) == 18, 'Missing native screenshots'
            print(f'{language}: 18 active native windows captured in {shots}', flush=True)
    finally:
        # The exact temporary executable is ours; never quit the installed app.
        found = subprocess.run(['pgrep', '-f', re.escape(str(app / 'Contents/MacOS/Syllapace'))], capture_output=True, text=True)
        for pid in found.stdout.split():
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
print(f'SNAPSHOTS {output}')
