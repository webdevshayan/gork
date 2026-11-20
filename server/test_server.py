#!/usr/bin/env python3
"""Server behavior tests: queue semantics, auth, redaction, credential
vault, YouTube ingestion (mocked yt-dlp/ffmpeg). Run: python3 test_server.py"""
import json
import os
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))
import gork_server as G  # noqa: E402

PORT = 18987
BASE = f'http://127.0.0.1:{PORT}'


def req(method, path, body=None, auth=True, token=None):
    headers = {'Content-Type': 'application/json'}
    if auth:
        headers['Authorization'] = 'Bearer ' + (token or G.VPS_TOKEN)
    r = urllib.request.Request(BASE + path, method=method,
                               data=json.dumps(body).encode() if body is not None else None,
                               headers=headers)
    try:
        with urllib.request.urlopen(r, timeout=10) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())


class ServerTests(unittest.TestCase):
    httpd = None
    stop = None

    @classmethod
    def setUpClass(cls):
        os.environ['GORK_VPS_TOKEN'] = 'test-token'
        G.VPS_TOKEN = 'test-token'
        G.DB_PATH = '/tmp/gork-server-test.sqlite3'
        if os.path.exists(G.DB_PATH):
            os.remove(G.DB_PATH)
        G.init_db()
        cls.httpd, cls.stop = G.serve('127.0.0.1', PORT)
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()
        time.sleep(0.3)

    @classmethod
    def tearDownClass(cls):
        cls.stop.set()
        cls.httpd.shutdown()

    def test_health_open_but_informative_only(self):
        st, body = req('GET', '/health', auth=False)
        self.assertEqual(st, 200)
        self.assertEqual(body['service'], 'gork-vps')

    def test_auth_required_on_v1(self):
        st, _ = req('GET', '/v1/jobs/x', auth=False)
        self.assertEqual(st, 401)
        st, _ = req('GET', '/v1/jobs/x', auth=True, token='wrong')
        self.assertEqual(st, 401)

    def test_message_job_lifecycle_honest_failure(self):
        st, job = req('POST', '/v1/messages',
                      {'conversation_id': 'c1', 'text': 'hi'})
        self.assertEqual(st, 201)
        jid = job['id']
        st, r = req('GET', f'/v1/jobs/{jid}')
        self.assertIn(r['status'], ('queued', 'running', 'failed'))
        # provider not configured → retries then honest failure
        deadline = time.time() + 15
        while time.time() < deadline:
            _, r = req('GET', f'/v1/jobs/{jid}')
            if r['status'] == 'failed':
                break
            time.sleep(0.3)
        self.assertEqual(r['status'], 'failed')
        self.assertIn('provider not configured', r['error'])

    def test_no_cancel_endpoint_exists(self):
        st, _ = req('POST', '/v1/jobs/some-id/cancel', {})
        self.assertEqual(st, 404, 'the VPS must not offer cancellation')

    def test_credentials_sealed_never_echoed(self):
        secret = {'installed': {'client_id': 'abc',
                                'client_secret': 'SUPERSECRET-X'}}
        st, r = req('POST', '/v1/credentials/google', {'client_json': secret})
        self.assertEqual(st, 201)
        self.assertNotIn('SUPERSECRET-X', json.dumps(r))
        st, status = req('GET', '/v1/credentials/google/status')
        self.assertTrue(status['has_client_json'])
        self.assertNotIn('SUPERSECRET-X', json.dumps(status))
        # at rest the blob is sealed
        import sqlite3
        conn = sqlite3.connect(G.DB_PATH)
        row = conn.execute(
            "SELECT sealed FROM credentials WHERE name='google'").fetchone()
        conn.close()
        self.assertNotIn(b'SUPERSECRET-X', bytes(row[0]))

    def test_redact_helper(self):
        out = G.redact({'client_secret': 'A', 'nested': {'api_key': 'B',
                                                         'fine': 1}})
        self.assertEqual(out['client_secret'], '[REDACTED]')
        self.assertEqual(out['nested']['api_key'], '[REDACTED]')
        self.assertEqual(out['nested']['fine'], 1)

    def test_seal_roundtrip(self):
        blob = G.seal(b'roundtrip-payload')
        self.assertEqual(G.unseal(blob), b'roundtrip-payload')
        blob2 = G.seal(b'roundtrip-payload')
        self.assertNotEqual(blob, blob2, 'sealing must be randomized')
        with self.assertRaises(Exception):
            G.unseal(blob[:-5] + b'\x00' * 5)  # tamper → must fail

    def test_youtube_job_rejects_non_youtube(self):
        st, _ = req('POST', '/v1/jobs/youtube', {'url': 'https://vimeo.com/x'})
        self.assertEqual(st, 400)

    def test_youtube_ingest_with_mocked_tools(self):
        meta = {'id': 'dQw4w9WgXcQ', 'title': 'Test video',
                'filepath': '/tmp/v.mp4'}
        fake_frames = type('R', (), {'returncode': 0})()
        def fake_run(cmd, **kw):
            if cmd[0] == 'yt-dlp':
                return type('R', (), {'stdout': json.dumps(meta).encode(),
                                      'stderr': b''})()
            if cmd[0] == 'ffmpeg':
                return fake_frames
            raise AssertionError(cmd[0])
        with patch('subprocess.run', side_effect=fake_run):
            result = G.yt_ingest('https://youtu.be/dQw4w9WgXcQ')
        self.assertEqual(result['video_id'], 'dQw4w9WgXcQ')
        self.assertEqual(result['title'], 'Test video')
        self.assertEqual(result['frames'][0]['tool'], 'ffmpeg')

    def test_youtube_job_via_queue_mocked(self):
        # full queue path with mocked yt_ingest
        def fake_ingest(url):
            return {'video_id': 'abc123', 'title': 'queued ingest',
                    'transcript': 'transcript-available', 'frames': []}
        with patch.object(G, 'yt_ingest', side_effect=fake_ingest):
            st, job = req('POST', '/v1/jobs/youtube',
                          {'url': 'https://youtube.com/watch?v=abc123'})
            self.assertEqual(st, 201)
            jid = job['id']
            deadline = time.time() + 10
            while time.time() < deadline:
                _, r = req('GET', f'/v1/jobs/{jid}')
                if r['status'] == 'done':
                    break
                time.sleep(0.2)
            self.assertEqual(r['status'], 'done')
            self.assertEqual(r['result']['video_id'], 'abc123')
            # the ingest index has it
            st, ing = req('GET', '/v1/ingests')
            self.assertTrue(any(i['video_id'] == 'abc123'
                                for i in ing['ingests']))
