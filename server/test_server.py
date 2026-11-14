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


if __name__ == '__main__':
    unittest.main(verbosity=2)
