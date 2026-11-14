# Google Cloud Console setup for gork — step by step

This walks you through creating the Google app that powers gork's Docs,
Sheets, Drive, Gmail and YouTube (frame-by-frame + transcript) features,
and getting its `credentials.json` onto your VPS safely.

The rule the whole design follows: **your secrets never leave the VPS
vault once uploaded, and the VPS never shows them to anyone** — not the
app, not logs, not the API. Status only.

---

## 1. Create the project (2 minutes)

1. Open <https://console.cloud.google.com> and sign in with the Google
   account you want gork to act as.
2. Top bar → project picker → **New project**.
3. Name: `gork-personal` (anything works). Click **Create**.
4. Make sure the new project is selected in the top bar before continuing.

## 2. Enable every product gork uses (3 minutes)

Open **APIs & Services → Library** (left menu) and enable each of these
(click → Enable):

| Product | What gork does with it |
|---|---|
| **Google Docs API** | read/write documents the assistant works in |
| **Google Sheets API** | read/write spreadsheets |
| **Google Drive API** | list, read and upload files (scope `drive.file` — only files gork created) |
| **Gmail API** | read inbox, send on your behalf (scopes `gmail.readonly`, `gmail.send`, `gmail.modify`) |
| **YouTube Data API v3** | video metadata, captions/transcript, comments |

The YouTube **frame-by-frame** pipeline (`yt-dlp` + `ffmpeg` on the VPS)
does not need extra APIs — it works on public video URLs and pairs with
the transcript from the Data API.

## 3. Configure the OAuth consent screen (5 minutes)

1. **APIs & Services → OAuth consent screen**.
2. User type **External** → Create.
3. App name `gork`, your email as support email and developer contact.
4. **Scopes** step → Add or remove scopes — add exactly these:
   - `.../auth/documents`
   - `.../auth/spreadsheets`
   - `.../auth/drive.file`
   - `.../auth/gmail.readonly`, `.../auth/gmail.send`, `.../auth/gmail.modify`
   - `.../auth/youtube.readonly`
   - `.../auth/youtube.force-ssl`
5. **Test users** step → add your own Gmail address (while the app is in
   testing, only these users can sign in — that is exactly what you want).

## 4. Create the OAuth client (3 minutes)

1. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
2. Application type: **Web application** (this one is for the VPS).
3. Authorized redirect URIs: add `http://localhost:8080/` and, if you
   know the VPS domain, `https://<your-vps-domain>/oauth/callback`.
4. **Create** → in the dialog click **Download JSON** — this is your
   `credentials.json` (it has an `installed` or `web` block).
5. Repeat with type **Android** if you ever want in-app Google sign-in;
   package name `dev.shayan.gork`, SHA-1 blank for now.

## 5. (Optional, server-to-server) Service account

For YouTube ingestion and Drive jobs that must run with no user present:

1. **Credentials → Create credentials → Service account** → name `gork-vps`.
2. Open it → **Keys → Add key → Create new key → JSON** → download.
3. This file is a different kind of `credentials.json` (it contains
   `private_key` and `client_email`). gork accepts both kinds.

## 6. Upload the credentials to the VPS (1 minute)

In the app: **Menu → Google → Google Cloud Console → Upload
credentials.json**. The app:

1. checks the file is really Cloud Console credentials (OAuth client or
   service account),
2. POSTs it once to the VPS over your configured VPS URL + token,
3. shows the verdict — *"Credentials sealed on the VPS"* — which is a
   **status boolean**; the server does not have an endpoint that returns
   the secret, ever.

## 7. Set up the VPS itself (one time)

```bash
# on the VPS
python3 server/gork_server.py          # stdlib only; or pip install cryptography for Fernet sealing
```

Environment variables:

| Variable | Meaning |
|---|---|
| `GORK_VPS_TOKEN` | the bearer token every `/v1/*` call must present |
| `GORK_DB` | SQLite path (jobs + sealed credentials) |
| `GORK_PORT` | listen port (default 8787) |
| `GORK_PROVIDER_URL` / `GORK_PROVIDER_KEY` | OpenAI-compatible provider for chat jobs |
| `GORK_PROVIDER_MODEL` | model id, default `gpt-4o-mini` |

And in the app **Menu → Security → VPS**: set the URL and the same token
(stored in the phone's keystore, never in prefs).

For a persistent run: `nohup python3 server/gork_server.py &` or the
systemd unit pattern (Restart=always).

## 8. How the secrets are protected

- Uploaded JSON is **encrypted at rest** (Fernet/AES when the
  `cryptography` package is present, otherwise an HMAC-SHA256 keystream
  seal — both authenticated).
- Every `/v1/*` request needs the bearer token; `/health` is the only
  open endpoint and returns nothing.
- Redaction is defense in depth: any dictionary with secret-shaped keys
  (`client_secret`, `private_key`, `*_token`, `api_key`…) has those
  values replaced with `[REDACTED]` before echoing, logging or storing
  errors.
- The client can only ask *"is it stored?"* — `GET /v1/credentials/google/status`
  answers `has_client_json: true/false` + the seal type. There is no
  read-back endpoint.
- Server logs contain method + path only — never bodies, never auth
  headers.

## 9. YouTube ingestion on the VPS

`POST /v1/jobs/youtube` with `{"url": "https://youtu.be/…"}` queues an
ingest job. On the VPS it runs `yt-dlp` for metadata + transcript and
`ffmpeg` (1 frame / 5 s, first 20) for the frame manifest, storing the
result in SQLite. Install the tools on the VPS:
`pip install yt-dlp && apt install ffmpeg` (or the distro equivalent).
Pull results with `GET /v1/ingests` — the assistant then "watches" the
video: transcript + frame manifest as its context.

## 10. Checklist

- [ ] Project created
- [ ] Docs, Sheets, Drive, Gmail, YouTube Data APIs enabled
- [ ] Consent screen scopes added, your account added as test user
- [ ] OAuth client (web) created, JSON downloaded
- [ ] (optional) service account key downloaded
- [ ] VPS reachable, `GORK_VPS_TOKEN` set, app configured with URL+token
- [ ] credentials.json uploaded — status shows *sealed on the VPS*
- [ ] yt-dlp + ffmpeg present on the VPS for YouTube ingestion
