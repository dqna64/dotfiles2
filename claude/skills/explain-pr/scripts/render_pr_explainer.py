#!/usr/bin/env python3
"""Validate structured PR story data and render a self-contained HTML artifact."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from string import Template
from typing import Any
from urllib.parse import urlparse


CONFIDENCE_VALUES = {"fact", "inference", "unknown"}
WATCHOUT_KINDS = {"risk", "assumption", "unknown"}
FILE_CATEGORIES = {"core", "supporting", "test", "mechanical", "generated"}
REQUIRED_META = {
    "owner",
    "repo",
    "number",
    "title",
    "url",
    "author",
    "state",
    "is_draft",
    "base_ref",
    "base_sha",
    "head_ref",
    "head_sha",
    "additions",
    "deletions",
    "changed_files",
}


class StoryError(ValueError):
    pass


def is_https_url(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc)


def require_text(value: Any, label: str, errors: list[str]) -> None:
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{label} must be non-empty text")


def validate_story(story: Any) -> dict[str, Any]:
    errors: list[str] = []
    if not isinstance(story, dict):
        raise StoryError("story root must be an object")

    meta = story.get("meta")
    if not isinstance(meta, dict):
        errors.append("meta must be an object")
        meta = {}
    missing_meta = sorted(REQUIRED_META - set(meta))
    if missing_meta:
        errors.append(f"meta is missing: {', '.join(missing_meta)}")
    for key in ("owner", "repo", "title", "author", "state", "base_ref", "head_ref"):
        require_text(meta.get(key), f"meta.{key}", errors)
    for key in ("base_sha", "head_sha"):
        value = meta.get(key)
        if not isinstance(value, str) or not re.fullmatch(
            r"[0-9a-fA-F]{7,64}", value
        ):
            errors.append(f"meta.{key} must be a commit-like hexadecimal identifier")
    if not is_https_url(meta.get("url")):
        errors.append("meta.url must be an absolute HTTPS URL")
    for key in ("number", "additions", "deletions", "changed_files"):
        if not isinstance(meta.get(key), int) or meta.get(key, -1) < 0:
            errors.append(f"meta.{key} must be a non-negative integer")
    if not isinstance(meta.get("is_draft"), bool):
        errors.append("meta.is_draft must be a boolean")

    overview = story.get("overview")
    if not isinstance(overview, dict):
        errors.append("overview must be an object")
        overview = {}
    for key in ("one_minute_summary", "why"):
        require_text(overview.get(key), f"overview.{key}", errors)
    for key in ("scope", "not_in_scope"):
        values = overview.get(key)
        if not isinstance(values, list) or any(
            not isinstance(item, str) or not item.strip() for item in values
        ):
            errors.append(f"overview.{key} must be an array of non-empty strings")

    flow = story.get("flow")
    if not isinstance(flow, list) or not flow:
        errors.append("flow must be a non-empty array")
        flow = []
    for index, item in enumerate(flow):
        if not isinstance(item, dict):
            errors.append(f"flow[{index}] must be an object")
            continue
        require_text(item.get("label"), f"flow[{index}].label", errors)
        require_text(item.get("description"), f"flow[{index}].description", errors)
        validate_urls(item.get("source_urls"), f"flow[{index}].source_urls", errors)

    chapters = story.get("chapters")
    if not isinstance(chapters, list) or not chapters:
        errors.append("chapters must be a non-empty array")
        chapters = []
    for index, chapter in enumerate(chapters):
        if not isinstance(chapter, dict):
            errors.append(f"chapters[{index}] must be an object")
            continue
        require_text(chapter.get("title"), f"chapters[{index}].title", errors)
        require_text(chapter.get("summary"), f"chapters[{index}].summary", errors)
        if chapter.get("confidence") not in CONFIDENCE_VALUES:
            errors.append(
                f"chapters[{index}].confidence must be fact, inference, or unknown"
            )
        evidence = chapter.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            errors.append(f"chapters[{index}].evidence must be a non-empty array")
        else:
            for evidence_index, source in enumerate(evidence):
                validate_source(
                    source,
                    f"chapters[{index}].evidence[{evidence_index}]",
                    errors,
                )
        steps = chapter.get("steps")
        if not isinstance(steps, list) or not steps:
            errors.append(f"chapters[{index}].steps must be a non-empty array")
            continue
        for step_index, step in enumerate(steps):
            if not isinstance(step, dict):
                errors.append(
                    f"chapters[{index}].steps[{step_index}] must be an object"
                )
                continue
            require_text(
                step.get("title"),
                f"chapters[{index}].steps[{step_index}].title",
                errors,
            )
            require_text(
                step.get("explanation"),
                f"chapters[{index}].steps[{step_index}].explanation",
                errors,
            )
            code = step.get("code")
            if code is not None:
                if not isinstance(code, dict):
                    errors.append(
                        f"chapters[{index}].steps[{step_index}].code must be an object"
                    )
                else:
                    for key in ("language", "label", "content"):
                        require_text(
                            code.get(key),
                            f"chapters[{index}].steps[{step_index}].code.{key}",
                            errors,
                        )
                    if not is_https_url(code.get("source_url")):
                        errors.append(
                            f"chapters[{index}].steps[{step_index}].code.source_url "
                            "must be an absolute HTTPS URL"
                        )

    tests = story.get("tests")
    if not isinstance(tests, list):
        errors.append("tests must be an array")
        tests = []
    for index, test in enumerate(tests):
        if not isinstance(test, dict):
            errors.append(f"tests[{index}] must be an object")
            continue
        require_text(test.get("behavior"), f"tests[{index}].behavior", errors)
        require_text(test.get("evidence"), f"tests[{index}].evidence", errors)
        if not is_https_url(test.get("source_url")):
            errors.append(f"tests[{index}].source_url must be an absolute HTTPS URL")

    watchouts = story.get("watchouts")
    if not isinstance(watchouts, list):
        errors.append("watchouts must be an array")
        watchouts = []
    for index, item in enumerate(watchouts):
        if not isinstance(item, dict):
            errors.append(f"watchouts[{index}] must be an object")
            continue
        if item.get("kind") not in WATCHOUT_KINDS:
            errors.append(
                f"watchouts[{index}].kind must be risk, assumption, or unknown"
            )
        require_text(item.get("title"), f"watchouts[{index}].title", errors)
        require_text(item.get("detail"), f"watchouts[{index}].detail", errors)
        validate_urls(
            item.get("source_urls"), f"watchouts[{index}].source_urls", errors
        )

    files = story.get("files")
    if not isinstance(files, list) or not files:
        errors.append("files must be a non-empty array")
        files = []
    seen_paths: set[str] = set()
    for index, item in enumerate(files):
        if not isinstance(item, dict):
            errors.append(f"files[{index}] must be an object")
            continue
        path = item.get("path")
        require_text(path, f"files[{index}].path", errors)
        if isinstance(path, str):
            if path in seen_paths:
                errors.append(f"files[{index}].path is duplicated: {path}")
            seen_paths.add(path)
        for key in ("status", "role", "treatment"):
            require_text(item.get(key), f"files[{index}].{key}", errors)
        if item.get("category") not in FILE_CATEGORIES:
            errors.append(
                f"files[{index}].category must be one of "
                f"{', '.join(sorted(FILE_CATEGORIES))}"
            )
        for key in ("additions", "deletions"):
            if not isinstance(item.get(key), int) or item.get(key, -1) < 0:
                errors.append(f"files[{index}].{key} must be a non-negative integer")
        if not is_https_url(item.get("url")):
            errors.append(f"files[{index}].url must be an absolute HTTPS URL")

    changed_files = meta.get("changed_files")
    if isinstance(changed_files, int) and len(files) != changed_files:
        errors.append(
            f"files contains {len(files)} entries but meta.changed_files is "
            f"{changed_files}"
        )

    if errors:
        raise StoryError("\n".join(f"- {error}" for error in errors))
    return story


def validate_urls(value: Any, label: str, errors: list[str]) -> None:
    if not isinstance(value, list):
        errors.append(f"{label} must be an array")
        return
    for index, url in enumerate(value):
        if not is_https_url(url):
            errors.append(f"{label}[{index}] must be an absolute HTTPS URL")


def validate_source(value: Any, label: str, errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return
    require_text(value.get("label"), f"{label}.label", errors)
    if not is_https_url(value.get("url")):
        errors.append(f"{label}.url must be an absolute HTTPS URL")


def esc(value: Any) -> str:
    return html.escape(str(value), quote=True)


def paragraph_text(value: str) -> str:
    paragraphs = [
        f"<p>{esc(part.strip())}</p>"
        for part in re.split(r"\n\s*\n", value)
        if part.strip()
    ]
    return "".join(paragraphs)


def source_links(
    sources: list[dict[str, Any]] | None = None,
    urls: list[str] | None = None,
) -> str:
    links: list[str] = []
    if sources:
        links.extend(
            f'<a href="{esc(source["url"])}" target="_blank" '
            f'rel="noreferrer">{esc(source["label"])}</a>'
            for source in sources
        )
    if urls:
        links.extend(
            f'<a href="{esc(url)}" target="_blank" rel="noreferrer">'
            f'Source {index}</a>'
            for index, url in enumerate(urls, start=1)
        )
    if not links:
        return ""
    return f'<div class="source-links">{"".join(links)}</div>'


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "section"


def render_list(items: list[str], empty_text: str) -> str:
    if not items:
        return f'<p class="muted">{esc(empty_text)}</p>'
    return "<ul>" + "".join(f"<li>{esc(item)}</li>" for item in items) + "</ul>"


def render_header(meta: dict[str, Any]) -> str:
    state = "DRAFT" if meta["is_draft"] else meta["state"]
    return f"""