class MemoryRoomsTests(unittest.TestCase):
    """Movement 51 — room-based memory: rooms → blocks → subcategories.
    Retrieval, mutation and adding happen in ONE call (/v1/memory/op);
    the map endpoint gives the agent full room/block context without ever
    dumping every block's content."""

    @classmethod
    def setUpClass(cls):
        global BASE
        cls._prev_base = BASE
        BASE = f'http://127.0.0.1:18988'
        cls._prev_db = G.DB_PATH
        os.environ['GORK_VPS_TOKEN'] = 'test-token'
        G.VPS_TOKEN = 'test-token'
        G.DB_PATH = '/tmp/gork-memory-test.sqlite3'
        if os.path.exists(G.DB_PATH):
            os.remove(G.DB_PATH)
        G.init_db()
        cls.httpd, cls.stop = G.serve('127.0.0.1', 18988)
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()
        time.sleep(0.3)

    @classmethod
    def tearDownClass(cls):
        global BASE
        cls.stop.set()
        cls.httpd.shutdown()
        G.DB_PATH = cls._prev_db
        BASE = cls._prev_base

    def setUp(self):
        with G._LOCK, G.db() as c:
            c.execute("DELETE FROM memory_blocks")

    def _wait_done(self, jid, timeout=10):
        deadline = time.time() + timeout
        while time.time() < deadline:
            _, r = req('GET', f'/v1/jobs/{jid}')
            if r['status'] in ('done', 'failed'):
                return r
            time.sleep(0.1)
        return r

    def test_map_starts_empty_and_needs_auth(self):
        st, _ = req('GET', '/v1/memory/map', auth=False)
        self.assertEqual(st, 401)
        st, body = req('GET', '/v1/memory/map')
        self.assertEqual(st, 200)
        self.assertEqual(body['rooms'], [])

    def test_one_call_adds_retrieves_and_mutates(self):
        st, out = req('POST', '/v1/memory/op', {'ops': [
            {'kind': 'add', 'room': 'Work', 'title': 'Taleem ERP',
             'category': 'projects', 'content': 'Taleem ERP ships Friday.'},
            {'kind': 'retrieve', 'room': 'Work'},
        ]})
        self.assertEqual(st, 200)
        self.assertEqual(len(out['results']), 2)
        self.assertTrue(out['results'][0]['ok'])
        self.assertIn('Taleem ERP', out['map']['rooms'][0]['blocks'][0]['title'])
        blocks = out['results'][1]['blocks']
        self.assertEqual(len(blocks), 1)
        block_id = blocks[0]['id']

        # Second ONE-call round: mutate the block and retrieve it back.
        st, out = req('POST', '/v1/memory/op', {'ops': [
            {'kind': 'mutate', 'block': block_id,
             'content': 'Taleem ERP shipped. Next: onboarding.'},
            {'kind': 'retrieve', 'room': 'Work'},
        ]})
        self.assertEqual(st, 200)
        got = out['results'][1]['blocks']
        self.assertEqual(got[0]['content'],
                         'Taleem ERP shipped. Next: onboarding.')
        self.assertEqual(got[0]['title'], 'Taleem ERP')
        self.assertEqual(got[0]['category'], 'projects')

    def test_map_shows_rooms_and_blocks_but_never_content(self):
        req('POST', '/v1/memory/op', {'ops': [
            {'kind': 'add', 'room': 'Personal', 'title': 'Birthday',
             'category': 'dates', 'content': 'Dec 26'},
            {'kind': 'add', 'room': 'Personal', 'title': 'Pet',
             'category': 'family', 'content': 'Max the dog'},
        ]})
        st, body = req('GET', '/v1/memory/map')
        self.assertEqual(st, 200)
        rooms = {r['room']: r for r in body['rooms']}
        self.assertIn('Personal', rooms)
        titles = [b['title'] for b in rooms['Personal']['blocks']]
        self.assertEqual(titles, ['Birthday', 'Pet'])
        for b in rooms['Personal']['blocks']:
            self.assertNotIn('content', b,
                             'the map carries titles, never block content')
            self.assertIn('chars', b)

    def test_delete_op_and_unknown_room(self):
        st, out = req('POST', '/v1/memory/op', {'ops': [
            {'kind': 'add', 'room': 'R', 'title': 'T', 'category': 'c',
             'content': 'x'},
        ]})
        block_id = out['results'][0]['id']
        st, out = req('POST', '/v1/memory/op', {'ops': [
            {'kind': 'delete', 'block': block_id},
            {'kind': 'retrieve', 'room': 'Missing'},
        ]})
        self.assertEqual(st, 200)
        self.assertTrue(out['results'][0]['ok'])
        self.assertEqual(out['results'][1]['blocks'], [])

    def test_extract_within_context_is_a_noop(self):
        st, job = req('POST', '/v1/messages',
                      {'conversation_id': 'mem-conv', 'text': 'tiny talk'})
        self.assertEqual(st, 201)
        st, enq = req('POST', '/v1/memory/extract',
                      {'conversation_id': 'mem-conv',
                       'context_chars': 1000000})
        self.assertEqual(st, 201)
        r = self._wait_done(enq['id'])
        self.assertEqual(r['status'], 'done')
        self.assertFalse(r['result']['extracted'])

    def test_extract_runs_provider_and_applies_ops(self):
        # Enough history to cross the threshold, a stub provider that
        # returns memory ops as JSON, then verify the rooms update.
        with G._LOCK, G.db() as c:
            now = int(time.time() * 1000)
            for i in range(4):
                c.execute(
                    "INSERT INTO jobs (id,kind,conversation_id,payload,"
                    "status,created_at,updated_at) VALUES "
                    "(?,?,?,?,?,?,?)",
                    (f'ext{i}', 'message', 'big-conv',
                     json.dumps({'text': 'fact ' * 600}), 'done', now, now))
            c.execute(
                "UPDATE jobs SET result=? WHERE id='ext0'",
                (json.dumps({'reply': 'reply ' * 600}),))
        import urllib.request as _u
        with patch.object(G, '_call_provider',
                          return_value=json.dumps({'ops': [
                              {'kind': 'add', 'room': 'Work',
                               'title': 'From extraction',
                               'category': 'auto',
                               'content': 'extracted memory block'}]})):
            st, enq = req('POST', '/v1/memory/extract',
                          {'conversation_id': 'big-conv',
                           'context_chars': 4000})
            self.assertEqual(st, 201)
            # The worker runs in its own thread — poll while the stub is
            # still patched, or it hits the real (unconfigured) provider.
            r = self._wait_done(enq['id'])
        self.assertTrue(r['status'] == 'done', r.get('error'))
        self.assertTrue(r['result']['extracted'])
        st, body = req('GET', '/v1/memory/map')
        rooms = {x['room']: x for x in body['rooms']}
        self.assertIn('Work', rooms)
        titles = [b['title'] for b in rooms['Work']['blocks']]
        self.assertIn('From extraction', titles)


