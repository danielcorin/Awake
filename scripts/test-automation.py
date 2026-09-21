#!/usr/bin/env python3
"""Exercise the generated CLI and real HTTP listener without user data or Keychain access."""
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import tempfile
import urllib.error
import urllib.request

root = Path(__file__).resolve().parent.parent
products = root / "build/Build/Products/Debug"


def stop(process):
    if process is not None and process.poll() is None:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=22)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait()
            raise AssertionError("Shutdown exceeded its deadline")


def line(process):
    assert select.select([process.stdout], [], [], 15)[0], "Readiness timeout"
    value = process.stdout.readline()
    assert value, process.stderr.read()
    return value


with tempfile.TemporaryDirectory(prefix="awake-api-", dir="/tmp") as temporary:
    env = {**os.environ, "APP_AUTOMATION_ROOT": temporary, "XDG_CONFIG_HOME": temporary + "/config"}
    app = server = None
    try:
        app = subprocess.Popen([str(products / "AwakeAutomationFixture"), temporary], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert line(app).strip() == "ready"
        def cli(*arguments):
            result = subprocess.run([str(products / "awake"), *arguments, "--json"], env=env, capture_output=True, text=True, timeout=15)
            assert result.returncode == 0, result.stderr
            return json.loads(result.stdout)
        assert cli("status")["data"]["appName"] == "Awake fixture"
        spec = cli("api", "schema")
        expected = {op["operationId"] for item in spec["paths"].values() for op in item.values() if isinstance(op, dict) and "operationId" in op}
        assert {op["id"] for op in cli("api", "operations")["data"]["operations"]} == expected
        human = subprocess.run([str(products / "awake"), "status"], env=env, capture_output=True, text=True, check=True).stdout
        assert "Awake fixture" in human and "pid" in human
        token = cli("api", "token", "create")["data"]["token"]
        server = subprocess.Popen([str(products / "awake"), "serve", "--port", "0", "--json"], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        ready = json.loads(line(server)); assert ready["event"] == "ready"
        def http(path, token=token, method="GET", body=None, status=200):
            headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"} if token else {}
            request = urllib.request.Request(ready["address"] + path, data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
            try:
                response = urllib.request.urlopen(request, timeout=10)
            except urllib.error.HTTPError as error:
                response = error
            assert response.status == status
            return json.loads(response.read())
        http("/health", token=None)
        http("/v1/app/status", token=None, status=401)
        assert http("/openapi.json") == cli("api", "schema")
        http("/v1/configuration/keep-display-on", method="PUT", body={"value": "false"})
        assert cli("config", "get", "keep-display-on")["data"]["value"] is False
        cli("config", "set", "keep-display-on", "--value", "true")
        assert http("/v1/configuration/keep-display-on")["data"]["value"] is True
        updated = cli("api", "token", "rotate", "--force")["data"]["token"]
        http("/ready", status=401)
        http("/ready", token=updated)
        cli("api", "token", "revoke", "--force")
        http("/ready", token=updated, status=401)
        stop(server)
        assert server.returncode == 0 and app.poll() is None
        print("Scaffold CLI/HTTP, typed Swift renderer, credentials, shared configuration, and shutdown passed.")
    finally:
        stop(server); stop(app)