<header class="page-header">
  <div class="eyebrow">PR #{meta["number"]} | {esc(meta["owner"])}/{esc(meta["repo"])}</div>
  <h1>{esc(meta["title"])}</h1>
  <p class="subtitle">A causal walkthrough of the final change at <code>{esc(meta["head_sha"][:12])}</code>.</p>
  <div class="meta-strip">
    <span>{esc(state)}</span>
    <span>by {esc(meta["author"])}</span>
    <span>+{meta["additions"]} / -{meta["deletions"]}</span>
    <span>{meta["changed_files"]} files</span>
    <a href="{esc(meta["url"])}" target="_blank" rel="noreferrer">Open PR</a>
    <a href="{esc(meta["url"] + "/files")}" target="_blank" rel="noreferrer">Open diff</a>
  </div>
</header>
"""


def render_overview(overview: dict[str, Any]) -> str:
    return f"""
<section id="overview" class="content-section">
  <div class="section-heading">
    <span class="section-number">01</span>
    <div><h2>One-minute summary</h2><p>The shortest useful mental model.</p></div>
  </div>
  <div class="summary-lead">{paragraph_text(overview["one_minute_summary"])}</div>
  <h3>Why this exists</h3>
  {paragraph_text(overview["why"])}
  <div class="scope-grid">
    <div class="scope-block">
      <h3>In scope</h3>
      {render_list(overview["scope"], "No additional scope was established.")}
    </div>
    <div class="scope-block">
      <h3>Not in scope</h3>
      {render_list(overview["not_in_scope"], "No explicit deferrals were established.")}
    </div>
  </div>
