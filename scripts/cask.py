#!/usr/bin/env python3
"""Writes the Homebrew cask for a release: packaging/homebrew/damla.rb with the version and dmg sha256 filled in."""
import argparse
import hashlib
from pathlib import Path


def render(template, version, sha256):
    return template.replace("@VERSION@", version).replace("@SHA256@", sha256)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dmg", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    digest = hashlib.sha256(args.dmg.read_bytes()).hexdigest()
    template = (Path(__file__).resolve().parent.parent / "packaging/homebrew/damla.rb").read_text()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(template, args.version, digest))
    print(f"cask: {args.version} {digest}")


if __name__ == "__main__":
    main()
