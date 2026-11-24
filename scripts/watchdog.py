#!/usr/bin/env python3


"""Host-side OrbStack/Compose supervisor. No third-party Python dependencies."""
import argparse
import fcntl
import json
import logging
import os
import signal
import subprocess
import threading
import time
import urllib.parse
import urllib.request
from logging.handlers import RotatingFileHandler
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = Path.home() / 'Library/Application Support/homeserver-watchdog'
LOG = logging.getLogger('homeserver-watchdog')
BUDGET = 20 * 60
INTERVAL = 60
COOLDOWN = 300


def run(args, timeout=30):
    # Kill the whole CLI process group on timeout, including Compose helpers.
    process = subprocess.Popen(args, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, _ = process.communicate(timeout=max(0.1, timeout))
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise RuntimeError('command timed out: ' + args[0]) from None
    if process.returncode:
        # CLI output can contain interpolated credentials. Never log it.
        raise RuntimeError('command failed: ' + args[0])
    return stdout.decode()


def ping(url, suffix=''):
    if not url:
        return
    try:
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != 'https' or parsed.hostname not in ('hc-ping.com',):
            raise ValueError('unsupported heartbeat URL')
        with urllib.request.urlopen(url.rstrip('/') + suffix, timeout=10) as response:
            response.read(1024)
    except Exception:
        LOG.warning('Heartbeat delivery failed (URL and error details withheld)')


def load_config():
    path = STATE / 'config.json'
    return json.loads(path.read_text()) if path.exists() else {}


class Watchdog:
    def __init__(self, config):
        self.config = config
        self.docker = config.get('docker', '/usr/local/bin/docker')
        self.orbctl = config.get('orbctl', '/opt/homebrew/bin/orbctl')
        self.compose = [self.docker, '--context', 'orbstack', 'compose',
                        '--project-directory', str(ROOT), '-f', str(ROOT / 'compose.yml')]
        self.failed = False

    def engine(self, timeout=10):
        try:
            run([self.docker, '--context', 'orbstack', 'info'], timeout=timeout)
            return True
        except RuntimeError:
            return False

    def status(self, timeout=60):
        deadline = time.monotonic() + timeout
        expected = set(run(self.compose + ['config', '--services'], timeout=min(30, timeout)).split())
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError('Health query deadline exceeded')
        raw = run(self.compose + ['ps', '--all', '--format', 'json'], timeout=min(30, remaining))
        # Compose versions emit either a JSON array or newline-delimited objects.
        rows = json.loads(raw) if raw.lstrip().startswith('[') else [
            json.loads(line) for line in raw.splitlines() if line.strip()]
        return services_healthy(expected, rows)

    def storage_ready(self):
        # Do not create substitute directories on the internal disk.
        return os.path.ismount('/Volumes/Backup') and all(
            Path(path).is_dir() for path in (
                '/Volumes/Backup/Photos', '/Volumes/Backup/Books',
                '/Volumes/Backup/homeserver-data/immich'))

    def failure(self, message):
        LOG.error(message)
        if not self.failed:
            ping(self.config.get('stack_ping_url'), '/fail')
        self.failed = True

    def recover(self):
        deadline = time.monotonic() + BUDGET

        def remaining():
            seconds = deadline - time.monotonic()
            if seconds <= 0:
                raise RuntimeError('20-minute recovery deadline exceeded')
            return seconds

        if not self.engine(timeout=min(10, remaining())):
            self.failure('OrbStack Docker unavailable; requesting OrbStack startup')
            run([self.orbctl, 'start'], timeout=min(60, remaining()))
            while not self.engine(timeout=min(10, remaining())):
                time.sleep(min(5, remaining()))
        if not self.storage_ready():
            raise RuntimeError('External SSD or required media directories unavailable; recovery deferred')
        # Validate before stopping anything. Never log rendered Compose config.
        run(self.compose + ['config', '--quiet'], timeout=min(30, remaining()))
        LOG.warning('Stopping stack gracefully before starting it again')
        run(self.compose + ['stop', '--timeout', '30'], timeout=min(90, remaining()))
        # up pulls missing images, starts in dependency order, and waits for health.
        # Preserve containers/volumes unless Compose itself needs to recreate them.
        run(self.compose + ['up', '-d', '--wait', '--wait-timeout',
                            str(max(1, int(remaining())))], timeout=remaining())
        if not self.status(timeout=remaining()):
            raise RuntimeError('Stack did not pass the final health check')
        remaining()

    def tick(self):
        if (STATE / 'paused').exists():
            LOG.info('Maintenance pause active; no stack checks or recovery')
            return
        try:
            if not self.engine() or not self.status():
                self.failure('Docker or deployed containers not healthy; beginning recovery')
                self.recover()
            ping(self.config.get('stack_ping_url'))
            if self.failed:
                LOG.info('Stack recovered; all configured services running/healthy')
            self.failed = False
        except (RuntimeError, OSError, ValueError) as error:
            # Only our own RuntimeErrors contain safe, curated messages.
            if isinstance(error, RuntimeError):
                LOG.error('%s', error)
            self.failure('Recovery failed; retry after cooldown. Check Docker, container health, and SSD mount')
            raise RuntimeError('Recovery incomplete') from None


def services_healthy(expected, rows):
    if not expected:
        return False
    active = [row for row in rows if row.get('Service') in expected]
    return (expected <= {row['Service'] for row in active}
            and all(row.get('State') == 'running' and
                    row.get('Health', '') in ('', 'healthy') for row in active))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Read-only engine/stack health check')
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    watchdog = Watchdog(load_config())
    if args.check:
        healthy = watchdog.engine() and watchdog.status()
        print('PASS: Docker and all Compose services healthy' if healthy else 'FAIL: Docker or Compose services not healthy')
        return 0 if healthy else 1
    # Covers manual invocation as well as launchd's single-instance guarantee.
    with (STATE / 'lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        handler = RotatingFileHandler(STATE / 'watchdog.log', maxBytes=2_000_000, backupCount=3)
        handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
        LOG.addHandler(handler)
        LOG.setLevel(logging.INFO)

        def host_heartbeat():
            while True:
                ping(watchdog.config.get('host_ping_url'))
                time.sleep(INTERVAL)

        threading.Thread(target=host_heartbeat, daemon=True).start()
        LOG.info('Watchdog started')
        while True:
            try:
                watchdog.tick()
                time.sleep(INTERVAL)
            except RuntimeError:
                time.sleep(COOLDOWN)


if __name__ == '__main__':
    raise SystemExit(main())