</section>
"""


def render_flow(flow: list[dict[str, Any]]) -> str:
    steps = []
    for item in flow:
        steps.append(
            f"""
<li class="flow-step">
  <div class="flow-label">{esc(item["label"])}</div>
  <p>{esc(item["description"])}</p>
  {source_links(urls=item["source_urls"])}
</li>
"""
        )
    return f"""
<section id="flow" class="content-section">
  <div class="section-heading">
    <span class="section-number">02</span>
    <div><h2>Change story at a glance</h2><p>Read left to right, then continue into the chapters.</p></div>
  </div>
  <ol class="flow-list">{"".join(steps)}</ol>
</section>
"""


def render_code(code: dict[str, Any]) -> str:
    return f"""
<figure class="code-figure">
  <figcaption>
    <span>{esc(code["label"])}</span>
    <a href="{esc(code["source_url"])}" target="_blank" rel="noreferrer">View source</a>
  </figcaption>
  <pre><code class="language-{esc(code["language"])}">{esc(code["content"])}</code></pre>
</figure>
"""


def render_chapters(chapters: list[dict[str, Any]]) -> tuple[str, list[tuple[str, str]]]:
    sections: list[str] = []
    toc: list[tuple[str, str]] = []
    for index, chapter in enumerate(chapters, start=1):
        section_id = f"chapter-{index}-{slugify(chapter['title'])}"
        toc.append((section_id, chapter["title"]))
        steps = []
        for step in chapter["steps"]:
            code = render_code(step["code"]) if step.get("code") else ""
            steps.append(
                f"""
