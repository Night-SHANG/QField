#!/usr/bin/env python3
"""Live smoke test for the national TianDiTu WMTS basemap services.

The token is read only from TIANDITU_TK and is never printed. The fixed tile
covers the Yulin area at zoom 10, so the request exercises the same national
Web-Mercator services used by the Android app.
"""

from __future__ import annotations

import os
import sys
import urllib.error
import urllib.parse
import urllib.request

SERVICES = (
    ("vec_w", "vec"),
    ("cva_w", "cva"),
    ("img_w", "img"),
    ("cia_w", "cia"),
)

# Approx. Yulin, Shaanxi (109.734E, 38.285N) at Web-Mercator zoom 10.
TILE_MATRIX = 10
TILE_COL = 824
TILE_ROW = 393


def is_image(payload: bytes) -> bool:
    return (
        payload.startswith(b"\x89PNG\r\n\x1a\n")
        or payload.startswith(b"\xff\xd8\xff")
        or payload.startswith((b"GIF87a", b"GIF89a"))
        or (len(payload) >= 12 and payload[:4] == b"RIFF" and payload[8:12] == b"WEBP")
    )


def tile_url(service_name: str, layer_name: str, token: str) -> str:
    base = f"https://t0.tianditu.gov.cn/{service_name}/wmts"
    query = urllib.parse.urlencode(
        {
            "SERVICE": "WMTS",
            "REQUEST": "GetTile",
            "VERSION": "1.0.0",
            "LAYER": layer_name,
            "STYLE": "default",
            "TILEMATRIXSET": "w",
            "FORMAT": "tiles",
            "TILEMATRIX": str(TILE_MATRIX),
            # WMTS: x is column, y is row.
            "TILEROW": str(TILE_ROW),
            "TILECOL": str(TILE_COL),
            "tk": token,
        }
    )
    return f"{base}?{query}"


def main() -> int:
    token = os.environ.get("TIANDITU_TK", "").strip()
    if not token:
        print("ERROR: TIANDITU_TK is not configured", file=sys.stderr)
        return 2

    failures = 0
    for service_name, layer_name in SERVICES:
        request = urllib.request.Request(
            tile_url(service_name, layer_name, token),
            headers={
                "User-Agent": "QField-Waterworks-Tianditu-Smoke/1.0",
                "Accept": "image/*,*/*;q=0.8",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
                status = getattr(response, "status", 200)
                content_type = response.headers.get_content_type()
        except urllib.error.HTTPError as exc:
            # Never print exc.url: it contains the secret token.
            print(f"ERROR: {service_name} HTTP {exc.code}", file=sys.stderr)
            failures += 1
            continue
        except Exception as exc:
            print(f"ERROR: {service_name} request failed: {type(exc).__name__}: {exc}", file=sys.stderr)
            failures += 1
            continue

        if status != 200:
            print(f"ERROR: {service_name} returned HTTP {status}", file=sys.stderr)
            failures += 1
            continue

        if len(payload) < 100 or not is_image(payload):
            preview = payload[:80].decode("utf-8", errors="replace").replace("\n", " ")
            print(
                f"ERROR: {service_name} did not return a valid image "
                f"(content-type={content_type}, bytes={len(payload)}, preview={preview!r})",
                file=sys.stderr,
            )
            failures += 1
            continue

        print(f"OK: {service_name} {content_type} {len(payload)} bytes")

    if failures:
        print(f"TianDiTu WMTS smoke test failed: {failures} service(s)", file=sys.stderr)
        return 1

    print("TianDiTu WMTS smoke test passed for all four basemap services.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
