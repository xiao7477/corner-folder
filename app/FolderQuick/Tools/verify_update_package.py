#!/usr/bin/env python3
"""Verify both signatures and archive metadata before uploading a release."""
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlparse

feed, archive, signer, key = map(Path, sys.argv[1:])
subprocess.run([str(signer), "--ed-key-file", str(key), "--verify", str(feed)], check=True)
enclosure = ET.parse(feed).find(".//enclosure")
if enclosure is None:
    raise SystemExit("更新信息没有下载附件")
if Path(unquote(urlparse(enclosure.attrib["url"]).path)).name != archive.name:
    raise SystemExit("更新信息中的附件名称与 ZIP 不匹配")
if int(enclosure.attrib["length"]) != archive.stat().st_size:
    raise SystemExit("更新 ZIP 的大小与签名更新信息不匹配")
signature = enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"]
subprocess.run([str(signer), "--ed-key-file", str(key), "--verify", str(archive), signature], check=True)
print("更新信息和 ZIP 的签名校验通过")
