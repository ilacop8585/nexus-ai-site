#!/usr/bin/env python3
"""Bounded, read-only security smoke for NEXUS Word public perimeter.

Owner-authorized smoke test. No account creation, credential retrieval,
provider completion, paid job, destructive payload, brute force, or crawling.
Requires Python 3 standard library and external network access.
"""
import json
import sys
import time
import urllib.error
import urllib.request

SITE = "https://nexusword.it/"
CONNECTORS = "https://nexus-connectors.ilario-coppola.workers.dev/connections"
CHAT = "https://nexus-ai-router.ilario-coppola.workers.dev/chat"
FOREIGN_ORIGIN = "https://external-security-audit.invalid"
UA = "Mozilla/5.0 (compatible; NEXUS-Authorized-SecuritySmoke/1.0)"
results = []

def fetch(name, url, method="GET", headers=None, body=None, expected=None, origin=None):
    request = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={"User-Agent": UA, **(headers or {})},
    )
    try:
        with urllib.request.urlopen(request, timeout=9) as response:
            status, h, final_url = response.status, response.headers, response.url
            response.read(160)
    except urllib.error.HTTPError as error:
        status, h, final_url = error.code, error.headers, error.url
        error.read(160)
    except Exception as error:
        results.append({"name": name, "pass": False, "error": type(error).__name__})
        return
    allowed = h.get("Access-Control-Allow-Origin")
    success = (status == expected if expected is not None else True)
    if origin is not None:
        success = success and (allowed == origin)
    results.append({"name": name, "http": status, "pass": success,
                    "cors": allowed or "(none)"})
    return h, final_url

main = fetch("main_https", SITE, expected=200)
if main:
    h, final_url = main
    results[-1]["pass"] = results[-1]["pass"] and final_url.startswith("https://")
    results.append({
        "name": "header_hardening_advisory",
        "pass": None,
        "missing": [name for name in (
            "Strict-Transport-Security", "Content-Security-Policy",
            "X-Frame-Options", "X-Content-Type-Options", "Referrer-Policy",
        ) if h.get(name) is None],
    })

tests = [
    ("connectors_anonymous_denied", CONNECTORS, "GET", {}, None, 401, None),
    ("connectors_invalid_token_denied", CONNECTORS, "GET",
        {"Authorization": "Bearer invalid-security-qa-token"}, None, 401, None),
    ("ai_chat_anonymous_denied", CHAT, "POST",
        {"Origin": SITE.rstrip("/"), "Content-Type": "application/json"}, b"{}", 401, SITE.rstrip("/")),
    ("ai_chat_invalid_token_denied", CHAT, "POST",
        {"Origin": SITE.rstrip("/"), "Content-Type": "application/json",
         "Authorization": "Bearer invalid-security-qa-token"}, b"{}", 401, SITE.rstrip("/")),
    ("connectors_foreign_origin_denied", CONNECTORS, "OPTIONS",
        {"Origin": FOREIGN_ORIGIN, "Access-Control-Request-Method": "GET",
         "Access-Control-Request-Headers": "authorization"}, None, 403, None),
    ("ai_chat_foreign_origin_denied", CHAT, "OPTIONS",
        {"Origin": FOREIGN_ORIGIN, "Access-Control-Request-Method": "POST",
         "Access-Control-Request-Headers": "authorization,content-type"}, None, 403, None),
    ("ai_chat_site_origin_allowed", CHAT, "OPTIONS",
        {"Origin": SITE.rstrip("/"), "Access-Control-Request-Method": "POST",
         "Access-Control-Request-Headers": "authorization,content-type"}, None, 204, SITE.rstrip("/")),
]
for name, url, method, headers, body, status, expected_cors in tests:
    fetch(name, url, method, headers, body, status, expected_cors)
    time.sleep(0.25)  # explicitly low-rate, bounded
print(json.dumps({"scope": "NEXUS Word perimeter only", "results": results},
                 ensure_ascii=False, indent=2))
sys.exit(0 if all(entry["pass"] is not False for entry in results) else 1)