class BrowserAccountsTests(unittest.TestCase):
    """Movement 52 — the AI's full browser on the VPS + the accounts screen
    data + the secure paste-fill protocol: the AI asks for a LABEL, the VPS
    fills the active input from the sealed vault, and the secret NEVER
    appears in any response, log or error — even if the site is insecure."""

    @classmethod
    def setUpClass(cls):
        global BASE
        cls._prev_base = BASE
        BASE = 'http://127.0.0.1:18989'
        cls._prev_db = G.DB_PATH
        os.environ['GORK_VPS_TOKEN'] = 'test-token'
        G.VPS_TOKEN = 'test-token'
        G.DB_PATH = '/tmp/gork-browser-test.sqlite3'
        if os.path.exists(G.DB_PATH):
            os.remove(G.DB_PATH)
        G.init_db()
        cls.httpd, cls.stop = G.serve('127.0.0.1', 18989)
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()
        time.sleep(0.3)

    @classmethod
    def tearDownClass(cls):
        global BASE
        cls.stop.set()
        cls.httpd.shutdown()
        G.DB_PATH = cls._prev_db
        BASE = cls._prev_base

    def test_accounts_recorded_and_never_echo_secrets(self):
        st, _ = req('POST', '/v1/accounts', {
            'site': 'mail.google.com', 'username': 'shayanalibuilds@gmail.com',
            'label': 'gmail-main'})
        self.assertEqual(st, 201)
        st, body = req('GET', '/v1/accounts')
        self.assertEqual(st, 200)
        acct = [a for a in body['accounts']
                if a['site'] == 'mail.google.com'][0]
        self.assertEqual(acct['username'], 'shayanalibuilds@gmail.com')
        self.assertNotIn('password', json.dumps(body).lower(),
                         'the accounts list never carries secrets')

    def test_sealed_secret_never_reads_back(self):
        st, out = req('POST', '/v1/vault/secret',
                      {'label': 'gmail-main', 'secret': 'hunter2-secret'})
        self.assertEqual(st, 201)
        self.assertTrue(out['stored'])
        self.assertNotIn('hunter2-secret', json.dumps(out))
        st, body = req('GET', '/v1/vault/status')
        self.assertEqual(st, 200)
        self.assertIn('gmail-main', body['labels'])
        self.assertNotIn('hunter2-secret', json.dumps(body))

    def test_fill_secret_fills_active_input_secret_never_returned(self):
        req('POST', '/v1/vault/secret',
            {'label': 'mail-pass', 'secret': 'top-secret-value'})
        # Mock the browser driver: record what was typed, return success.
        captured = {}

        class FakeDriver:
            def fill_active(self, session, text):
                captured['text'] = text
                return True

            def op(self, session, action, args):
                return {'acted': action}

        with patch.object(G, '_browser_driver', return_value=FakeDriver()):
            st, out = req('POST', '/v1/browser/op', {
                'session': 's1', 'action': 'fill_secret',
                'label': 'mail-pass'})
        self.assertEqual(st, 200)
        self.assertTrue(out['filled'])
        self.assertEqual(captured['text'], 'top-secret-value',
                         'the driver got the real value')
        self.assertNotIn('top-secret-value', json.dumps(out),
                         'the AI-facing response never carries the secret')

    def test_browser_op_without_engine_fails_honestly(self):
        # Simulate a VPS with no browser engine at all: the factory must
        # resolve to None (Movement 69.1 — no cache flag left to patch).
        with patch.object(G, '_browser_driver', return_value=None):
            st, out = req('POST', '/v1/browser/op',
                          {'session': 's1', 'action': 'navigate',
                           'url': 'https://example.com'})
        self.assertEqual(st, 200)
        self.assertFalse(out.get('ok', True))
        self.assertIn('agent-browser', out.get('error', ''))
        self.assertIn('daemon', out.get('error', ''),
                      'points Termux hosts at the built-in fallback')

    def test_fill_secret_unknown_label_is_rejected(self):
        class FakeDriver:
            def fill_active(self, session, text):
                return True

        with patch.object(G, '_browser_driver', return_value=FakeDriver()):
            st, out = req('POST', '/v1/browser/op',
                          {'session': 's1', 'action': 'fill_secret',
                           'label': 'does-not-exist'})
        self.assertEqual(st, 200)
        self.assertFalse(out.get('filled', True))
        self.assertIn('unknown', out.get('error', '').lower())


