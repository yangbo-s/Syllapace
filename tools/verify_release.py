#!/usr/bin/env python3
"""Prepare or verify release metadata and archives without reading a private key."""
from __future__ import annotations

import argparse
import base64
from datetime import datetime, timezone
from email.utils import format_datetime
import hashlib
from html import escape
from pathlib import Path, PurePosixPath
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

REPOSITORY = "https://github.com/yangbo-s/Syllapace"
FEED = f"{REPOSITORY}/releases/latest/download/appcast.xml"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ROOT = Path(__file__).resolve().parent.parent
ET.register_namespace("sparkle", SPARKLE)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def release_notes_html(markdown: str) -> str:
    """Render the small heading/list/link subset used by our release notes."""
    def inline(value: str) -> str:
        value = escape(value)
        value = re.sub(r"\[([^\]]+)\]\((https://[^\s)]+)\)", r'<a href="\2">\1</a>', value)
        value = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", value)
        return re.sub(r"`([^`]+)`", r"<code>\1</code>", value)

    blocks = []
    for paragraph in markdown.strip().split("\n\n"):
        lines = paragraph.splitlines()
        if all(line.startswith("- ") for line in lines):
            blocks.append("<ul>" + "".join(f"<li>{inline(line[2:])}</li>" for line in lines) + "</ul>")
        elif paragraph.startswith("## "):
            blocks.append(f"<h3>{inline(paragraph[3:])}</h3>")
        elif paragraph.startswith("# "):
            blocks.append(f"<h2>{inline(paragraph[2:])}</h2>")
        elif paragraph == "---":
            blocks.append("<hr>")
        else:
            blocks.append(f"<p>{inline(paragraph)}</p>")
    return "\n".join(blocks)


def validate_info(info: dict) -> None:
    require(info.get("CFBundleIdentifier") == "app.syllapace.mac", "Unexpected bundle identifier")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", info.get("CFBundleShortVersionString", "")) is not None, "Version must be major.minor.patch")
    require(re.fullmatch(r"[1-9][0-9]*", info.get("CFBundleVersion", "")) is not None, "Build number must be a positive integer")
    require(info.get("LSMinimumSystemVersion") == "26.0", "This release contract requires macOS 26.0")
    require(info.get("SUFeedURL") == FEED, "Unexpected Sparkle feed URL")
    require(info.get("SUVerifyUpdateBeforeExtraction") is True, "Pre-extraction signature verification must be enabled")
    require(info.get("SURequireSignedFeed", False) is False, "This script does not produce signed feeds")
    public_key = base64.b64decode(info.get("SUPublicEDKey", ""), validate=True)
    require(len(public_key) == 32, "A valid 32-byte Sparkle public key is required")


def preflight(app: Path) -> dict:
    require(app.is_dir(), f"Build the application first: {app}")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    validate_info(info)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/Syllapace")], text=True).split()
    require(architectures == ["arm64"], f"Unexpected architectures for arm64 release: {architectures}")
    require((app / "Contents/Frameworks/Sparkle.framework").is_dir(), "Sparkle framework is missing")
    require((app / "Contents/Resources/THIRD_PARTY_NOTICES.md").is_file(), "Third-party notices are missing")
    print(f"PASS: signed bundle, Sparkle configuration, arm64 and release version {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
    return info


def manifest(app: Path, output: Path, signature_path: Path) -> None:
    info = preflight(app)
    version = info["CFBundleShortVersionString"]
    archive = output / f"Syllapace-{version}-macOS-arm64.zip"
    attributes = dict(re.findall(r'([\w:]+)="([^"]+)"', signature_path.read_text()))
    signature = attributes.get("sparkle:edSignature", "")
    require(len(base64.b64decode(signature, validate=True)) == 64, "sign_update did not return an Ed25519 signature")
    require(attributes.get("length") == str(archive.stat().st_size), "Signed archive length differs")
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Syllapace"
    ET.SubElement(channel, "link").text = REPOSITORY
    ET.SubElement(channel, "description").text = "Syllapace updates for macOS"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Syllapace {version}"
    ET.SubElement(item, "link").text = f"{REPOSITORY}/releases/tag/v{version}"
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc), usegmt=True)
    for name, value in [("version", info["CFBundleVersion"]), ("shortVersionString", version),
                        ("minimumSystemVersion", info["LSMinimumSystemVersion"]), ("hardwareRequirements", "arm64")]:
        ET.SubElement(item, f"{{{SPARKLE}}}{name}").text = value
    # Embedded notes stay available without asking Sparkle to render GitHub's site.
    ET.SubElement(item, "description").text = release_notes_html((ROOT / f"docs/releases/{version}.md").read_text())
    ET.SubElement(item, "enclosure", {
        "url": f"{REPOSITORY}/releases/download/v{version}/{archive.name}",
        "length": str(archive.stat().st_size), "type": "application/octet-stream", f"{{{SPARKLE}}}edSignature": signature,
    })
    ET.indent(rss, space="  ")
    ET.ElementTree(rss).write(output / "appcast.xml", encoding="UTF-8", xml_declaration=True)
    paths = sorted(output.glob("*.zip")) + sorted(output.glob("*.dmg")) + [output / "appcast.xml"]
    (output / "SHA256SUMS").write_text("".join(f"{sha256(path)}  {path.name}\n" for path in paths))


