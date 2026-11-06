"""Advisory Markdown checks; deliberately not a YAML or semantic validator."""

from dataclasses import asdict, dataclass, field
from pathlib import Path
import math
import re
from urllib.parse import unquote, urlsplit


@dataclass
class Finding:
    rule: str
    severity: str
    path: str
    line: int
    message: str


@dataclass
class Report:
    path: str
    estimated_tokens: int = 0
    findings: list[Finding] = field(default_factory=list)

    def to_dict(self):
        return asdict(self)


def estimate_tokens(text: str) -> int:
    """Portable size proxy, not a model tokenizer. Includes frontmatter."""
    return math.ceil(len(text) / 4)


def markdown_lines(text: str):
    """Yield (line number, text, inside fence); handle backtick and tilde fences."""
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        match = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if match:
            marker = match[1]
            if fence is None:
                fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence) and not line[match.end():].strip():
                fence = None
            yield number, line, True
        else:
            yield number, line, fence is not None


def local_links(text: str):
    # Inline Markdown links and reference-style definitions; code fences excluded.
    for number, line, fenced in markdown_lines(text):
        if fenced:
            continue
        line = re.sub(r"`[^`]*`", "", line)
        targets = re.findall(r"!?\[[^\]]*\]\([ \t]*(<[^>]+>|(?:[^\s()]|\([^\s()]*\))+)", line)
        definition = re.match(r"^\s{0,3}\[[^\]]+\]:\s*(<[^>]+>|\S+)", line)
        if definition:
            targets.append(definition[1])
        for target in targets:
            target = target.strip("<>")
            parsed = urlsplit(target)
            if not parsed.scheme and not parsed.netloc and parsed.path:
                yield number, unquote(parsed.path)


def lint_skill(path: Path, warn_tokens: int = 500, max_tokens: int = 1000) -> Report:
    root = path.parent if path.name == "SKILL.md" and not path.is_dir() else path
    entry = root / "SKILL.md"
    report = Report(str(entry))

    def add(rule, severity, file, line, message):
        report.findings.append(Finding(rule, severity, str(file), line, message))

    if not entry.resolve().is_relative_to(root.resolve()):
        add("SL300", "error", entry, 1, "SKILL.md escapes the self-contained skill folder.")
        return report
    try:
        text = entry.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeError) as exc:
        add("SL000", "error", entry, 1, f"Cannot read SKILL.md: {exc}")
        return report
    report.estimated_tokens = estimate_tokens(text)
    lines = text.splitlines()
    body_start = 0
    if not lines or lines[0] != "---" or "---" not in lines[1:]:
        add("SL001", "error", entry, 1, "Add YAML frontmatter with name and description.")
    else:
        end = lines[1:].index("---") + 1
        body_start = end + 1
        header = "\n".join(lines[1:end])
        for key in ("name", "description"):
            match = re.search(rf"^{key}:[ \t]*([^\n]*)$", header, re.M)
            value = match[1].strip() if match else ""
            if value in ("|", ">", "|-", ">-", "|+", ">+"):
                remainder = header[match.end():].splitlines()
                block = []
                for line in remainder:
                    if line and not line[0].isspace():
                        break
                    block.append(line.strip())
                value = " ".join(block).strip()
            if not value or value.startswith("#") or value in ('""', "''", "null", "~"):
                add("SL001", "error", entry, 2, f"Add a non-empty {key} field.")
        # This is a presence check; full YAML validation belongs to skills-ref.
    if not any(line.strip() for line in lines[body_start:]):
        add("SL001", "error", entry, body_start + 1, "Add actionable core instructions after frontmatter.")
    if report.estimated_tokens > max_tokens:
        add("SL100", "error", entry, 1, f"~{report.estimated_tokens} tokens exceeds {max_tokens}; move conditional detail out.")
    elif report.estimated_tokens > warn_tokens:
        add("SL100", "warning", entry, 1, f"~{report.estimated_tokens} tokens exceeds the ideal budget of {warn_tokens}.")

    code_lines = 0
    for number, line, fenced in markdown_lines(text):
        if number <= body_start:
            continue
        if fenced:
            code_lines += 1
            continue
        if re.match(r"^#{1,6}\s+(?:background|history|rationale|philosophy|examples?|tutorial|faq|reference)(?:\s|:|$)", line, re.I):
            add("SL200", "warning", entry, number, "Possible reference material; keep only instructions needed for the common case here.")
        if re.search(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)?(?:you\s+)?(?:always|must)\s+(?:read|load)\s+(?:all|every)\b", line, re.I):
            add("SL201", "warning", entry, number, "Unconditional bulk loading defeats progressive disclosure; route by task.")
    if code_lines > 20:
        add("SL202", "warning", entry, 1, f"{code_lines} fenced lines; consider moving long examples into examples/.")

    # Follow reachable Markdown routes so split references can link to each other.
    root_resolved = root.resolve()
    pending = [(entry, text)]
    reached = {entry.resolve()}
    while pending:
        current, content = pending.pop()
        for number, target in local_links(content):
            destination = (current.parent / target).resolve()
            if not destination.is_relative_to(root_resolved):
                add("SL300", "error", current, number, f"Link escapes the self-contained skill: {target}")
                continue
            if not destination.is_file():
                add("SL301", "error", current, number, f"Linked file does not exist: {target}")
                continue
            if destination in reached:
                continue
            reached.add(destination)
            if destination.suffix.lower() == ".md":
                try:
                    pending.append((destination, destination.read_text(encoding="utf-8-sig")))
                except (OSError, UnicodeError) as exc:
                    add("SL000", "error", current, number, f"Cannot read {target}: {exc}")
    for folder in ("references", "examples"):
        directory = root / folder
        if directory.is_symlink():
            add("SL300", "error", entry, 1, f"Use a local {folder}/ directory, not a symlink.")
            continue
        for resource in sorted(directory.rglob("*.md")):
            if resource.resolve() not in reached:
                add("SL302", "warning", resource, 1, "No Markdown link from SKILL.md or a reachable guide; add a conditional load path.")
    return report