class IntroTests(unittest.TestCase):
    """Movement 53 — the intro messages are generated in ONE provider
    request on the VPS and returned as an array; the client then sends
    them as separate bubbles with human-like timing."""

    @classmethod
    def setUpClass(cls):
        global BASE
        cls._prev_base = BASE
        BASE = 'http://127.0.0.1:18990'
        cls._prev_db = G.DB_PATH
        os.environ['GORK_VPS_TOKEN'] = 'test-token'
        G.VPS_TOKEN = 'test-token'
        G.DB_PATH = '/tmp/gork-intro-test.sqlite3'
        if os.path.exists(G.DB_PATH):
            os.remove(G.DB_PATH)
        G.init_db()
        cls.httpd, cls.stop = G.serve('127.0.0.1', 18990)
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()
        time.sleep(0.3)

    @classmethod
    def tearDownClass(cls):
        global BASE
        cls.stop.set()
        cls.httpd.shutdown()
        G.DB_PATH = cls._prev_db
        BASE = cls._prev_base

    def test_intro_generated_in_one_call(self):
        with patch.object(G, 'PROVIDER_URL', 'https://fake-provider'), \
             patch.object(G, '_call_provider', return_value=json.dumps({
                 'messages': ['Hey Shayan, I am Gork.',
                              'One idea per bubble.']})):
            st, body = req('POST', '/v1/onboarding/intro',
                           {'name': 'Shayan', 'email': 's@x.com'})
        self.assertEqual(st, 200)
        self.assertEqual(body['messages'],
                         ['Hey Shayan, I am Gork.', 'One idea per bubble.'])

    def test_intro_without_provider_is_honest(self):
        with patch.object(G, '_browser_driver', return_value=None):
            pass  # keep patch import used; provider env untouched
        G.PROVIDER_URL_BACKUP = G.PROVIDER_URL
        G.PROVIDER_URL = ''
        try:
            st, body = req('POST', '/v1/onboarding/intro', {'name': 'S'})
            self.assertEqual(st, 503)
            self.assertIn('provider', body['error'])
        finally:
            G.PROVIDER_URL = G.PROVIDER_URL_BACKUP


