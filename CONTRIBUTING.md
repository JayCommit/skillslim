# Contributing

Requires Python 3.11 or newer. Runtime dependencies stay empty; use the standard library. setuptools is a build dependency only.

macOS or Linux, from the repository root. `python3` must be Python 3.11 or newer; if it is older, use `python3.11` in the same three steps:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
python -m unittest discover -s tests -v
skillslim lint examples --recursive --strict
skillslim lint src/skillslim/template --strict
```

Windows is second. Create the environment with Python 3.11 and activate it with `.venv\Scripts\Activate.ps1`, then run the same `pip`, `unittest`, and `skillslim` commands.

For a packaging change, also install non-editably in a fresh environment (`python -m pip install .`) and, from an empty directory outside the checkout, run `skillslim init`, strict lint (text and JSON), and `skillslim compare`.

Token sizes are `ceil(characters / 4)` estimates, including frontmatter. Do not report them as tokenizer counts or as measured turn savings.

Open a GitHub issue for bugs. Include the command, Python and OS versions, a minimal sanitized skill, the actual finding or exit code, and the expected behavior.
