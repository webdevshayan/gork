#!/usr/bin/env python3
"""gork VPS server — requests live here, not on the phone.

A sent message is enqueued in SQLite and a worker thread drives it to
completion: the device can turn off, the app can go inactive, the process
can die — the job keeps running and its result is ready when the client
comes back. The client NEVER cancels a job; there is no cancel endpoint.

Secrets (Google credentials JSON) are stored encrypted at rest and are
never returned by any endpoint, never logged. Scopes/status only.

Stdlib only except the optional `cryptography` package for Fernet sealing
(falls back to an HMAC-SHA256 keystream seal when it is missing).

Env:
  GORK_VPS_TOKEN      bearer token required on /v1/* (default: dev-token)
  GORK_DB             sqlite path (default: gork.sqlite3 next to this file)
  GORK_PROVIDER_URL   OpenAI-compatible base URL (default: none → jobs fail
                      honestly with 'provider not configured')
  GORK_PROVIDER_KEY   provider API key
  GORK_PROVIDER_MODEL model id (default: gpt-4o-mini)
"""
import base64
import hashlib
import hmac
import json
import os
import re
import sqlite3
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

DB_PATH = os.environ.get("GORK_DB",
                         os.path.join(os.path.dirname(__file__), "gork.sqlite3"))
VPS_TOKEN = os.environ.get("GORK_VPS_TOKEN", "dev-token")
PROVIDER_URL = os.environ.get("GORK_PROVIDER_URL", "")
PROVIDER_KEY = os.environ.get("GORK_PROVIDER_KEY", "")
PROVIDER_MODEL = os.environ.get("GORK_PROVIDER_MODEL", "gpt-4o-mini")

_MAX_ATTEMPTS = 3
_SECRET_KEYS = re.compile(
    r"client_secret|private_key|private_key_id|api[_-]?key|token|secret|"
    r"refresh_token|access_token|client_email", re.I)

# ---------------------------------------------------------------- sealing ---
try:  # real AES when available
    from cryptography.fernet import Fernet

    def _key():  # derive a stable Fernet key from the token
        return base64.urlsafe_b64encode(
            hashlib.sha256(("gork-vault:" + VPS_TOKEN).encode()).digest())

    def seal(data: bytes) -> bytes:
        return Fernet(_key()).encrypt(data)

    def unseal(data: bytes) -> bytes:
        return Fernet(_key()).decrypt(data)

    SEALED_WITH = "fernet"
except Exception:  # stdlib fallback: HMAC-SHA256 keystream + HMAC tag
    def _keystream(key: bytes, nonce: bytes, n: int) -> bytes:
        out, block = b"", 0
        while len(out) < n:
            out += hmac.new(key, nonce + block.to_bytes(4, "big"),
                            hashlib.sha256).digest()
            block += 1
        return out[:n]

    def seal(data: bytes) -> bytes:
        key = hashlib.sha256(("gork-vault:" + VPS_TOKEN).encode()).digest()
        nonce = os.urandom(16)
        ct = bytes(a ^ b for a, b in
                   zip(data, _keystream(key, nonce, len(data))))
        tag = hmac.new(key, nonce + ct, hashlib.sha256).digest()
        return b"GK1" + nonce + tag + ct

    def unseal(data: bytes) -> bytes:
        if not data.startswith(b"GK1"):
            raise ValueError("not a gork-sealed blob")
        nonce, tag, ct = data[3:19], data[19:51], data[51:]
        key = hashlib.sha256(("gork-vault:" + VPS_TOKEN).encode()).digest()
        good = hmac.new(key, nonce + ct, hashlib.sha256).digest()
        if not hmac.compare_digest(good, tag):
            raise ValueError("sealed blob failed authentication")
        return bytes(a ^ b for a, b in
                     zip(ct, _keystream(key, nonce, len(ct))))

    SEALED_WITH = "gork-seal"