class DaemonFallbackTest(unittest.TestCase):
    """Movement 69.1 — no agent-browser binary (Termux)? The server proxies
    browser ops to the daemon's built-in CDP browser, mapping verbs."""

    def _driver(self):
        d = G._AgentBrowserDriver.__new__(G._AgentBrowserDriver)
        d._daemon = True
        return d

    def test_slide_maps_to_daemon_drag(self):
        seen = {}

        def fake(action, args):
            seen['action'] = action
            seen['args'] = args
            return {'state': 'ok'}

        d = self._driver()
        with patch.object(d, '_daemon_op', side_effect=fake):
            out = d.op('default', 'slide',
                       {'handle': '@e1', 'target': '@e2'})
        self.assertEqual(seen['action'], 'drag')
        self.assertEqual(seen['args']['selector'], '@e1')
        self.assertEqual(seen['args']['target'], '@e2')
        self.assertEqual(out, {'state': 'ok'})

    def test_fill_maps_to_daemon_type(self):
        seen = {}

        def fake(action, args):
            seen['action'] = action
            return {}

        d = self._driver()
        with patch.object(d, '_daemon_op', side_effect=fake):
            d.op('default', 'fill', {'selector': '@e3', 'text': 'hi'})
        self.assertEqual(seen['action'], 'type')

    def test_unmapped_action_is_honest(self):
        d = self._driver()
        with self.assertRaises(RuntimeError) as ctx:
            d.op('default', 'network', {})
        self.assertIn('agent-browser-only', str(ctx.exception))


if __name__ == '__main__':
    unittest.main(verbosity=2)
