"""Bump patch + build number in pubspec.yaml. Prints the new version.

Usage: python3 tool/bump_patch.py
Turns `version: 0.1.0+1` into `version: 0.1.1+2`.
"""

import re
import sys

PUBSPEC = "pubspec.yaml"


def main() -> None:
    with open(PUBSPEC) as f:
        content = f.read()
    match = re.search(
        r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", content, re.M
    )
    if not match:
        sys.exit("version line not found in pubspec.yaml")
    major, minor, patch, code = map(int, match.groups())
    new_version = f"{major}.{minor}.{patch + 1}+{code + 1}"
    content = (
        content[: match.start()]
        + f"version: {new_version}\n"
        + content[match.end() :]
    )
    with open(PUBSPEC, "w") as f:
        f.write(content)
    print(new_version)


if __name__ == "__main__":
    main()
