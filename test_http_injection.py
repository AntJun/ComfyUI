#!/usr/bin/env python3
"""
Test script to check for HTTP Response Header Injection vulnerability
"""

import asyncio
import aiohttp
from aiohttp import web, FormData
import os
import sys

async def test_header_injection():
    """Test if filename with CRLF can cause header injection"""

    print("[*] Testing HTTP Response Header Injection vulnerability...")
    print()

    # Test 1: Check if aiohttp web.Response allows CRLF in headers
    print("[Test 1] Direct header injection test")
    malicious_filename = "test\r\nX-Injected: malicious\r\n.png"

    try:
        headers = {"Content-Disposition": f'filename="{malicious_filename}"'}
        response = web.Response(body=b"test", headers=headers)
        print(f"  Filename: {repr(malicious_filename)}")
        print(f"  Headers: {response.headers}")
        print(f"  [!] Potential vulnerability: Headers accepted CRLF characters")
        print()
    except Exception as e:
        print(f"  [✓] Safe: Exception raised: {e}")
        print()

    # Test 2: Check what os.path.basename does with CRLF
    print("[Test 2] os.path.basename() with CRLF")
    test_filenames = [
        "normal.png",
        "test\r\nmalicious\r\n.png",
        "test\nmalicious.png",
        "../test.png",
    ]

    for fname in test_filenames:
        basename = os.path.basename(fname)
        print(f"  Input:  {repr(fname)}")
        print(f"  Output: {repr(basename)}")
        print()

    # Test 3: Simulate the actual server code path
    print("[Test 3] Simulating server code path")
    filename = "test\r\nX-Injected: pwned\r\n.png"
    filename = os.path.basename(filename)  # Like server.py:467

    print(f"  After basename: {repr(filename)}")

    # Try to create response like server.py:489
    try:
        response = web.Response(
            body=b"fake image data",
            content_type='image/png',
            headers={"Content-Disposition": f'filename="{filename}"'}
        )
        print(f"  Response headers: {dict(response.headers)}")

        # Check if header was injected
        if 'X-Injected' in response.headers:
            print(f"  [!!!] VULNERABILITY CONFIRMED: X-Injected header found!")
            print(f"  [!!!] Value: {response.headers['X-Injected']}")
        else:
            print(f"  [?] X-Injected header not found in response.headers dict")
            print(f"  [*] But raw Content-Disposition might still be vulnerable")
            print(f"  [*] Raw value: {response.headers.get('Content-Disposition')}")

        return True

    except Exception as e:
        print(f"  [✓] Safe: Exception raised: {type(e).__name__}: {e}")
        return False

if __name__ == "__main__":
    result = asyncio.run(test_header_injection())

    if result:
        print()
        print("="*70)
        print("POTENTIAL VULNERABILITY DETECTED")
        print("="*70)
        print("The application may be vulnerable to HTTP Response Header Injection")
        print("if filenames with CRLF characters can be uploaded.")
    else:
        print()
        print("="*70)
        print("NO VULNERABILITY DETECTED")
        print("="*70)
        print("aiohttp appears to sanitize headers properly.")