<div class="chapter-step">
  <h3>{esc(step["title"])}</h3>
  {paragraph_text(step["explanation"])}
  {code}
</div>
"""
            )
        sections.append(
            f"""
<section id="{esc(section_id)}" class="content-section chapter">
  <div class="section-heading">
    <span class="section-number">{index + 2:02d}</span>
    <div>
      <div class="heading-row">
        <h2>{esc(chapter["title"])}</h2>
        <span class="confidence {esc(chapter["confidence"])}">{esc(chapter["confidence"])}</span>
      </div>
      <p>{esc(chapter["summary"])}</p>
    </div>
  </div>
  {source_links(sources=chapter["evidence"])}
  <div class="chapter-steps">{"".join(steps)}</div>
</section>
"""
        )
    return "".join(sections), toc


def render_tests(tests: list[dict[str, Any]], number: int) -> str:
    if tests:
        rows = "".join(
            f"""
<tr>
  <td>{esc(item["behavior"])}</td>
  <td>{esc(item["evidence"])}</td>
  <td><a href="{esc(item["source_url"])}" target="_blank" rel="noreferrer">Test</a></td>
</tr>
"""
            for item in tests
        )
        content = f"""
<div class="table-wrap">
  <table>
    <thead><tr><th>Behavior</th><th>What the test establishes</th><th>Evidence</th></tr></thead>
    <tbody>{rows}</tbody>
  </table>
</div>
"""
    else:
        content = (
            '<p class="empty-state">No committed tests were identified as '
            "behavioral evidence for this change.</p>"
        )
    return f"""
<section id="tests" class="content-section">
  <div class="section-heading">
    <span class="section-number">{number:02d}</span>
    <div><h2>Behavioral evidence</h2><p>What the committed tests demonstrate.</p></div>
  </div>
  {content}
</section>
"""


def render_watchouts(watchouts: list[dict[str, Any]], number: int) -> str:
    if watchouts:
        items = "".join(
            f"""
<article class="watchout {esc(item["kind"])}">
  <div class="watchout-kind">{esc(item["kind"])}</div>
  <h3>{esc(item["title"])}</h3>
  {paragraph_text(item["detail"])}
  {source_links(urls=item["source_urls"])}
</article>
"""
            for item in watchouts
        )
    else:
        items = (
            '<p class="empty-state">No evidence-backed risks, assumptions, or '
            "unknowns were identified.</p>"
        )
    return f"""
<section id="watchouts" class="content-section">
  <div class="section-heading">
    <span class="section-number">{number:02d}</span>
    <div><h2>Watchouts and unknowns</h2><p>Kept separate from the teaching narrative.</p></div>
  </div>
  <div class="watchout-list">{items}</div>
</section>
"""


def render_files(files: list[dict[str, Any]], number: int) -> str:
    rows = "".join(
        f"""