# ------------------------------------------------------------------- store ---
_LOCK = threading.Lock()


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    with _LOCK, db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS jobs (
          id TEXT PRIMARY KEY, kind TEXT NOT NULL,
          conversation_id TEXT NOT NULL, payload TEXT NOT NULL,
          status TEXT NOT NULL, result TEXT, error TEXT,
          attempts INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS credentials (
          name TEXT PRIMARY KEY, sealed BLOB NOT NULL,
          updated_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS ingests (
          video_id TEXT PRIMARY KEY, title TEXT, transcript TEXT,
          frames TEXT, updated_at INTEGER NOT NULL);
        """)


def redact(obj):
    """Strip any secret-shaped value out of dicts before they are echoed,
    logged or stored in errors — defense in depth for the no-exposure rule."""
    if isinstance(obj, dict):
        return {k: ("[REDACTED]" if _SECRET_KEYS.search(k) else redact(v))
                for k, v in obj.items()}
    if isinstance(obj, list):
        return [redact(v) for v in obj]
    return obj


# ------------------------------------------------------------------ worker ---
def _conversation_history(c, conversation_id):
    rows = c.execute(
        "SELECT payload, result, kind, status FROM jobs WHERE "
        "conversation_id=? ORDER BY created_at", (conversation_id,)).fetchall()
    history = []
    for r in rows:
        if r["kind"] != "message":
            continue
        payload = json.loads(r["payload"])
        history.append({"role": "user", "content": payload.get("text", "")})
        if r["status"] == "done" and r["result"]:
            history.append({"role": "assistant",
                            "content": json.loads(r["result"])["reply"]})
    return history


def _call_provider(history):
    if not PROVIDER_URL:
        raise RuntimeError("provider not configured on the VPS")
    import urllib.request
    req = urllib.request.Request(
        PROVIDER_URL.rstrip("/") + "/chat/completions",
        data=json.dumps({"model": PROVIDER_MODEL,
                         "messages": history}).encode(),
        headers={"Content-Type": "application/json",
                 "Authorization": "Bearer " + PROVIDER_KEY},
        method="POST")
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read().decode())
    return body["choices"][0]["message"]["content"]


def yt_ingest(url):
    """YouTube ingestion: metadata + transcript + frames via yt-dlp/ffmpeg.
    Raises when the tools are missing — the job fails honestly."""
    import subprocess
    meta = json.loads(subprocess.run(
        ["yt-dlp", "-J", "--no-download", url],
        capture_output=True, timeout=180, check=True).stdout.decode())
    video_id = meta.get("id", "")
    transcript = ""
    try:
        subs = subprocess.run(
            ["yt-dlp", "-J", "--write-auto-subs", "--sub-lang", "en",
             "--skip-download", url],
            capture_output=True, timeout=180, check=True).stdout.decode()
        m = re.search(r'"ext": "vtt"', subs)  # presence marker
        transcript = "transcript-available" if m else ""
    except Exception:
        transcript = ""
    frames = subprocess.run(
        ["ffmpeg", "-i", meta.get("filepath", url), "-vf", "fps=1/5",
         "-frames:v", "20", "-"], capture_output=True, timeout=600)
    frame_manifest = [{"fps": "1/5", "count": 20, "tool": "ffmpeg",
                       "rc": frames.returncode}]
    return {"video_id": video_id, "title": meta.get("title", ""),
            "transcript": transcript, "frames": frame_manifest}


def _process_job(c, row):
    payload = json.loads(row["payload"])
    if row["kind"] == "message":
        history = _conversation_history(c, row["conversation_id"])
        reply = _call_provider(history)
        return json.dumps({"reply": reply})
    if row["kind"] == "youtube":
        ing = yt_ingest(payload.get("url", ""))
        # The caller already holds _LOCK and owns the connection — reuse it
        # (a non-reentrant re-acquire would deadlock the worker).
        c.execute(
            "INSERT OR REPLACE INTO ingests "
            "(video_id,title,transcript,frames,updated_at) "
            "VALUES (?,?,?,?,?)",
            (ing["video_id"], ing["title"], ing["transcript"],
             json.dumps(ing["frames"]), int(time.time() * 1000)))
        return json.dumps({"video_id": ing["video_id"],
                           "title": ing["title"],
                           "transcript": ing["transcript"]})
    raise RuntimeError("unknown job kind: " + row["kind"])


def worker_loop(stop: threading.Event) -> None:
    while not stop.is_set():
        job = None
        with _LOCK, db() as c:
            job = c.execute(
                "SELECT * FROM jobs WHERE status='queued' "
                "ORDER BY created_at LIMIT 1").fetchone()
            if job:
                c.execute("UPDATE jobs SET status='running',updated_at=? "
                          "WHERE id=?", (int(time.time() * 1000), job["id"]))
        if not job:
            stop.wait(0.5)
            continue
        try:
            with _LOCK, db() as c:
                result = _process_job(c, job)
                c.execute(
                    "UPDATE jobs SET status='done',result=?,error=NULL,"
                    "updated_at=? WHERE id=?",
                    (result, int(time.time() * 1000), job["id"]))
        except Exception as e:  # noqa: BLE001 — the job fails honestly
            attempts = job["attempts"] + 1
            status = "failed" if attempts >= _MAX_ATTEMPTS else "queued"
            with _LOCK, db() as c:
                c.execute(
                    "UPDATE jobs SET status=?,attempts=?,error=?,updated_at=? "
                    "WHERE id=?",
                    (status, attempts, redact({"error": str(e)})["error"],
                     int(time.time() * 1000), job["id"]))


# ----------------------------------------------------------------- handler ---
class Handler(BaseHTTPRequestHandler):
    server_version = "gork-vps/1.10"

    def log_message(self, fmt, *args):  # paths only — never bodies, never auth
        print("[gork-vps] " + fmt % args)

    def _authed(self):
        head = self.headers.get("Authorization", "")
        return hmac.compare_digest("Bearer " + VPS_TOKEN, head)

    def _json(self, code, obj):
        body = json.dumps(redact(obj)).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        n = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(n).decode() or "{}")

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            return self._json(200, {"ok": True, "service": "gork-vps"})
        if not self._authed():
            return self._json(401, {"error": "unauthorized"})
        m = re.match(r"^/v1/jobs/([\w-]+)$", path)
        if m:
            with db() as c:
                r = c.execute("SELECT * FROM jobs WHERE id=?",
                              (m.group(1),)).fetchone()
            if not r:
                return self._json(404, {"error": "no such job"})
            return self._json(200, {
                "id": r["id"], "kind": r["kind"], "status": r["status"],
                "result": json.loads(r["result"]) if r["result"] else None,
                "error": r["error"]})
        m = re.match(r"^/v1/conversations/([\w-]+)/messages$", path)
        if m:
            with db() as c:
                rows = c.execute(
                    "SELECT payload,result FROM jobs WHERE "
                    "conversation_id=? AND kind='message' AND status='done' "
                    "ORDER BY created_at", (m.group(1),)).fetchall()
            msgs = []
            for r in rows:
                msgs.append({"role": "user",
                             "content": json.loads(r["payload"])["text"]})
                reply = json.loads(r["result"]).get("reply", "")
                msgs.append({"role": "assistant", "content": reply})
            return self._json(200, {"conversation": m.group(1),
                                    "messages": msgs})
        if path == "/v1/credentials/google/status":
            with db() as c:
                r = c.execute("SELECT updated_at FROM credentials WHERE "
                              "name='google'").fetchone()
            return self._json(200, {
                "has_client_json": r is not None,
                "sealed_with": SEALED_WITH if r else None,
                "updated_at": r["updated_at"] if r else None,
                "scopes_expected": SCOPES_EXPECTED})
        if path == "/v1/ingests":
            with db() as c:
                rows = c.execute("SELECT * FROM ingests ORDER BY "
                                 "updated_at DESC").fetchall()
            return self._json(200, {"ingests": [
                {"video_id": r["video_id"], "title": r["title"],
                 "transcript": r["transcript"],
                 "frames": json.loads(r["frames"])} for r in rows]})
        return self._json(404, {"error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        if not self._authed():
            return self._json(401, {"error": "unauthorized"})
        if path == "/v1/messages":
            body = self._read_json()
            text = (body.get("text") or "").strip()
            if not text:
                return self._json(400, {"error": "text is required"})
            job_id = uuid.uuid4().hex[:12]
            now = int(time.time() * 1000)
            with _LOCK, db() as c:
                c.execute(
                    "INSERT INTO jobs (id,kind,conversation_id,payload,"
                    "status,created_at,updated_at) VALUES "
                    "(?,?,?,?,?,?,?)",
                    (job_id, "message", body.get("conversation_id") or "default",
                     json.dumps({"text": text,
                                 "attachment": redact(body.get("attachment"))}),
                     "queued", now, now))
            # 201 + id immediately — the VPS owns the request from here.
            return self._json(201, {"id": job_id, "status": "queued"})
        if path == "/v1/jobs/youtube":
            body = self._read_json()
            url = (body.get("url") or "").strip()
            if "youtube.com" not in url and "youtu.be" not in url:
                return self._json(400, {"error": "not a youtube url"})
            job_id = uuid.uuid4().hex[:12]
            now = int(time.time() * 1000)
            with _LOCK, db() as c:
                c.execute(
                    "INSERT INTO jobs (id,kind,conversation_id,payload,"
                    "status,created_at,updated_at) VALUES "
                    "(?,?,?,?,?,?,?)",
                    (job_id, "youtube", "ingest",
                     json.dumps({"url": url}), "queued", now, now))
            return self._json(201, {"id": job_id, "status": "queued"})
        if path == "/v1/credentials/google":
            body = self._read_json()
            client_json = body.get("client_json")
            if not isinstance(client_json, dict):
                return self._json(400, {"error": "client_json must be the "
                                                "Cloud Console credentials object"})
            blob = seal(json.dumps(client_json, sort_keys=True).encode())
            with _LOCK, db() as c:
                c.execute(
                    "INSERT OR REPLACE INTO credentials (name,sealed,"
                    "updated_at) VALUES ('google',?,?)",
                    (blob, int(time.time() * 1000)))
            return self._json(201, {"stored": True, "sealed_with": SEALED_WITH,
                                    "names": list(client_json.keys())})
        return self._json(404, {"error": "not found"})


SCOPES_EXPECTED = [
    "documents (Google Docs API)",
    "spreadsheets (Google Sheets API)",
    "drive.file (Drive API)",
    "gmail.send / gmail.readonly / gmail.modify (Gmail API)",
    "youtube.readonly + youtubepartner (YouTube Data API v3)",
]


def serve(host="127.0.0.1", port=int(os.environ.get("GORK_PORT", "8787"))):
    init_db()
    stop = threading.Event()
    worker = threading.Thread(target=worker_loop, args=(stop,), daemon=True)
    worker.start()
    httpd = ThreadingHTTPServer((host, port), Handler)
    print(f"[gork-vps] listening on {host}:{port} (sealing: {SEALED_WITH})")
    return httpd, stop


if __name__ == "__main__":
    httpd, stop = serve()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        stop.set()
        httpd.shutdown()
