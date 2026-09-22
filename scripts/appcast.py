#!/usr/bin/env python3
"""Prepend a release item to the Sparkle appcast (creates the file on first use)."""
import argparse
import datetime
import html
import re
from pathlib import Path

HEAD = '''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Damla</title>
    <description>Damla güncellemeleri</description>
    <language>tr</language>
'''
TAIL = '''  </channel>
</rss>
'''


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("appcast", type=Path)
    for name in ["--version", "--build", "--url", "--length", "--signature", "--min-os"]:
        p.add_argument(name, required=True)
    p.add_argument("--notes", type=Path)
    a = p.parse_args()
    notes = a.notes.read_text().strip() if a.notes and a.notes.exists() else ""
    paragraphs = [f"<p>{html.escape(line)}</p>" for line in notes.splitlines() if line.strip()]
    item = f'''    <item>
      <title>Damla {a.version}</title>
      <pubDate>{datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")}</pubDate>
      <sparkle:version>{a.build}</sparkle:version>
      <sparkle:shortVersionString>{a.version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{a.min_os}</sparkle:minimumSystemVersion>
      <description><![CDATA[{"".join(paragraphs)}]]></description>
      <enclosure url="{a.url}" length="{a.length}" type="application/octet-stream" sparkle:edSignature="{a.signature}"/>
    </item>
'''
    existing = a.appcast.read_text() if a.appcast.exists() else HEAD + TAIL
    if f"<sparkle:shortVersionString>{a.version}</sparkle:shortVersionString>" in existing:
        raise SystemExit(f"appcast zaten {a.version} içeriyor")
    body = re.sub(r"(<language>[^<]*</language>\n)", r"\1" + item.replace("\\", "\\\\"), existing, count=1)
    a.appcast.write_text(body)
    print(f"appcast: {a.version} eklendi")


if __name__ == "__main__":
    main()