def verify_signature(archive: Path, signature: str, public_key: str) -> None:
    # CryptoKit validates against the key shipped inside the app, not merely the
    # key selected in the maintainer's Keychain. Neither private key is exported.
    source = r'''
import Foundation
import CryptoKit
let args = CommandLine.arguments
let keyData = Data(base64Encoded: args[1])!
let signature = Data(base64Encoded: args[2])!
let payload = try Data(contentsOf: URL(fileURLWithPath: args[3]), options: .mappedIfSafe)
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
guard key.isValidSignature(signature, for: payload) else {
    FileHandle.standardError.write(Data("Archive signature does not match the embedded public key\n".utf8))
    exit(1)
}
'''
    with tempfile.TemporaryDirectory(prefix="syllapace-signature-") as directory:
        swift = Path(directory) / "verify.swift"
        swift.write_text(source)
        subprocess.run(["/usr/bin/xcrun", "swift", str(swift), public_key, signature, str(archive)], check=True)


def verify(output: Path) -> None:
    checksums = output / "SHA256SUMS"
    require(checksums.is_file(), "SHA256SUMS missing")
    seen = set()
    for line in checksums.read_text().splitlines():
        digest, name = line.split("  ", 1)
        require(re.fullmatch(r"[0-9a-f]{64}", digest) is not None and Path(name).name == name, "Malformed checksum record")
        require(name not in seen, "Duplicate checksum entry")
        seen.add(name)
        require(sha256(output / name) == digest, f"Checksum mismatch: {name}")
    tree = ET.parse(output / "appcast.xml")
    items = tree.findall("./channel/item")
    require(len(items) == 1, "The release asset feed must describe exactly one release")
    item = items[0]
    enclosure = item.find("enclosure")
    require(enclosure is not None, "Missing update enclosure")
    version = item.findtext(f"{{{SPARKLE}}}shortVersionString")
    require(version is not None and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is not None, "Invalid feed version")
    name = f"Syllapace-{version}-macOS-arm64.zip"
    archive = output / name
    require(seen == {name, f"Syllapace-{version}-macOS-arm64.dmg", "appcast.xml"}, "Missing or unexpected release checksums")
    require(enclosure.get("url") == f"{REPOSITORY}/releases/download/v{version}/{name}", "Unexpected download origin/path")
    require(enclosure.get("length") == str(archive.stat().st_size), "Feed archive length differs")
    require(item.findtext(f"{{{SPARKLE}}}minimumSystemVersion") == "26.0", "Incorrect minimum macOS version")
    require(item.findtext(f"{{{SPARKLE}}}hardwareRequirements") == "arm64", "Incorrect hardware requirement")
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.namelist():
            path = PurePosixPath(member)
            require(not path.is_absolute() and ".." not in path.parts, "Unsafe archive entry")
            require(path.parts[0] in {"Syllapace.app", "__MACOSX"}, "Unexpected root-level ZIP entry")
        info = plistlib.loads(bundle.read("Syllapace.app/Contents/Info.plist"))
    validate_info(info)
    require(info["CFBundleShortVersionString"] == version, "Feed/app marketing version mismatch")
    require(info["CFBundleVersion"] == item.findtext(f"{{{SPARKLE}}}version"), "Feed/app build number mismatch")
    signature = enclosure.get(f"{{{SPARKLE}}}edSignature", "")
    require(len(base64.b64decode(signature, validate=True)) == 64, "Invalid update signature encoding")
    verify_signature(archive, signature, info["SUPublicEDKey"])
    with tempfile.TemporaryDirectory(prefix="syllapace-archive-") as directory:
        subprocess.run(["/usr/bin/ditto", "-x", "-k", str(archive), directory], check=True)
        preflight(Path(directory) / "Syllapace.app")
    subprocess.run(["/usr/bin/hdiutil", "verify", str(output / f"Syllapace-{version}-macOS-arm64.dmg")], check=True, stdout=subprocess.DEVNULL)
    print("PASS: checksums, appcast constraints, embedded-key update signature, ZIP app signature and DMG integrity")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["preflight", "manifest", "verify"])
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()
    paths = [Path(value).resolve() for value in args.paths]
    expected = 3 if args.action == "manifest" else 1
    require(len(paths) == expected, f"{args.action} requires {expected} path(s)")
    if args.action == "preflight":
        preflight(paths[0])
    elif args.action == "manifest":
        manifest(*paths)
    else:
        verify(paths[0])


if __name__ == "__main__":
    main()
