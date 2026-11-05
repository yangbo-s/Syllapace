#!/usr/bin/env python3
"""Capture active light/dark app windows in an isolated preview, without installation."""
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
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / '.impeccable/review' / f'review-{time.time_ns()}'
output.mkdir(parents=True, exist_ok=False)
languages = [os.environ['APP_LANGUAGE']] if os.environ.get('APP_LANGUAGE') else ['en', 'zh-Hans']
capture_flags = {key: os.environ.get(key, '0') for key in
                 ('APP_SNAPSHOT_CONTROLS', 'APP_SNAPSHOT_EMPTY', 'APP_SNAPSHOT_WORKSPACE', 'APP_SNAPSHOT_GANTT', 'APP_SNAPSHOT_COPY', 'APP_SNAPSHOT_CREDENTIALS', 'APP_SNAPSHOT_APPEARANCE', 'APP_SNAPSHOT_ACTIVITY')}
if sum(value == '1' for value in capture_flags.values()) > 1:
    raise ValueError('Choose only one APP_SNAPSHOT mode')


def expected_names():
    appearances = ('light', 'dark')
    views = ('list', 'gantt', 'calendar')
    if capture_flags['APP_SNAPSHOT_GANTT'] == '1':
        return {f'workspace-gantt-{width}-{mode}.png' for width in (1320, 1120, 940) for mode in appearances}
    if capture_flags['APP_SNAPSHOT_ACTIVITY'] == '1':
        return {f'activity-{name}-{mode}.png' for name in ('summary', 'compact', 'details', 'running', 'running-details') for mode in appearances}
    if capture_flags['APP_SNAPSHOT_APPEARANCE'] == '1':
        return {f'appearance-{name}-{mode}.png' for name in ('90', '100', '115', 'settings') for mode in appearances}
    if capture_flags['APP_SNAPSHOT_CREDENTIALS'] == '1':
        return {f'credentials-{name}-{mode}.png' for name in ('local', 'keychain', 'error', 'updates', 'canvas', 'models') for mode in appearances}
    if capture_flags['APP_SNAPSHOT_COPY'] == '1':
        return {f'{name}-{mode}.png' for name in ('settings-1', 'desktop', 'desktop-expanded') for mode in appearances}
    if capture_flags['APP_SNAPSHOT_CONTROLS'] == '1':
        return {f'course-scope-{width}-{mode}.png' for width in (940, 1120) for mode in appearances}
    if capture_flags['APP_SNAPSHOT_WORKSPACE'] == '1':
        # 18 wide/regular/narrow views + 6 empty/course/academic states = 24 per language.
        return ({f'workspace-{view}-{width}-{mode}.png'
                 for view in views for width in (1320, 1120, 940) for mode in appearances}
                | {f'workspace-list-{state}-{mode}.png'
                   for state in ('empty', 'course', 'academic') for mode in appearances})
    if capture_flags['APP_SNAPSHOT_EMPTY'] == '1':
        return ({f'empty-{page}-{width}-{mode}.png'
                 for page in ('workspace-list', 'review', 'sources', 'course')
                 for width in (940, 1280) for mode in appearances}
                | {f'settings-canvas-{mode}.png' for mode in appearances})
    # Six pages/views + eighteen sheets/panels/settings, twice, plus three edge states = 51.
    per_appearance = ([f'workspace-{view}' for view in views]
                      + ['review', 'sources', 'editor', 'session-editor', 'import',
                         'import-1', 'import-2', 'import-3', 'course-display', 'source-reader',
                         'course-scope', 'course-scope-narrow', 'desktop', 'desktop-expanded',
                         'settings-5', 'settings-3', 'settings-0', 'settings-1', 'settings-4', 'settings-2',
                         'school-search'])
    return ({f'{name}-{mode}.png' for name in per_appearance for mode in appearances}
            | {'course-empty-dark.png', 'review-narrow-dark.png', 'empty-dark.png'})


expected = expected_names()

with tempfile.TemporaryDirectory(prefix='syllapace-window-review-', dir='/tmp') as temporary:
    app = Path(temporary) / 'Syllapace Preview.app'
    subprocess.run(['ditto', str(root / 'build/Syllapace.app'), str(app)], check=True)
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info['CFBundleIdentifier'] = f'app.syllapace.preview.review{os.getpid()}'
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
                'APP_SNAPSHOT': str(shots),
                'APP_SNAPSHOT_EXTERNAL': '1', 'APP_LANGUAGE': language, 'APP_SNAPSHOT_WAIT': '1',
                **capture_flags,
            }.items():
                command += ['--env', f'{key}={value}']
            command += ['--args', '-appLanguage', language]
            process = subprocess.Popen(command)
            deadline = time.monotonic() + 600
            last_capture = time.monotonic()
            while process.poll() is None:
                if time.monotonic() > deadline:
                    raise RuntimeError('Preview timed out')
                for layout in shots.glob('*-layout.json'):
                    png = layout.with_name(layout.name.replace('-layout.json', '.png'))
                    if png.exists():
                        continue
                    last_capture = time.monotonic()
                    measurement = json.loads(layout.read_text())
                    window_id = str(int(measurement['window']['number']))
                    subprocess.run(['/usr/sbin/screencapture', '-x', '-o', '-l', window_id, str(png)], check=True)
                # Activation from the launching process is more reliable than a
                # background app asking to activate itself on recent macOS.
                if time.monotonic() - last_capture > 10 and 'SNAPSHOT done' not in (log.read_text() if log.exists() else ''):
                    subprocess.run(['open', '-a', str(app)], check=True)
                    last_capture = time.monotonic()
                time.sleep(0.05)
            report = log.read_text()
            if process.returncode or 'SNAPSHOT done' not in report or 'Capture failed' in report or 'fallback' in report:
                raise RuntimeError(report)
            actual = {path.name for path in shots.glob('*.png')}
            if actual != expected:
                raise RuntimeError(f'Screenshot set differs: missing={sorted(expected - actual)}, unexpected={sorted(actual - expected)}')
            print(f'{language}: {len(expected)} active native windows captured in {shots}', flush=True)
    finally:
        # The exact temporary executable is ours; never quit the installed app.
        found = subprocess.run(['pgrep', '-f', re.escape(str(app / 'Contents/MacOS/Syllapace'))], capture_output=True, text=True)
        for pid in found.stdout.split():
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
print(f'SNAPSHOTS {output}')
