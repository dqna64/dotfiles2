#!/usr/bin/env python3
"""Gather stable, read-only GitHub PR context through the gh CLI."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlparse


PR_FIELDS = (
    "number,title,url,author,body,baseRefName,baseRefOid,headRefName,"
    "headRefOid,headRepository,headRepositoryOwner,isCrossRepository,"
    "isDraft,state,createdAt,updatedAt,additions,deletions,changedFiles,"
    "labels,commits,statusCheckRollup"
)
MAX_DISCUSSION_BODY = 12_000


class GhError(RuntimeError):
    pass


def run_gh(args: list[str], *, raw: bool = False) -> str | bytes:
    if shutil.which("gh") is None:
        raise GhError("gh CLI is not installed or not on PATH")

    env = os.environ.copy()
    env["GH_PAGER"] = "cat"
    env["NO_COLOR"] = "1"
    completed = subprocess.run(
        ["gh", *args],
        check=False,
        capture_output=True,
        text=not raw,
        env=env,
    )
    if completed.returncode != 0:
        stderr = completed.stderr
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        detail = stderr.strip() or f"gh exited with status {completed.returncode}"
        raise GhError(f"gh {' '.join(args[:3])}: {detail}")
    return completed.stdout


def gh_json(args: list[str]) -> Any:
    output = run_gh(args)
    assert isinstance(output, str)
    try:
        return json.loads(output)
    except json.JSONDecodeError as exc:
        raise GhError(f"gh returned invalid JSON: {exc}") from exc


def pr_view(selector: str | None, repo: str | None) -> dict[str, Any]:
    args = ["pr", "view"]
    if selector:
        args.append(selector)
    if repo:
        args.extend(["--repo", repo])
    args.extend(["--json", PR_FIELDS])
    result = gh_json(args)
    if not isinstance(result, dict):
        raise GhError("gh pr view did not return an object")
    return result


def parse_repo_from_url(url: str) -> tuple[str, str]:
    parsed = urlparse(url)
    parts = [part for part in parsed.path.split("/") if part]
    if parsed.netloc != "github.com" or len(parts) < 2:
        raise GhError(f"cannot derive GitHub repository from PR URL: {url}")
    return parts[0], parts[1]


def paginated_api(endpoint: str) -> list[dict[str, Any]]:
    pages = gh_json(["api", "--paginate", "--slurp", endpoint])
    if not isinstance(pages, list):
        raise GhError(f"GitHub API returned unexpected data for {endpoint}")
    items: list[dict[str, Any]] = []
    for page in pages:
        if isinstance(page, list):
            items.extend(item for item in page if isinstance(item, dict))
        elif isinstance(page, dict):
            items.append(page)
    return items


def probable_bot(user: Any, repo_full_name: str) -> bool:
    if not isinstance(user, dict):
        return False
    login = str(user.get("login") or "").lower()
    user_type = str(user.get("type") or "").lower()
    if user_type == "bot" or "[bot]" in login or login.endswith("-bot"):
        return True
    if login.startswith(("dependabot", "renovate", "github-actions")):
        return True
    if repo_full_name.lower() == "canva/canva":
        return login in {
            "canva-ci-bot",
            "developer-platform-bot",
            "forge-canva",
            "owners-canva",
        }
    return False


def truncate_body(body: Any) -> tuple[str, bool]:
    text = str(body or "")
    if len(text) <= MAX_DISCUSSION_BODY:
        return text, False
    return text[:MAX_DISCUSSION_BODY] + "\n[truncated]", True


def normalize_discussion_item(
    item: dict[str, Any], *, kind: str
) -> dict[str, Any]:
    body, truncated = truncate_body(item.get("body"))
    user = item.get("user") if isinstance(item.get("user"), dict) else {}
    result: dict[str, Any] = {
        "kind": kind,
        "id": item.get("id"),
        "author": user.get("login"),
        "author_association": item.get("author_association"),
        "body": body,
        "body_truncated": truncated,
        "created_at": item.get("created_at") or item.get("submitted_at"),
        "updated_at": item.get("updated_at"),
        "url": item.get("html_url"),
    }
    for key in (
        "state",
        "path",
        "line",
        "original_line",
        "side",
        "start_line",
        "commit_id",
        "original_commit_id",
        "in_reply_to_id",
    ):
        if item.get(key) is not None:
            result[key] = item[key]
    return result


def classify_file(path: str, patch: str | None) -> str:
    lower = path.lower()
    name = Path(path).name.lower()
    patch_head = "\n".join((patch or "").splitlines()[:12]).lower()

    generated_suffixes = (
        "proto.java",
        "api.yml",
        "proto.ts",
        "proto_client.ts",
        "proto_services.ts",
    )
    if name.endswith(generated_suffixes) or "// generated from" in patch_head:
        return "generated"

    mechanical_names = {
        "build",
        "build.bazel",
        "workspace",
        "workspace.bazel",
        "tsconfig.json",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "cargo.lock",
        "go.sum",
    }
    if (
        name in mechanical_names
        or name.endswith((".snap", ".lock"))
    ):
        return "mechanical"

    test_markers = (
        "/test/",
        "/tests/",
        ".test.",
        ".tests.",
        ".spec.",
        "__tests__",
    )
    if any(marker in lower for marker in test_markers):
        return "test"

    if name.endswith((".md", ".mdx", ".rst")):
        return "supporting"

    return "core"


def normalize_file(
    item: dict[str, Any],
    *,
    base_owner: str,
    base_repo: str,
    base_sha: str,
    head_owner: str,
    head_repo: str,
    head_sha: str,
) -> dict[str, Any]:
    path = str(item.get("filename") or "")
    previous_path = str(item.get("previous_filename") or path)
    patch = item.get("patch")
    return {
        "path": path,
        "previous_path": previous_path if previous_path != path else None,
        "status": item.get("status"),
        "additions": item.get("additions", 0),
        "deletions": item.get("deletions", 0),
        "changes": item.get("changes", 0),
        "category_hint": classify_file(path, patch),
        "patch": patch,
        "patch_missing": patch is None,
        "base_url": (
            f"https://github.com/{base_owner}/{base_repo}/blob/"
            f"{base_sha}/{quote(previous_path, safe='/')}"
        ),
        "head_url": (
            f"https://github.com/{head_owner}/{head_repo}/blob/"
            f"{head_sha}/{quote(path, safe='/')}"
        ),
    }


def collect_discussion(
    owner: str, repo: str, number: int
) -> dict[str, Any]:
    repo_full_name = f"{owner}/{repo}"
    endpoints = {
        "issue_comments": f"/repos/{owner}/{repo}/issues/{number}/comments?per_page=100",
        "reviews": f"/repos/{owner}/{repo}/pulls/{number}/reviews?per_page=100",
        "review_comments": (
            f"/repos/{owner}/{repo}/pulls/{number}/comments?per_page=100"
        ),
    }
    result: dict[str, Any] = {}
    filtered = 0
    for kind, endpoint in endpoints.items():
        kept: list[dict[str, Any]] = []
        for item in paginated_api(endpoint):
            user = item.get("user")
            if probable_bot(user, repo_full_name):
                filtered += 1
                continue
            normalized = normalize_discussion_item(item, kind=kind)
            if kind == "reviews" and not normalized["body"].strip():
                continue
            kept.append(normalized)
        result[kind] = kept
    result["filtered_automated_items"] = filtered
    return result


def atomic_write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        json.dump(data, handle, indent=2, ensure_ascii=True)
        handle.write("\n")
        temp_path = Path(handle.name)
    os.replace(temp_path, path)


def atomic_write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "wb",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        handle.write(data)
        temp_path = Path(handle.name)
    os.replace(temp_path, path)


def collect_command(args: argparse.Namespace) -> int:
    pr = pr_view(args.selector, args.repo)
    owner, repo = parse_repo_from_url(str(pr["url"]))

    head_repo_data = pr.get("headRepository")
    head_owner_data = pr.get("headRepositoryOwner")
    head_repo = (
        str(head_repo_data.get("name"))
        if isinstance(head_repo_data, dict) and head_repo_data.get("name")
        else repo
    )
    head_owner = (
        str(head_owner_data.get("login"))
        if isinstance(head_owner_data, dict) and head_owner_data.get("login")
        else owner
    )

    number = int(pr["number"])
    files_raw = paginated_api(
        f"/repos/{owner}/{repo}/pulls/{number}/files?per_page=100"
    )
    files = [
        normalize_file(
            item,
            base_owner=owner,
            base_repo=repo,
            base_sha=str(pr["baseRefOid"]),
            head_owner=head_owner,
            head_repo=head_repo,
            head_sha=str(pr["headRefOid"]),
        )
        for item in files_raw
    ]

    context: dict[str, Any] = {
        "schema_version": 1,
        "gathered_at": datetime.now(timezone.utc).isoformat(),
        "repository": f"{owner}/{repo}",
        "head_repository": f"{head_owner}/{head_repo}",
        "pr": {
            key: pr.get(key)
            for key in (
                "number",
                "title",
                "url",
                "author",
                "body",
                "baseRefName",
                "baseRefOid",
                "headRefName",
                "headRefOid",
                "isCrossRepository",
                "isDraft",
                "state",
                "createdAt",
                "updatedAt",
                "additions",
                "deletions",
                "changedFiles",
                "labels",
                "commits",
                "statusCheckRollup",
            )
        },
        "links": {
            "pr": pr["url"],
            "diff": f"{pr['url']}/files",
            "commits": f"{pr['url']}/commits",
            "checks": f"{pr['url']}/checks",
        },
        "files": files,
    }
    if len(files) != int(pr.get("changedFiles") or 0):
        context["warnings"] = [
            "GitHub's changedFiles count does not match the files API result."
        ]
    if args.include_discussion:
        context["human_discussion"] = collect_discussion(owner, repo, number)

    if args.output:
        atomic_write_json(Path(args.output).expanduser(), context)
    else:
        json.dump(context, sys.stdout, indent=2, ensure_ascii=True)
        sys.stdout.write("\n")
    return 0


def fetch_file_command(args: argparse.Namespace) -> int:
    if not re.fullmatch(r"[0-9a-fA-F]{7,64}", args.ref):
        raise GhError("--ref must be a commit-like hexadecimal identifier")
    if "/" not in args.repo:
        raise GhError("--repo must use OWNER/REPO format")
    owner, repo = args.repo.split("/", 1)
    encoded_path = quote(args.path.lstrip("/"), safe="/")
    endpoint = f"/repos/{owner}/{repo}/contents/{encoded_path}?ref={args.ref}"
    content = run_gh(
        ["api", "-H", "Accept: application/vnd.github.raw", endpoint],
        raw=True,
    )
    assert isinstance(content, bytes)
    if args.output:
        atomic_write_bytes(Path(args.output).expanduser(), content)
    else:
        sys.stdout.buffer.write(content)
    return 0


def check_head_command(args: argparse.Namespace) -> int:
    pr = pr_view(args.selector, args.repo)
    actual = str(pr.get("headRefOid") or "")
    result = {
        "number": pr.get("number"),
        "url": pr.get("url"),
        "expected_head": args.expect_head,
        "actual_head": actual,
        "matches": actual.lower() == args.expect_head.lower(),
    }
    json.dump(result, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0 if result["matches"] else 3


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Gather read-only GitHub PR context through gh."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    collect = subparsers.add_parser("collect", help="Collect PR metadata and patches.")
    collect.add_argument("selector", nargs="?", help="PR URL, number, or branch.")
    collect.add_argument("--repo", help="Repository in OWNER/REPO format.")
    collect.add_argument(
        "--include-discussion",
        action="store_true",
        help="Include non-bot issue comments, reviews, and inline comments.",
    )
    collect.add_argument("--output", help="Write JSON atomically to this path.")
    collect.set_defaults(func=collect_command)

    fetch_file = subparsers.add_parser(
        "fetch-file", help="Fetch one file at an exact commit SHA."
    )
    fetch_file.add_argument("--repo", required=True, help="OWNER/REPO.")
    fetch_file.add_argument("--ref", required=True, help="Exact commit SHA.")
    fetch_file.add_argument("--path", required=True, help="Repository-relative path.")
    fetch_file.add_argument("--output", help="Write bytes atomically to this path.")
    fetch_file.set_defaults(func=fetch_file_command)

    check_head = subparsers.add_parser(
        "check-head", help="Confirm the PR head still matches a recorded SHA."
    )
    check_head.add_argument("selector", nargs="?", help="PR URL, number, or branch.")
    check_head.add_argument("--repo", help="Repository in OWNER/REPO format.")
    check_head.add_argument("--expect-head", required=True, help="Recorded head SHA.")
    check_head.set_defaults(func=check_head_command)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.func(args))
    except GhError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
