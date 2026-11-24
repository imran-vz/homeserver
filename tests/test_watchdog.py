import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('watchdog', Path(__file__).resolve().parents[1] / 'scripts/watchdog.py')
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)


class HealthTests(unittest.TestCase):
    def test_all_expected_services_required(self):
        self.assertFalse(w.services_healthy({'app', 'db'}, [
            {'Service': 'app', 'State': 'running', 'Health': 'healthy'}]))

    def test_bad_states_fail(self):
        for state, health in [('exited', ''), ('running', 'unhealthy'), ('running', 'starting')]:
            with self.subTest(state=state, health=health):
                self.assertFalse(w.services_healthy({'app'}, [
                    {'Service': 'app', 'State': state, 'Health': health}]))

    def test_running_without_healthcheck_allowed(self):
        self.assertTrue(w.services_healthy({'app'}, [{'Service': 'app', 'State': 'running', 'Health': ''}]))
        self.assertFalse(w.services_healthy(set(), []))


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.wd = w.Watchdog({})

    @patch.object(w, 'run', return_value='')
    def test_stop_then_up_never_restart(self, run):
        with patch.object(self.wd, 'engine', return_value=True), \
             patch.object(self.wd, 'storage_ready', return_value=True), \
             patch.object(self.wd, 'status', return_value=True):
            self.wd.recover()
        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn('stop', commands[1])
        self.assertIn('up', commands[2])
        self.assertIn('--wait', commands[2])
        self.assertTrue(all('restart' not in cmd and 'down' not in cmd for cmd in commands))
        self.assertTrue(all(call.kwargs['timeout'] <= 1200 for call in run.call_args_list))

    @patch.object(w, 'run')
    def test_missing_disk_does_not_stop_or_start(self, run):
        with patch.object(self.wd, 'engine', return_value=True), \
             patch.object(self.wd, 'storage_ready', return_value=False):
            with self.assertRaises(RuntimeError):
                self.wd.recover()
        run.assert_not_called()

    @patch.object(w, 'ping')
    @patch.object(w, 'run', return_value='')
    def test_engine_down_starts_orbstack_before_compose(self, run, ping):
        with patch.object(self.wd, 'engine', side_effect=[False, True]), \
             patch.object(self.wd, 'storage_ready', return_value=True), \
             patch.object(self.wd, 'status', return_value=True):
            self.wd.recover()
        self.assertEqual(run.call_args_list[0].args[0], [self.wd.orbctl, 'start'])

    @patch.object(w, 'ping')
    def test_failed_recovery_never_sends_success(self, ping):
        with patch.object(w.Path, 'exists', return_value=False), \
             patch.object(self.wd, 'engine', return_value=False), \
             patch.object(self.wd, 'recover', side_effect=RuntimeError):
            with self.assertRaises(RuntimeError):
                self.wd.tick()
        self.assertEqual([call.args[1:] for call in ping.call_args_list], [('/fail',)])

    @patch.object(w, 'ping')
    def test_maintenance_does_not_touch_engine(self, ping):
        with patch.object(w.Path, 'exists', return_value=True), patch.object(self.wd, 'engine') as engine:
            self.wd.tick()
        engine.assert_not_called()
        ping.assert_not_called()

    @patch.object(w, 'run', return_value='')
    def test_deadline_stops_recovery(self, run):
        with patch.object(self.wd, 'engine', return_value=True), \
             patch.object(self.wd, 'storage_ready', return_value=True), \
             patch.object(w.time, 'monotonic', side_effect=[0, 1201]):
            with self.assertRaises(RuntimeError):
                self.wd.recover()
        run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
