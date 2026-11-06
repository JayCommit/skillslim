"""CLI and template generator."""

import argparse
from importlib.resources import files
import json
import os
from pathlib import Path
import re
import shutil
import sys

from . import __version__
from .lint import estimate_tokens, lint_skill


def positive(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def copy_template(source, destination, name):
    for child in source.iterdir():
        target = destination / child.name
        if child.is_dir():
            target.mkdir()
            copy_template(child, target, name)
        else:
            target.write_text(child.read_text(encoding="utf-8").replace("{{name}}", name), encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Keep skill core rules small and load details on demand.")
    parser.add_argument("--version", action="version", version=__version__)
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="create a skill from the bundled template")
    init.add_argument("path", type=Path)
    lint = commands.add_parser("lint", help="check a skill or recursively discover skills")
    lint.add_argument("path", nargs="?", default=Path("."), type=Path)
    lint.add_argument("--recursive", action="store_true")
    lint.add_argument("--format", choices=("text", "json"), default="text")
    lint.add_argument("--strict", action="store_true", help="fail on warnings as well as errors")
    lint.add_argument("--warn-tokens", type=positive, default=500)
    lint.add_argument("--max-tokens", type=positive, default=1000)
    compare = commands.add_parser("compare", help="estimate entrypoint size reduction against a baseline")
    compare.add_argument("baseline", type=Path)
    compare.add_argument("slim", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "init":
            name = args.path.resolve().name
            if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name) or len(name) > 64:
                parser.error("skill folder name must be 1–64 lowercase letters, digits, and single hyphens")
            # Refuse even an empty existing folder, so no user files can be overwritten.
            args.path.mkdir(parents=True, exist_ok=False)
            try:
                copy_template(files("skillslim").joinpath("template"), args.path, name)
            except Exception:
                shutil.rmtree(args.path)
                raise
            print(f"Created {args.path}. Adapt its task, core rules, and conditional guides before use.")
            return 0
        if args.command == "compare":
            baseline = args.baseline.read_text(encoding="utf-8-sig")
            slim = args.slim.read_text(encoding="utf-8-sig")
            if not baseline.strip() or not slim.strip():
                parser.error("baseline and candidate must both contain text")
            before = estimate_tokens(baseline)
            after = estimate_tokens(slim)
            print(json.dumps({"baseline_estimated_tokens": before, "slim_estimated_tokens": after,
                              "entrypoint_reduction_percent": round((1 - after / before) * 100, 1),
                              "method": "ceil(characters / 4); excludes on-demand reads; not measured turn savings"}, indent=2))
            return 0
        if args.warn_tokens > args.max_tokens:
            parser.error("--warn-tokens must not exceed --max-tokens")
        if args.recursive:
            if not args.path.is_dir():
                parser.error("--recursive requires a directory")
            ignored = {".git", ".venv", "venv", "node_modules", "build", "dist", "__pycache__"}
            paths = []
            for directory, folders, filenames in os.walk(args.path):
                folders[:] = sorted(folder for folder in folders if folder not in ignored)
                if "SKILL.md" in filenames:
                    paths.append(Path(directory) / "SKILL.md")
            paths.sort()
            if not paths:
                parser.error("no SKILL.md files found")
        else:
            if args.path.is_file() and args.path.name != "SKILL.md":
                parser.error("expected a skill directory or SKILL.md")
            paths = [args.path]
        reports = [lint_skill(p, args.warn_tokens, args.max_tokens) for p in paths]
        if args.format == "json":
            print(json.dumps({"schema_version": 1, "token_method": "ceil(characters / 4)",
                              "reports": [r.to_dict() for r in reports]}, indent=2))
        else:
            for report in reports:
                print(f"{report.path}: ~{report.estimated_tokens} tokens")
                for finding in report.findings:
                    print(f"  {finding.path}:{finding.line}: {finding.severity} {finding.rule}: {finding.message}")
            print(f"Checked {len(reports)} skill(s).")
        return int(any(f.severity == "error" or args.strict for r in reports for f in r.findings))
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"skillslim: {exc}", file=sys.stderr)
        return 2
