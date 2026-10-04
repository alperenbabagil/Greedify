#!/usr/bin/env python3
"""Throwaway (Task 1 checks only): prints a Spotify user access token via PKCE + loopback.

Usage: python3 scripts/spike/token.py <CLIENT_ID>
Needs http://127.0.0.1:8898/callback registered as a redirect URI in the Spotify dashboard.
"""
import base64, hashlib, http.server, json, secrets, sys, urllib.parse, urllib.request, webbrowser

CLIENT_ID = sys.argv[1]
REDIRECT = "http://127.0.0.1:8898/callback"
SCOPES = "user-read-playback-state user-modify-playback-state playlist-read-private"

verifier = secrets.token_urlsafe(64)[:64]
challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
state = secrets.token_urlsafe(16)
url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode(dict(
    client_id=CLIENT_ID, response_type="code", redirect_uri=REDIRECT, code_challenge_method="S256",
    code_challenge=challenge, state=state, scope=SCOPES))

result = {}

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        result["code"] = query.get("code", [None])[0]
        result["state"] = query.get("state", [None])[0]
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Done. You can close this tab.")

    def log_message(self, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 8898), Handler)
webbrowser.open(url)
server.handle_request()
if result.get("state") != state or not result.get("code"):
    sys.exit("Login failed or state mismatch")
body = urllib.parse.urlencode(dict(grant_type="authorization_code", code=result["code"], redirect_uri=REDIRECT,
                                   client_id=CLIENT_ID, code_verifier=verifier)).encode()
token = json.load(urllib.request.urlopen(urllib.request.Request("https://accounts.spotify.com/api/token", data=body)))
print(token["access_token"])
