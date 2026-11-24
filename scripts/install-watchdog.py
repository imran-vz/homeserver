#!/usr/bin/env python3

"""Install the watchdog for the current macOS login session (no sudo)."""
import json
import os
import plistlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = Path.home() / 'Library/Application Support/homeserver-watchdog'
LABEL = 'com.imran.homeserver-watchdog'
STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
config = STATE / 'config.json'
if not config.exists():
    config.write_text(json.dumps({'host_ping_url': '', 'stack_ping_url': ''}, indent=2) + '\n')
config.chmod(0o600)
agent = Path.home() / 'Library/LaunchAgents' / (LABEL + '.plist')
agent.parent.mkdir(parents=True, exist_ok=True)
agent.write_bytes(plistlib.dumps({
    'Label': LABEL,
    'ProgramArguments': [str(Path(sys.executable).resolve()), str(ROOT / 'scripts/watchdog.py')],
    'WorkingDirectory': str(ROOT),
    'EnvironmentVariables': {'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'},
    'RunAtLoad': True,
    'KeepAlive': True,
    'ThrottleInterval': 60,
    'StandardOutPath': str(STATE / 'launchd.log'),
    'StandardErrorPath': str(STATE / 'launchd.log'),
}))
domain = 'gui/' + str(os.getuid())
subprocess.run(['launchctl', 'bootout', domain + '/' + LABEL], capture_output=True)
subprocess.run(['launchctl', 'bootstrap', domain, str(agent)], check=True)
print('Watchdog installed and started. Alert configuration: ' + str(config))
print('Log: ' + str(STATE / 'watchdog.log'))