<tr>
  <td><a href="{esc(item["url"])}" target="_blank" rel="noreferrer"><code>{esc(item["path"])}</code></a></td>
  <td><span class="category {esc(item["category"])}">{esc(item["category"])}</span></td>
  <td>{esc(item["status"])}</td>
  <td>{esc(item["role"])}</td>
  <td>{esc(item["treatment"])}</td>
  <td>+{item["additions"]} / -{item["deletions"]}</td>
</tr>
"""
        for item in files
    )
    return f"""
<section id="coverage" class="content-section">
  <div class="section-heading">
    <span class="section-number">{number:02d}</span>
    <div><h2>Changed-file coverage</h2><p>Every changed file, including mechanical work.</p></div>
  </div>
  <div class="table-wrap">
    <table class="coverage-table">
      <thead>
        <tr><th>File</th><th>Category</th><th>Status</th><th>Role</th><th>Treatment</th><th>Diff</th></tr>
      </thead>
      <tbody>{rows}</tbody>
    </table>
  </div>
</section>
"""


def render_toc(chapter_toc: list[tuple[str, str]]) -> str:
    links = [
        ("overview", "One-minute summary"),
        ("flow", "Change story"),
        *chapter_toc,
        ("tests", "Behavioral evidence"),
        ("watchouts", "Watchouts"),
        ("coverage", "File coverage"),
    ]
    return (
        '<nav class="toc" aria-label="Document sections">'
        '<div class="toc-title">Contents</div>'
        + "".join(
            f'<a href="#{esc(section_id)}">{esc(label)}</a>'
            for section_id, label in links
        )
        + "</nav>"
    )


def render_footer(meta: dict[str, Any], generated_at: str) -> str:
    return f"""
<footer>
  <p>Generated {esc(generated_at)} from base <code>{esc(meta["base_sha"])}</code>
  and head <code>{esc(meta["head_sha"])}</code>.</p>
</footer>
"""


def default_output_path(meta: dict[str, Any]) -> Path:
    folder = f"{meta['owner']}-{meta['repo']}"
    return (
        Path.home()
        / "work"
        / "Banva"
        / "Archives"
        / "PR Explainers"
        / folder
        / f"pr-{meta['number']}.html"
    )


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    os.replace(temp_path, path)


def render_story(story: dict[str, Any], template_path: Path) -> str:
    template = Template(template_path.read_text(encoding="utf-8"))
    meta = story["meta"]
    chapter_html, chapter_toc = render_chapters(story["chapters"])
    tests_number = len(story["chapters"]) + 3
    watchouts_number = tests_number + 1
    coverage_number = watchouts_number + 1
    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    main = (
        render_overview(story["overview"])
        + render_flow(story["flow"])
        + chapter_html
        + render_tests(story["tests"], tests_number)
        + render_watchouts(story["watchouts"], watchouts_number)
        + render_files(story["files"], coverage_number)
    )
    return template.substitute(
        page_title=esc(f"PR #{meta['number']}: {meta['title']}"),
        header=render_header(meta),
        toc=render_toc(chapter_toc),
        main=main,
        footer=render_footer(meta, generated_at),
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render validated PR story JSON as self-contained HTML."
    )
    parser.add_argument("--input", required=True, help="Path to story JSON.")
    parser.add_argument("--output", help="Override the canonical output path.")
    parser.add_argument(
        "--template",
        help="Override the bundled HTML template path.",
    )
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="Validate the story without writing HTML.",
    )
    args = parser.parse_args()

    try:
        story_data = json.loads(Path(args.input).expanduser().read_text("utf-8"))
        story = validate_story(story_data)
        if args.validate_only:
            print("Story JSON is valid.")
            return 0
        template_path = (
            Path(args.template).expanduser()
            if args.template
            else Path(__file__).resolve().parent.parent
            / "assets"
            / "pr-explainer-template.html"
        )
        if not template_path.is_file():
            raise StoryError(f"template not found: {template_path}")
        output = (
            Path(args.output).expanduser()
            if args.output
            else default_output_path(story["meta"])
        )
        atomic_write(output, render_story(story, template_path))
        print(output)
        return 0
    except (OSError, json.JSONDecodeError, StoryError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
