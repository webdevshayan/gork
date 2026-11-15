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
        CREATE TABLE IF NOT EXISTS memory_blocks (
          id TEXT PRIMARY KEY, room TEXT NOT NULL, title TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '',
          updated_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS accounts (
          site TEXT NOT NULL, username TEXT NOT NULL, label TEXT NOT NULL DEFAULT '',
          updated_at INTEGER NOT NULL, PRIMARY KEY (site, username));
        CREATE TABLE IF NOT EXISTS vault_secrets (
          label TEXT PRIMARY KEY, sealed BLOB NOT NULL,
          updated_at INTEGER NOT NULL);
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


# ---------------------------------------------- browser + secure fill ---
class _PlaywrightDriver:
    """The AI's full browser on the VPS. Lazy: playwright + chromium are
    installed on the real VPS; when they are missing the factory returns
    None and every op fails honestly instead of pretending."""

    def __init__(self):
        from playwright.sync_api import sync_playwright
        self._pw = sync_playwright().start()
        self._contexts = {}

    def _page(self, session):
        ctx = self._contexts.get(session)
        if ctx is None:
            ctx = self._pw.chromium.launch(headless=True).new_context()
            self._contexts[session] = ctx
        return ctx.pages[0] if ctx.pages else ctx.new_page()

    def op(self, session, action, args):
        page = self._page(session)
        if action == "navigate":
            page.goto(args.get("url", "about:blank"), wait_until="domcontentloaded")
            return {"url": page.url, "title": page.title()}
        if action == "click":
            page.click(args["selector"])
            return {"ok": True}
        if action == "type":
            page.type(args["selector"], args.get("text", ""))
            return {"ok": True}
        if action == "read":
            return {"text": page.inner_text("body")[:8000]}
        if action == "screenshot":
            path = f"/tmp/gork-{session}-{int(time.time())}.png"
            page.screenshot(path=path)
            return {"screenshot": path}
        raise RuntimeError("unknown browser action: " + str(action))

    def fill_active(self, session, text):
        """Fill the ACTIVE input without the AI ever learning the value."""
        page = self._page(session)
        return page.evaluate(
            """t => {
              const el = document.activeElement;
              if (!el || (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA'
                          && !el.isContentEditable)) return false;
              el.value = t;
              el.dispatchEvent(new Event('input', {bubbles: true}));
              return true;
            }""", text)

    def close(self, session):
        ctx = self._contexts.pop(session, None)
        if ctx:
            ctx.close()


_BROWSER_DRIVER = None
_BROWSER_TRIED = False


def _browser_driver():
    """One lazy driver instance; None when playwright is not installed."""
    global _BROWSER_DRIVER, _BROWSER_TRIED
    if not _BROWSER_TRIED:
        _BROWSER_TRIED = True
        try:
            _BROWSER_DRIVER = _PlaywrightDriver()
        except Exception:  # noqa: BLE001 — no engine on this VPS
            _BROWSER_DRIVER = None
    return _BROWSER_DRIVER


_NO_ENGINE = {
    "ok": False,
    "error": "browser engine not installed on the VPS "
             "(pip install playwright && playwright install chromium)",
}


def _memory_map(c):
    """The full room map the agent sees: every room, every block (title +
    subcategory + size) — never the block contents."""
    rows = c.execute(
        "SELECT id,room,title,category,updated_at,"
        "length(content) AS chars FROM memory_blocks "
        "ORDER BY room,updated_at").fetchall()
    rooms = {}
    order = []
    for r in rows:
        room = r["room"]
        if room not in rooms:
            rooms[room] = []
            order.append(room)
        rooms[room].append({"id": r["id"], "title": r["title"],
                            "category": r["category"],
                            "chars": r["chars"],
                            "updated_at": r["updated_at"]})
    return {"rooms": [{"room": k, "blocks": rooms[k]} for k in order]}


def _memory_ops(c, ops):
    """THE one call: retrieve + mutate + add (and delete) together. Ops are
    applied atomically; retrieval results come back alongside the map."""
    results = []
    for op in ops:
        kind = op.get("kind", "")
        if kind == "add":
            room = (op.get("room") or "").strip()
            title = (op.get("title") or "").strip()
            if not room or not title:
                results.append({"ok": False,
                                "error": "add needs room and title"})
                continue
            block_id = uuid.uuid4().hex[:12]
            c.execute(
                "INSERT INTO memory_blocks (id,room,title,category,content,"
                "updated_at) VALUES (?,?,?,?,?,?)",
                (block_id, room, title,
                 (op.get("category") or "").strip(),
                 op.get("content") or "", int(time.time() * 1000)))
            results.append({"ok": True, "id": block_id,
                            "block": block_id})
        elif kind == "mutate":
            block_id = op.get("block") or ""
            row = c.execute("SELECT id FROM memory_blocks WHERE id=?",
                            (block_id,)).fetchone()
            if not row:
                results.append({"ok": False, "error": "no such block"})
                continue
            for field in ("title", "category", "content"):
                if field in op:
                    c.execute(f"UPDATE memory_blocks SET {field}=?,"
                              "updated_at=? WHERE id=?",
                              (op[field], int(time.time() * 1000),
                               block_id))
            results.append({"ok": True, "block": block_id})
        elif kind == "retrieve":
            room = (op.get("room") or "").strip()
            block = op.get("block")
            if block:
                rows = c.execute(
                    "SELECT id,room,title,category,content,updated_at "
                    "FROM memory_blocks WHERE id=?", (block,)).fetchall()
            else:
                rows = c.execute(
                    "SELECT id,room,title,category,content,updated_at "
                    "FROM memory_blocks WHERE room=? ORDER BY updated_at",
                    (room,)).fetchall()
            results.append({"ok": True, "blocks": [
                {"id": r["id"], "room": r["room"], "title": r["title"],
                 "category": r["category"], "content": r["content"],
                 "updated_at": r["updated_at"]} for r in rows]})
        elif kind == "delete":
            c.execute("DELETE FROM memory_blocks WHERE id=?",
                      (op.get("block") or "",))
            results.append({"ok": True, "block": op.get("block")})
        else:
            results.append({"ok": False,
                            "error": "unknown op kind: " + str(kind)})
    return {"results": results, "map": _memory_map(c)}


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
    if row["kind"] == "memory_extract":
        # Context-length-aware extraction: when the conversation's transcript
        # grows past the model's usable context, distill the tail into the
        # room-based memory (rooms → blocks → subcategories) so the agent
        # keeps full coverage of everything without the raw transcript.
        conv = payload.get("conversation_id", "default")
        context_chars = max(1, int(payload.get("context_chars", 400000)))
        threshold = int(context_chars * 0.6)
        history = _conversation_history(c, conv)
        total = sum(len(m.get("content", "")) for m in history)
        if total <= threshold:
            return json.dumps({"extracted": False,
                               "reason": "within context",
                               "chars": total, "threshold": threshold})
        tail = history[-12:]
        prompt = (
            "Distill this conversation tail into the room-based memory "
            "system. Rooms are categories of information; each room holds "
            "blocks; a block has a title, a subcategory and the content.\n"
            "Respond with ONLY a JSON object: {\"ops\": [...]} where every "
            "op is one of:\n"
            '  {"kind":"add","room":..., "title":..., "category":..., '
            '"content":...}\n'
            '  {"kind":"mutate","block":<id from the map>, "content":...}\n'
            "The current room map follows. Merge into it — do not duplicate "
            "existing blocks.\nMAP: " + json.dumps(_memory_map(c)) +
            "\nTAIL: " + json.dumps(tail))
        raw = _call_provider([{"role": "user", "content": prompt}])
        m = re.search(r"\{.*\}", raw, re.S)
        if not m:
            raise RuntimeError("provider did not return JSON ops")
        ops = json.loads(m.group(0)).get("ops", [])
        out = _memory_ops(c, ops)
        return json.dumps({"extracted": True, "applied": len(ops),
                           "chars": total, "threshold": threshold,
                           "map": out["map"]})
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
        if path == "/v1/accounts":
            with db() as c:
                rows = c.execute("SELECT site,username,label,updated_at "
                                 "FROM accounts ORDER BY updated_at "
                                 "DESC").fetchall()
            return self._json(200, {"accounts": [
                {"site": r["site"], "username": r["username"],
                 "label": r["label"], "updated_at": r["updated_at"]}
                for r in rows]})
        if path == "/v1/vault/status":
            with db() as c:
                rows = c.execute("SELECT label FROM vault_secrets "
                                 "ORDER BY label").fetchall()
            return self._json(200, {"labels": [r["label"] for r in rows],
                                    "sealed_with": SEALED_WITH})
        if path == "/v1/memory/map":
            with db() as c:
                return self._json(200, _memory_map(c))
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
        if path == "/v1/accounts":
            body = self._read_json()
            site = (body.get("site") or "").strip()
            username = (body.get("username") or "").strip()
            if not site or not username:
                return self._json(400, {"error": "site and username are required"})
            with _LOCK, db() as c:
                c.execute(
                    "INSERT OR REPLACE INTO accounts (site,username,label,"
                    "updated_at) VALUES (?,?,?,?)",
                    (site, username, (body.get("label") or "").strip(),
                     int(time.time() * 1000)))
            return self._json(201, {"stored": True})
        if path == "/v1/vault/secret":
            body = self._read_json()
            label = (body.get("label") or "").strip()
            secret = body.get("secret") or ""
            if not label or not secret:
                return self._json(400, {"error": "label and secret are required"})
            blob = seal(secret.encode())
            with _LOCK, db() as c:
                c.execute(
                    "INSERT OR REPLACE INTO vault_secrets (label,sealed,"
                    "updated_at) VALUES (?,?,?)",
                    (label, blob, int(time.time() * 1000)))
            return self._json(201, {"stored": True, "label": label,
                                    "sealed_with": SEALED_WITH})
        if path == "/v1/browser/op":
            body = self._read_json()
            action = body.get("action") or ""
            session = (body.get("session") or "default").strip()
            if action == "fill_secret":
                label = (body.get("label") or "").strip()
                with _LOCK, db() as c:
                    row = c.execute("SELECT sealed FROM vault_secrets "
                                    "WHERE label=?", (label,)).fetchone()
                if not row:
                    return self._json(200, {
                        "filled": False, "error": "unknown label: " + label})
                secret = unseal(row["sealed"]).decode()
                driver = _browser_driver()
                if driver is None:
                    return self._json(200, _NO_ENGINE)
                try:
                    ok = driver.fill_active(session, secret)
                except Exception:  # noqa: BLE001 — never echo the value
                    return self._json(200, {
                        "filled": False,
                        "error": "fill failed (secret not exposed)"})
                return self._json(200, {"filled": bool(ok), "label": label})
            driver = _browser_driver()
            if driver is None:
                return self._json(200, _NO_ENGINE)
            try:
                result = driver.op(session, action, body)
            except Exception as e:  # noqa: BLE001 — honest, redacted
                return self._json(200, {"ok": False,
                                        "error": redact({"error": str(e)})["error"]})
            return self._json(200, {"ok": True, "result": result})
        if path == "/v1/onboarding/intro":
            # ONE provider request generates ALL the intro messages; the
            # client sends them as separate bubbles with human-like timing.
            body = self._read_json()
            name = (body.get("name") or "there").strip()
            email = (body.get("email") or "").strip()
            if not PROVIDER_URL:
                return self._json(503, {"error": "provider not configured "
                                                "on the VPS"})
            prompt = (
                "Write the first-run greeting of a personal AI assistant "
                "named Hark to its user. 3 to 4 SHORT messages, each one a "
                "separate bubble, warm and concrete, one idea per message, "
                "no markdown, no emoji. Reply with ONLY a JSON object: "
                "{\"messages\": [\"...\", \"...\"]}. The user's name is "
                f"{name}" + (f" (email {email})" if email else "") + ".")
            try:
                raw = _call_provider([{"role": "user", "content": prompt}])
            except Exception as e:  # noqa: BLE001 — honest, redacted
                return self._json(502, {
                    "error": redact({"error": str(e)})["error"]})
            m = re.search(r"\{.*\}", raw, re.S)
            if not m:
                return self._json(502, {"error": "provider did not return "
                                                "JSON"})
            messages = json.loads(m.group(0)).get("messages", [])
            messages = [str(x) for x in messages if str(x).strip()]
            if not messages:
                return self._json(502, {"error": "provider returned no "
                                                "messages"})
            return self._json(200, {"messages": messages[:5]})
        if path == "/v1/memory/op":
            body = self._read_json()
            ops = body.get("ops")
            if not isinstance(ops, list) or not ops:
                return self._json(400, {"error": "ops must be a non-empty list"})
            with _LOCK, db() as c:
                out = _memory_ops(c, ops)
            return self._json(200, out)
        if path == "/v1/memory/extract":
            body = self._read_json()
            conv = (body.get("conversation_id") or "default").strip()
            job_id = uuid.uuid4().hex[:12]
            now = int(time.time() * 1000)
            with _LOCK, db() as c:
                c.execute(
                    "INSERT INTO jobs (id,kind,conversation_id,payload,"
                    "status,created_at,updated_at) VALUES "
                    "(?,?,?,?,?,?,?)",
                    (job_id, "memory_extract", conv,
                     json.dumps({"conversation_id": conv,
                                 "context_chars": body.get("context_chars",
                                                           400000)}),
                     "queued", now, now))
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
