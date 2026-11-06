# Working on skillslim

skillslim is a Python CLI (`init`, `lint`, `compare`) and a bundled progressive-disclosure skill template. Keep common-case instructions small and put conditional guidance in linked files. This directory is self-contained and must work as a standalone repository.

## Layout

- `src/skillslim/cli.py`: commands, discovery, template generation, exit codes.
- `src/skillslim/lint.py`: heuristic checks, Markdown links, size estimates.
- `src/skillslim/template/`: packaged starter and its references/examples.
- `scripts/install-skill.sh` and `scripts/install-skill.ps1`: copy a skill directory into a host path without double nesting. There is no root `SKILL.md`; the skill users copy is `src/skillslim/template/`.
- `examples/release-notes/`: complete standalone example skill.
- `tests/test_skillslim.py`: standard-library unittest suite.
- `pyproject.toml`: package metadata, entrypoint, bundled resources.
- `.github/workflows/ci.yml`: install, tests, strict example linting.
- `README.md`: public usage and limitations.

## Setup and checks

Requires Python 3.11+. Run from this directory.

macOS or Linux (`python3` must be 3.11 or newer):

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

Windows PowerShell is second. Create the environment with Python 3.11, then activate `.venv\Scripts\Activate.ps1`.

Then:

```sh
python -m unittest discover -s tests -v
skillslim lint examples --recursive --strict
skillslim lint src/skillslim/template --strict
```

There is no configured formatter or separate Python linter. Template linting does not validate the unsubstituted `{{name}}` as an Agent Skills name.

## Constraints

- Keep runtime dependencies empty; use the standard library. setuptools is a build dependency.
- Preserve no-overwrite initialization, warning/error separation, opt-in `--strict`, and documented JSON/exit-code contracts.
- Defaults warn above 500 and error above 1,000 estimated entrypoint tokens. These are project budgets, not specification limits.
- Estimates use `ceil(characters / 4)`, including frontmatter. Never call them tokenizer counts or proven turn savings.
- Keep common-case instructions usable without extra reads. Link conditional guidance with relative Markdown paths; do not require bulk loading.
- Do not add features, rules, dependencies, or examples without a concrete task need. Do not rewrite skills automatically, introduce parent-directory dependencies, or claim untested agent/platform compatibility.

## Before committing

For code changes, run the checks above and add regression coverage only for real gaps. For packaging changes, also install non-editably in a fresh environment and generate/lint a skill from outside the checkout. For documentation-only edits, verify commands against `--help` and check local links; no new tests are needed. Review `git diff --check` and the diff for scope, secrets, machine-specific paths, and accurate claims. Report what ran and what remains unverified.
