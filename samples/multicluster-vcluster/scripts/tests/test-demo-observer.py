"""Regression checks for unknown observations and ScaledJob Pod ownership."""
import importlib.util
import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("observer", Path(__file__).parents[1] / "demo-observer.py")
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)


class ObserverTests(unittest.TestCase):
    def cpu_inventory(self):
        return [
            {"kind": "Deployment", "metadata": {"name": "worker", "generation": 1},
             "spec": {"replicas": 1}, "status": {"observedGeneration": 1, "replicas": 1, "readyReplicas": 1, "updatedReplicas": 1}},
            {"kind": "KedifyPodAutoscaler", "metadata": {"name": "worker-autoscaler"},
             "status": {"conditions": [{"type": "ScalingActive", "status": "True"}]}},
            {"kind": "Pod", "metadata": {"name": "worker-pod", "labels": {"app": "worker"}, "creationTimestamp": "2026-10-13T17:00:00Z"},
             "status": {"phase": "Running", "startTime": "2026-10-13T17:00:00Z", "conditions": [
                 {"type": "Ready", "status": "True", "lastTransitionTime": "2026-10-13T17:00:01Z"}]}},
        ]

    def test_top_sample_must_have_whole_window_after_ready(self):
        items = self.cpu_inventory()
        now = observer.timestamp("2026-10-13T17:01:10Z")
        metrics = {"items": [{"metadata": {"name": "worker-pod"}, "timestamp": "2026-10-13T17:01:00Z",
                              "window": "59.65s", "containers": [{"usage": {"cpu": "1000000n"}}]}]}
        self.assertFalse(observer.cpu_metrics_usable(items, metrics, now))
        metrics["items"][0]["window"] = "59s"
        self.assertTrue(observer.cpu_metrics_usable(items, metrics, now))
        for mutate in [lambda data: data[2]["metadata"].update(deletionTimestamp="2026-10-13T17:01:01Z"),
                       lambda data: data[0]["status"].update(observedGeneration=0),
                       lambda data: data[1]["status"]["conditions"][0].update(status="False")]:
            other = copy.deepcopy(items)
            mutate(other)
            self.assertFalse(observer.cpu_metrics_usable(other, metrics, now))
        self.assertFalse(observer.cpu_metrics_usable(items, None, now))
        self.assertFalse(observer.cpu_metrics_usable(items, metrics, now + 151))

    def test_warmup_requires_known_message_new_pod_and_bounded_failure(self):
        items = self.cpu_inventory()
        active = items[1]["status"]["conditions"][0]
        active.update(status="False", reason="FailedGetMetric", message="metric 0 (Resource): no metrics for ready target pods",
                      lastTransitionTime="2026-10-13T17:00:02Z")
        now = observer.timestamp("2026-10-13T17:01:00Z")
        pods = observer.worker_pods(items)
        self.assertTrue(observer.cpu_startup_warmup(items[1], pods, now))
        self.assertFalse(observer.cpu_startup_warmup(items[1], pods, now + 100))
        for message in ["metric 0 (Resource): get resource metric cpu: forbidden", "context deadline exceeded", "connection refused"]:
            active["message"] = message
            self.assertFalse(observer.cpu_startup_warmup(items[1], pods, now))
        active["message"] = "metric 0 (Resource): no metrics for ready target pods"
        active["lastTransitionTime"] = "2026-10-13T16:55:00Z"
        self.assertFalse(observer.cpu_startup_warmup(items[1], pods, now))
        active["lastTransitionTime"] = "2026-10-13T17:00:02Z"
        items[2]["metadata"]["creationTimestamp"] = "2026-10-13T16:55:00Z"
        self.assertFalse(observer.cpu_startup_warmup(items[1], pods, now))

    def test_warmup_display_retains_real_condition_and_scopes_to_vc1(self):
        items = self.cpu_inventory() + [{"kind": "ScaledObject", "metadata": {"name": "worker"}}]
        active = items[1]["status"]["conditions"][0]
        active.update(status="False", reason="FailedGetMetric", message="metric 0 (Resource): no metrics for ready target pods",
                      lastTransitionTime="2026-10-13T17:00:02Z")
        with patch.object(observer.time, "time", return_value=observer.timestamp("2026-10-13T17:01:00Z")):
            state = observer.summarize(items, 1)
            self.assertEqual(state["scalingActive"], "False")
            self.assertEqual(state["kpaReason"], "FailedGetMetric")
            lines = "\n".join(observer.member_lines(state))
            self.assertIn("ScalingActive=False", lines)
            self.assertIn("Collecting CPU metrics…", lines)
            self.assertNotIn("KPA reason: FailedGetMetric", lines)
            self.assertFalse(observer.summarize(items, 3)["cpuWarmup"])

    def test_jobs_include_pods_owned_by_jobs_without_a_scaledjob_label(self):
        state = observer.summarize([
            {"kind": "ScaledJob", "metadata": {"name": "worker"}},
            {"kind": "Job", "metadata": {"name": "job", "uid": "job-uid", "labels": {"scaledjob.keda.sh/name": "worker"}}, "status": {"active": 1}},
            {"kind": "Pod", "metadata": {"name": "job-pod", "ownerReferences": [{"uid": "job-uid"}]}, "status": {"conditions": [{"type": "Ready", "status": "True"}]}},
            {"kind": "Pod", "metadata": {"name": "unrelated", "ownerReferences": [{"uid": "other-job"}]}},
        ], 2)
        self.assertEqual(state["jobsActive"], 1)
        self.assertEqual(state["pods"], 1)
        self.assertEqual(state["readyPods"], 1)
        self.assertIsNone(state["desired"])

    def test_cache_expiry_never_returns_old_replica_counts(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(observer, "CACHE", Path(directory)):
            observer.cache_state({"member": 1, "updated": 100, "connection": "CONNECTED", "desired": 3})
            self.assertEqual(observer.cached_member(1, now=101)["desired"], 3)
            self.assertEqual(observer.cached_member(1, now=200), {"connection": "STALE", "registrationUID": None})
            self.assertEqual(observer.cached_member(2), {"connection": "WAITING"})
            self.assertEqual((Path(directory) / 'vc-1.json').stat().st_mode & 0o777, 0o600)

    def host_output(self, registrations, cached):
        output = []
        def finish(_):
            observer.STOP = True
        observer.STOP = False
        with patch.object(observer, "kube_get", side_effect=[registrations, {"items": []}]), patch.object(observer, "cached_member", return_value=cached), patch.object(observer, "display", side_effect=output.extend), patch.object(observer.time, "sleep", side_effect=finish):
            observer.observe_host()
        observer.STOP = False
        return output

    def test_recreated_member_invalidates_previous_registration_observations(self):
        lines = self.host_output({"items": [{"metadata": {"uid": "new"}, "spec": {"clusterName": "vc-1.vcluster-1"}, "status": {"conditions": [{"type": "Ready", "status": "True"}]}}]}, {"registrationUID": "old", "connection": "CONNECTED", "desired": 3, "available": 3})
        row = next(line for line in lines if line.startswith('vc-1'))
        self.assertIn('UPDATING', row)
        self.assertIn('?/?', row)
        self.assertNotIn('3/3', row)

    def test_absent_registration_and_failed_inventory_do_not_show_cached_counts(self):
        cached = {"registrationUID": "old", "connection": "CONNECTED", "desired": 3, "available": 3}
        for inventory, expected in [({"items": []}, 'WAITING'), (None, 'UNKNOWN')]:
            with self.subTest(expected=expected):
                row = next(line for line in self.host_output(inventory, cached) if line.startswith('vc-1'))
                self.assertIn(expected, row)
                self.assertIn('?/?', row)

    def test_observed_kpa_zero_is_distinct_from_unobserved_status(self):
        kpa = {"kind": "KedifyPodAutoscaler", "metadata": {"name": "worker-autoscaler"}}
        self.assertIsNone(observer.summarize([kpa], 3)["kpaCurrent"])
        kpa["status"] = {"observedGeneration": 1, "desiredReplicas": 0}
        self.assertEqual(observer.summarize([kpa], 3)["kpaCurrent"], 0)


if __name__ == '__main__':
    unittest.main()
