"""Check a list of HTTP endpoints concurrently and report status and latency.

    healthcheck https://example.com https://api.example.com/healthz
    healthcheck -f urls.txt --timeout 3 --max-latency 500 --json

Exits 1 if any endpoint is down or slower than --max-latency.
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass
from typing import List, Optional


@dataclass
class Result:
    url: str
    ok: bool
    status: Optional[int]
    latency_ms: Optional[int]
    error: Optional[str] = None


def check(url: str, timeout: float, max_latency_ms: Optional[int] = None) -> Result:
    if not url.startswith(("http://", "https://")):
        return Result(url, False, None, None, "only http(s) URLs are supported")
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:  # noqa: S310 - scheme checked above
            status = resp.status
    except urllib.error.HTTPError as err:
        status = err.code
    except (urllib.error.URLError, TimeoutError, OSError) as err:
        reason = getattr(err, "reason", err)
        return Result(url, False, None, None, str(reason))
    latency = round((time.perf_counter() - start) * 1000)
    if status >= 400:
        return Result(url, False, status, latency, f"HTTP {status}")
    if max_latency_ms is not None and latency > max_latency_ms:
        return Result(url, False, status, latency, f"slower than {max_latency_ms}ms")
    return Result(url, True, status, latency)


def check_all(urls: List[str], timeout: float, max_latency_ms: Optional[int], workers: int) -> List[Result]:
    with ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(lambda u: check(u, timeout, max_latency_ms), urls))


def format_table(results: List[Result]) -> str:
    width = max((len(r.url) for r in results), default=3)
    lines = [f"{'URL':<{width}}  STATE  CODE  LATENCY  DETAIL"]
    for r in results:
        code = str(r.status) if r.status is not None else "-"
        latency = f"{r.latency_ms}ms" if r.latency_ms is not None else "-"
        state = "UP" if r.ok else "DOWN"
        lines.append(f"{r.url:<{width}}  {state:<5}  {code:<4}  {latency:<7}  {r.error or ''}".rstrip())
    return "\n".join(lines)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("urls", nargs="*")
    parser.add_argument("-f", "--file", help="file with one URL per line (# comments allowed)")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--max-latency", type=int, help="fail endpoints slower than this many ms")
    parser.add_argument("--workers", type=int, default=10)
    parser.add_argument("--json", action="store_true", help="print JSON instead of a table")
    args = parser.parse_args(argv)

    urls = list(args.urls)
    if args.file:
        with open(args.file) as fh:
            urls += [line.strip() for line in fh if line.strip() and not line.startswith("#")]
    if not urls:
        parser.error("no URLs given")

    results = check_all(urls, args.timeout, args.max_latency, args.workers)
    print(json.dumps([asdict(r) for r in results], indent=2) if args.json else format_table(results))
    return 0 if all(r.ok for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
