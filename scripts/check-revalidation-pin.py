#!/usr/bin/env python3
"""Compare the immutable revalidation pin with a resolved stable release."""

import argparse
from pathlib import Path
import re


def check(workflow, release_tag, release_sha):
    if not re.fullmatch(r"v\d+\.\d+\.\d+", release_tag):
        raise ValueError("expected an exact stable release tag")
    if not re.fullmatch(r"[0-9a-f]{40}", release_sha):
        raise ValueError("expected a resolved release commit SHA")
    pins = re.findall(
        r"^\s+uses: flowcore-io/usable-pr-validator@([0-9a-f]{40}) # (v\d+\.\d+\.\d+)\s*$",
        workflow, re.MULTILINE,
    )
    if pins != [(release_sha, release_tag)]:
        raise ValueError(
            f"revalidation must pin {release_tag} at {release_sha}; "
            "update comment-revalidation.yml after publishing the release"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workflow", default=".github/workflows/comment-revalidation.yml")
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--release-sha", required=True)
    args = parser.parse_args()
    try:
        check(Path(args.workflow).read_text(), args.release_tag, args.release_sha)
    except (OSError, ValueError) as error:
        parser.exit(1, f"ERROR: {error}\n")
    print("Revalidation pins the latest published stable release commit.")


if __name__ == "__main__":
    main()
