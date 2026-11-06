# skillslim

A template and linter for small skill entrypoints. Keep common-case instructions in `SKILL.md`; link to deeper guidance only when needed.

Requires Python 3.11+. No runtime dependencies, services, or parent-repository files. Installation uses setuptools. MIT licensed.

## Install and run

Requires Python 3.11 or newer. No runtime dependencies. Source install only; this package is not published to PyPI. `python3` in the macOS and Linux steps must be 3.11 or newer.

macOS or Linux, from the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install .
```

Windows PowerShell is second. Create the virtual environment with Python 3.11, then activate the `Scripts` directory:

```powershell
py -3.11 -m venv .venv
.venv\Scripts\Activate.ps1
pip install .
```

These are documented commands. The GitHub Actions workflow runs on Linux and Windows; that is not a claim that a maintainer ran the macOS or Windows install locally.

```sh
skillslim lint examples --recursive --strict
skillslim init my-skill
skillslim lint my-skill
skillslim lint my-skill --format json --strict
skillslim compare before/SKILL.md after/SKILL.md
```

`init` creates a complete technical-update skill and refuses any existing destination. Its folder name becomes its skill name: use lowercase letters, digits, and single hyphens, up to 64 characters. Adapt the content for a different task.

```text
my-skill/
  SKILL.md
  references/evidence.md
  examples/update.md
```

There is no root `SKILL.md` in this repository. Do not add one that duplicates the CLI. The skill users copy is the packaged template at `src/skillslim/template/`. `skillslim init` writes that template and replaces `{{name}}`. `examples/release-notes/` is another complete skill, not the CLI. Copy the skill directory itself so the destination contains `SKILL.md` directly; do not nest an extra folder of the same name. The copied folder needs no skillslim installation.

Handle the common case from `SKILL.md` alone. Use relative Markdown links saying when to read each guide. Short skills do not need extra folders.

## Host skill paths

Install locations below are file paths and invocation names. They do not establish that every host was exercised or that behavior matches across hosts. `<name>` is the skill folder name. Cursor's frontmatter `name` must match that folder. Antigravity requires a non-empty `description`.

| Host | Project | User | How to invoke |
| --- | --- | --- | --- |
| Grok | `.grok/skills/<name>/` | `~/.grok/skills/<name>/` | `/<name>` |
| Grok Bot | (same user path) | `~/.grok/skills/<name>/` on the bot computer, plus a paste-in prompt | Same `SKILL.md` |
| Cursor | `.cursor/skills/<name>/` | `~/.cursor/skills/<name>/` | `/<name>`; name matches folder |
| OpenAI / ChatGPT app | `.agents/skills/<name>/` | `~/.agents/skills/<name>/` | Zip upload via Plugins → Skills → Add. Codex `$<name>` |
| Antigravity | `.agents/skills/<name>/` (one level) | `~/.gemini/config/skills/<name>/`; CLI `~/.gemini/antigravity-cli/skills/<name>/` | `description` required |
| Claude | `.claude/skills/<name>/` | `~/.claude/skills/<name>/` | `/<name>` |

macOS or Linux, from any working directory (project scope uses the current directory):

```sh
bash scripts/install-skill.sh --host cursor --scope project --name my-skill
```

Windows PowerShell is second:

```powershell
powershell -File scripts\install-skill.ps1 --host cursor --scope project --name my-skill
```

`scripts/install-skill.sh` and `scripts/install-skill.ps1` take an optional skill directory. If omitted, they use the packaged template only when that directory contains `SKILL.md`. `--host` is `grok`, `grok-bot`, `cursor`, `openai`, `antigravity`, `claude`, or `all`. `--scope` is `project` (default) or `user`. `--name` sets the folder name and replaces `{{name}}`. Grok Bot always copies to `~/.grok/skills/<name>/` and prints a paste-in prompt of the same `SKILL.md`. Antigravity user scope copies to both the `~/.gemini/config/skills/<name>/` path and the CLI path. The destination skill folder is replaced; its contents are not placed inside another `<name>` directory.

## Checks and exit codes

| Rule | Level | Checks |
| --- | --- | --- |
| SL000 | Error | Missing/unreadable entrypoint or linked Markdown |
| SL001 | Error | Frontmatter delimiters, required-field presence, nonempty body |
| SL100 | Warning / error | Above 500 / 1,000 estimated entrypoint tokens |
| SL200 | Warning | Reference-like headings, such as Background or Examples |
| SL201 | Warning | Direct instructions to always/must read/load all/every resource |
| SL202 | Warning | More than 20 fenced lines, including fence delimiters |
| SL300 | Error | Links outside the skill, escaping entrypoint, or symlinked support directory |
| SL301 | Error | Missing local linked file |
| SL302 | Warning | Markdown in references/ or examples/ without a reachable link |

Budgets are skillslim defaults, not Agent Skills requirements. Override them with `--warn-tokens 600 --max-tokens 1200`.

Exit **0** passes; **1** means errors, or warnings with opt-in `--strict`; **2** means invalid usage or a CLI failure. Unreadable lint inputs are findings. Other file-operation failures go to stderr. JSON includes `schema_version`, `token_method`, and `reports`, with paths, estimates, rule IDs, severities, lines, and messages. See `skillslim --help` and each command's `--help`.

Recursive scans skip `.git`, `.venv`, `venv`, `node_modules`, `build`, `dist`, and `__pycache__` directories. Finding no skills fails rather than silently passing.

## Limitations and what this does not prove

These checks are heuristics. A pass does not prove useful instructions, correct agent behavior, or valid YAML. Frontmatter checking is limited; use a full Agent Skills validator separately. Heading checks may flag useful material or miss narrative bloat. Review warnings before removing essential instructions.

Link checks follow relative Markdown links through reachable guides. They support inline links, angle-bracket destinations, and reference definitions; ignore external URLs, anchors, inline code, and fenced code. Plain-text paths, complex Markdown syntax, anchor validity, and whether routing language is actually conditional are outside coverage. Use explicit Markdown links for load paths. Relative links in supporting guides resolve from that guide's directory.

Token estimates are `ceil(characters / 4)` over decoded text, including frontmatter, with line endings normalized and a leading UTF-8 BOM removed. This is a size proxy, not tokenizer output; accuracy varies by language and content.

`compare` reports estimated entrypoint reduction and requires two nonblank files. It excludes on-demand reads and does not verify equivalent content. Entrypoint reduction is **not proven average-turn savings**. No savings percentage is validated.

To evaluate savings, keep equivalent guidance in monolithic and split versions. Run representative requests, record every file actually loaded, and count tokens with the target model's tokenizer. Compare behavior and common versus advanced cases, then weight results by observed usage.

No hosting, marketplace, automatic rewriting, model calls, telemetry, or agent-specific extensions.

## Development

macOS or Linux:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
python -m unittest discover -s tests -v
skillslim lint examples --recursive --strict
skillslim lint src/skillslim/template --strict
```

Windows PowerShell is second: activate `.venv\Scripts\Activate.ps1`, then run the same `pip`, `unittest`, and `skillslim` commands.

The GitHub Actions workflow is configured for Python 3.11 and 3.13 on Linux and Windows, with this folder as the repository root. It installs the package, runs tests, and lints the example. Configured CI coverage is not a claim that every platform has been verified locally.
