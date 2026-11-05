#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# LaunchServices plus a separate bundle identity keeps a running installed app
# from swallowing the test window. All data and preferences stay isolated.
python3 - <<'PY'
import os, plistlib, re, signal, subprocess, tempfile
from pathlib import Path
with tempfile.TemporaryDirectory(prefix='syllapace-selftest-', dir='/tmp') as folder:
    root = Path(folder)
    app = root / 'Syllapace Selftest.app'
    subprocess.run(['ditto', 'build/Syllapace.app', str(app)], check=True)
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info['CFBundleIdentifier'] = f'app.syllapace.selftest.run{os.getpid()}'
    plist.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, capture_output=True)
    log = root / 'selftest.log'
    language = os.environ.get('APP_LANGUAGE', 'en')
    try:
        subprocess.run(['open', '-W', '-n', '-a', str(app), '--stderr', str(log), '--stdout', str(log),
                        '--env', f'APP_STORE={root / "archive.json"}', '--env', 'APP_SELFTEST=1',
                        '--env', f'APP_LANGUAGE={language}', '--args', '-appLanguage', language,
                        '-AppleShowScrollBars', 'Always',
                        '-interfaceScale', os.environ.get('APP_TEST_SCALE', '1')], check=True, timeout=180)
        report = log.read_text()
        if 'SELFTEST complete' not in report or 'FAIL' in report:
            raise RuntimeError('Isolated self-test did not pass')
    finally:
        if log.exists(): print(log.read_text(), end='', flush=True)
        owned = subprocess.run(['pgrep', '-f', re.escape(str(app / 'Contents/MacOS/Syllapace'))], capture_output=True, text=True)
        for pid in owned.stdout.split():
            try: os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError: pass
PY
