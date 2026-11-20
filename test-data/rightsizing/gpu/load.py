"""Run a bounded, concurrent load phase against the lab vLLM Service."""

import json
import math
import time
from concurrent.futures import ThreadPoolExecutor
from urllib.error import URLError
from urllib.request import Request, urlopen

URL = "http://vllm:8000/v1/completions"
WORKERS = 8
DURATION_SECONDS = 180


def send_requests(deadline, worker):
    latencies = []
    generated_tokens = 0
    failures = 0
    sequence = 0
    while time.monotonic() < deadline:
        sequence += 1
        body = json.dumps({
            "model": "opt125m",
            "prompt": f"Request {worker}-{sequence}. The capital of France is",
            "temperature": 0,
            "max_tokens": 64,
            "ignore_eos": True,
        }).encode()
        request = Request(URL, data=body, headers={"Content-Type": "application/json"})
        started = time.monotonic()
        try:
            with urlopen(request, timeout=15) as response:
                generated_tokens += json.load(response)["usage"]["completion_tokens"]
            latencies.append(time.monotonic() - started)
        except (URLError, TimeoutError, ValueError, KeyError) as error:
            if failures == 0:
                print(f"Worker {worker} first failure: {error}", flush=True)
            failures += 1
            time.sleep(1)
    return latencies, generated_tokens, failures


def main():
    started = time.monotonic()
    deadline = started + DURATION_SECONDS
    with ThreadPoolExecutor(max_workers=WORKERS) as executor:
        results = list(executor.map(lambda worker: send_requests(deadline, worker), range(WORKERS)))

    elapsed = time.monotonic() - started
    latencies = sorted(latency for samples, _, _ in results for latency in samples)
    tokens = sum(tokens for _, tokens, _ in results)
    failures = sum(failures for _, _, failures in results)
    p95 = latencies[math.ceil(0.95 * len(latencies)) - 1] if latencies else None
    print(json.dumps({
        "successful_requests": len(latencies),
        "failed_requests": failures,
        "completion_tokens_per_second": round(tokens / elapsed, 2),
        "p95_request_seconds": round(p95, 3) if p95 is not None else None,
    }), flush=True)
    return 1 if failures or not latencies else 0


if __name__ == "__main__":
    raise SystemExit(main())
