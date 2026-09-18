#!/usr/bin/env python3
"""Rewrite the '## PR Train' section on every PR of a stacked train.

usage: update_train_section.py [--repo OWNER/REPO] [--dry-run] N1 N2 N3 ...   (PR numbers in train order)

Defaults to Canva/canva. Uses `gh --repo`, so it needs no local checkout and runs from any directory.

Each PR gets the full ordered list of bare PR URLs with ' <-- this PR' on its own line. The section is
inserted above a trailing attribution footer ('🤖 Generated with ...') when present, else appended.
"""
import argparse, re, subprocess, sys, tempfile

ap = argparse.ArgumentParser()
ap.add_argument("--repo", default="Canva/canva", help="owner/repo (default: Canva/canva)")
ap.add_argument("--dry-run", action="store_true", help="print each new body instead of editing the PR")
ap.add_argument("numbers", nargs="+", type=int, help="PR numbers in train order")
a = ap.parse_args()

def gh(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"gh {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout

repo = a.repo
url = f"https://github.com/{repo.lower()}/pull/"   # GitHub URLs are case-insensitive; lowercase keeps existing lists stable
section_re = re.compile(r"## PR Train\n\n(?:- (?:https://)?github\.com/" + re.escape(repo) + r"/pull/\d+[^\n]*\n)+\n?", re.IGNORECASE)
footer_re = re.compile(r"^🤖 Generated with [^\n]*$", re.MULTILINE)   # may be followed by bot-added link references

for n in a.numbers:
    section = "## PR Train\n\n" + "\n".join(f"- {url}{m}" + (" <-- this PR" if m == n else "") for m in a.numbers) + "\n"
    body = gh("pr", "view", str(n), "--repo", repo, "--json", "body", "--jq", ".body")
    body = section_re.sub("", body)
    m = footer_re.search(body)
    body = body[:m.start()].rstrip("\n") + "\n\n" + section + "\n" + body[m.start():] if m else body.rstrip("\n") + "\n\n" + section
    if a.dry_run:
        print(f"===== #{n} =====\n{body}")
        continue
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
        f.write(body)
    gh("pr", "edit", str(n), "--repo", repo, "--body-file", f.name)
    print(n, "ok")
