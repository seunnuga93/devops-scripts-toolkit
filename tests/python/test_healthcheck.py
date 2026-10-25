import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from devops_toolkit import healthcheck


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow":
            time.sleep(0.3)
        self.send_response(500 if self.path == "/broken" else 200)
        self.end_headers()

    def log_message(self, *args):
        pass


@pytest.fixture(scope="module")
def base():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{server.server_port}"
    server.shutdown()


def test_healthy_endpoint(base):
    r = healthcheck.check(f"{base}/ok", timeout=2)
    assert r.ok and r.status == 200 and r.latency_ms is not None


def test_server_error_is_down(base):
    r = healthcheck.check(f"{base}/broken", timeout=2)
    assert not r.ok and r.status == 500 and r.error == "HTTP 500"


def test_slow_endpoint_fails_latency_budget(base):
    r = healthcheck.check(f"{base}/slow", timeout=2, max_latency_ms=100)
    assert not r.ok and r.error == "slower than 100ms"


def test_unreachable_host():
    r = healthcheck.check("http://127.0.0.1:1", timeout=1)
    assert not r.ok and r.status is None


def test_rejects_non_http_scheme():
    r = healthcheck.check("file:///etc/passwd", timeout=1)
    assert not r.ok and "http" in r.error


def test_main_exit_code_and_json(base, capsys):
    assert healthcheck.main([f"{base}/ok", "--json"]) == 0
    assert json.loads(capsys.readouterr().out)[0]["ok"] is True
    assert healthcheck.main([f"{base}/ok", f"{base}/broken"]) == 1


def test_reads_urls_from_file(base, tmp_path):
    urls = tmp_path / "urls.txt"
    urls.write_text(f"# comment\n{base}/ok\n\n{base}/ok\n")
    assert healthcheck.main(["-f", str(urls)]) == 0
