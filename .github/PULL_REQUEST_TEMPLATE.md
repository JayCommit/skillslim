## What changed

## Why

## How tested

- `python -m unittest discover -s tests -v`
- `skillslim lint examples --recursive --strict`
- `skillslim lint src/skillslim/template --strict`

Note Python version and anything you did not run.

## Checks

- [ ] No new runtime dependencies
- [ ] Estimates are still described as `ceil(characters / 4)`, not tokenizer counts or turn savings
- [ ] No secrets or machine-specific paths
