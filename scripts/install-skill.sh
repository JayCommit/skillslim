#!/usr/bin/env bash
# Copy a skill directory into one host path without nesting the folder twice.
# macOS or Linux. Windows uses scripts/install-skill.ps1.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-skill.sh [SKILL_DIR] --host HOST [--scope user|project] [--name NAME]

Copy a skill directory into a host skill path. The destination contains the
skill's files directly (SKILL.md at the top); it does not nest <name>/<name>.

SKILL_DIR must be a directory containing SKILL.md. If omitted, the packaged
template (src/skillslim/template next to this script, otherwise the installed
skillslim template) is used only when that directory contains SKILL.md.

--host   grok | grok-bot | cursor | openai | antigravity | claude | all
--scope  project (default, current directory) or user ($HOME)
--name   skill folder name. Default: frontmatter name, else the directory name.
         {{name}} in copied files is replaced with this name.

Paths, with <name> replaced by the skill folder name:
  Grok          .grok/skills/<name>/                         ~/.grok/skills/<name>/
                Invoke /<name>.
  Grok Bot      ~/.grok/skills/<name>/ on the bot computer, plus a paste-in prompt.
                Same SKILL.md. Either scope uses that user path.
  Cursor        .cursor/skills/<name>/                       ~/.cursor/skills/<name>/
                Invoke /<name>. name matches folder.
  OpenAI        .agents/skills/<name>/                       ~/.agents/skills/<name>/
                Zip upload via Plugins → Skills → Add. Codex $<name>.
  Antigravity   .agents/skills/<name>/ one level
                ~/.gemini/config/skills/<name>/
                CLI ~/.gemini/antigravity-cli/skills/<name>/
                description required. User scope writes both home paths.
  Claude        .claude/skills/<name>/                       ~/.claude/skills/<name>/
                Invoke /<name>.
EOF
}

fail() {
  echo "install-skill: $*" >&2
  exit 2
}

HOST=""
SCOPE="project"
NAME=""
SKILL_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --host)
      [[ $# -ge 2 ]] || fail "--host requires a value"
      HOST="$2"
      shift 2
      ;;
    --host=*)
      HOST="${1#*=}"
      shift
      ;;
    --scope)
      [[ $# -ge 2 ]] || fail "--scope requires a value"
      SCOPE="$2"
      shift 2
      ;;
    --scope=*)
      SCOPE="${1#*=}"
      shift
      ;;
    --name)
      [[ $# -ge 2 ]] || fail "--name requires a value"
      NAME="$2"
      shift 2
      ;;
    --name=*)
      NAME="${1#*=}"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      fail "unknown flag: $1"
      ;;
    *)
      [[ -z "$SKILL_DIR" ]] || fail "unexpected argument: $1"
      SKILL_DIR="$1"
      shift
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  [[ -z "$SKILL_DIR" ]] || fail "unexpected argument: $1"
  SKILL_DIR="$1"
  shift
  [[ $# -eq 0 ]] || fail "unexpected argument: $1"
fi

case "$HOST" in
  grok|grok-bot|cursor|openai|antigravity|claude|all) ;;
  "") fail "--host is required (grok|grok-bot|cursor|openai|antigravity|claude|all)" ;;
  *) fail "unknown --host: $HOST" ;;
esac

case "$SCOPE" in
  user|project) ;;
  *) fail "unknown --scope: $SCOPE (use user or project)" ;;
esac

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PACKAGED="$REPO_ROOT/src/skillslim/template"

resolve_installed_template() {
  local py output
  for py in python3.11 python3 python; do
    if command -v "$py" >/dev/null 2>&1; then
      output=$("$py" -c 'from pathlib import Path
try:
    import skillslim
except Exception:
    raise SystemExit(1)
path = Path(skillslim.__file__).resolve().parent / "template"
skill = path / "SKILL.md"
if skill.is_file() and skill.stat().st_size > 0:
    print(path)
else:
    raise SystemExit(1)' 2>/dev/null) || true
      if [[ -n "${output:-}" && -f "$output/SKILL.md" ]]; then
        printf '%s\n' "$output"
        return 0
      fi
    fi
  done
  return 1
}

if [[ -z "$SKILL_DIR" ]]; then
  if [[ -d "$PACKAGED" ]]; then
    if [[ -f "$PACKAGED/SKILL.md" && -s "$PACKAGED/SKILL.md" ]]; then
      SKILL_DIR="$PACKAGED"
    else
      fail "packaged template is not a valid skill (missing SKILL.md): $PACKAGED"
    fi
  else
    SKILL_DIR=$(resolve_installed_template) || fail "no skill directory given and the packaged template is not a valid skill with SKILL.md"
  fi
fi

if [[ -f "$SKILL_DIR" && "$(basename "$SKILL_DIR")" == "SKILL.md" ]]; then
  SKILL_DIR=$(dirname "$SKILL_DIR")
fi

[[ -d "$SKILL_DIR" ]] || fail "skill directory not found: $SKILL_DIR"
SKILL_DIR=$(cd "$SKILL_DIR" && pwd)
[[ -f "$SKILL_DIR/SKILL.md" && -s "$SKILL_DIR/SKILL.md" ]] || fail "not a valid skill (SKILL.md is missing or empty): $SKILL_DIR"

frontmatter_value() {
  # $1 file, $2 key. Prints the value or nothing. Handles a simple block scalar.
  awk -v key="$2" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    NR == 1 && $0 != "---" { exit 0 }
    NR == 1 { in_fm = 1; next }
    in_fm && $0 == "---" { exit 0 }
    in_fm && collecting {
      if ($0 ~ /^[ \t]/) {
        piece = trim($0)
        if (piece != "") {
          if (value == "") value = piece
          else value = value " " piece
        }
        next
      }
      collecting = 0
    }
    in_fm && !have && $0 ~ "^" key ":[ \t]*" {
      line = $0
      sub("^" key ":[ \t]*", "", line)
      line = trim(line)
      if (line == "|" || line == ">" || line == "|-" || line == ">-" || line == "|+" || line == ">+") {
        collecting = 1
        have = 1
        next
      }
      value = line
      have = 1
    }
    END {
      if (!have) exit 0
      if (value ~ /^".*"$/ || value ~ /^'\''.*'\''$/) value = substr(value, 2, length(value) - 2)
      if (value == "" || value == "null" || value == "~") exit 0
      print value
    }
  ' "$1"
}

value_is_empty() {
  case "$1" in
    ""|"\"\""|"''"|null|~|"|"|">"|"|-"|">-"|"|+"|">+") return 0 ;;
    *) return 1 ;;
  esac
}

raw_name=$(frontmatter_value "$SKILL_DIR/SKILL.md" "name" || true)
if [[ -z "$NAME" ]]; then
  if [[ "$raw_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#raw_name} -le 64 ]]; then
    NAME="$raw_name"
  else
    NAME=$(basename "$SKILL_DIR")
  fi
fi

if [[ ! "$NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ || ${#NAME} -gt 64 ]]; then
  fail "name must be 1-64 lowercase letters, digits, and single hyphens: $NAME"
fi

stage=$(mktemp -d)
list=$(mktemp)
trap 'rm -rf "$stage"; rm -f "$list"' EXIT
cp -R "$SKILL_DIR"/. "$stage"/

find "$stage" -type f -print0 > "$list"
while IFS= read -r -d '' file; do
  if grep -F -q '{{name}}' "$file"; then
    tmp=$(mktemp)
    sed "s/{{name}}/${NAME}/g" "$file" > "$tmp"
    mv "$tmp" "$file"
  fi
done < "$list"

installed_name=$(frontmatter_value "$stage/SKILL.md" "name" || true)
installed_description=$(frontmatter_value "$stage/SKILL.md" "description" || true)

want_grok=0
want_grok_bot=0
want_cursor=0
want_openai=0
want_antigravity=0
want_claude=0
case "$HOST" in
  all)
    want_grok=1
    want_grok_bot=1
    want_cursor=1
    want_openai=1
    want_antigravity=1
    want_claude=1
    ;;
  grok) want_grok=1 ;;
  grok-bot) want_grok_bot=1 ;;
  cursor) want_cursor=1 ;;
  openai) want_openai=1 ;;
  antigravity) want_antigravity=1 ;;
  claude) want_claude=1 ;;
esac

if [[ "$want_cursor" -eq 1 && -n "$installed_name" && "$installed_name" != "$NAME" ]]; then
  fail "Cursor requires the frontmatter name to match the folder ($NAME); SKILL.md name is $installed_name"
fi

if [[ "$want_antigravity" -eq 1 ]] && value_is_empty "$installed_description"; then
  fail "Antigravity requires a non-empty description in SKILL.md"
fi

if [[ "$SCOPE" == "user" || "$want_grok_bot" -eq 1 ]]; then
  [[ -n "${HOME:-}" ]] || fail "HOME is not set"
fi

project_root=$(pwd)
user_root="${HOME:-}"
project_root=${project_root%/}
user_root=${user_root%/}

DESTS=()
add_dest() {
  local dest="$1"
  local existing
  if [[ ${#DESTS[@]} -gt 0 ]]; then
    for existing in "${DESTS[@]}"; do
      [[ "$existing" == "$dest" ]] && return 0
    done
  fi
  DESTS+=("$dest")
}

if [[ "$want_grok" -eq 1 ]]; then
  if [[ "$SCOPE" == "project" ]]; then
    add_dest "$project_root/.grok/skills/$NAME"
  else
    add_dest "$user_root/.grok/skills/$NAME"
  fi
fi
if [[ "$want_grok_bot" -eq 1 ]]; then
  add_dest "$user_root/.grok/skills/$NAME"
fi
if [[ "$want_cursor" -eq 1 ]]; then
  if [[ "$SCOPE" == "project" ]]; then
    add_dest "$project_root/.cursor/skills/$NAME"
  else
    add_dest "$user_root/.cursor/skills/$NAME"
  fi
fi
if [[ "$want_openai" -eq 1 ]]; then
  if [[ "$SCOPE" == "project" ]]; then
    add_dest "$project_root/.agents/skills/$NAME"
  else
    add_dest "$user_root/.agents/skills/$NAME"
  fi
fi
if [[ "$want_antigravity" -eq 1 ]]; then
  if [[ "$SCOPE" == "project" ]]; then
    add_dest "$project_root/.agents/skills/$NAME"
  else
    add_dest "$user_root/.gemini/config/skills/$NAME"
    add_dest "$user_root/.gemini/antigravity-cli/skills/$NAME"
  fi
fi
if [[ "$want_claude" -eq 1 ]]; then
  if [[ "$SCOPE" == "project" ]]; then
    add_dest "$project_root/.claude/skills/$NAME"
  else
    add_dest "$user_root/.claude/skills/$NAME"
  fi
fi

assert_safe_dest() {
  case "$1" in
    */.grok/skills/"$NAME"|*/.cursor/skills/"$NAME"|*/.agents/skills/"$NAME"|*/.claude/skills/"$NAME"|*/.gemini/config/skills/"$NAME"|*/.gemini/antigravity-cli/skills/"$NAME")
      ;;
    *)
      fail "refusing unexpected destination: $1"
      ;;
  esac
}

source_prefix="$SKILL_DIR/"
for dest in "${DESTS[@]}"; do
  assert_safe_dest "$dest"
  case "$dest/" in
    "$source_prefix"*) fail "destination is inside the source skill: $dest" ;;
  esac
  case "$source_prefix" in
    "$dest/"*) fail "source skill is inside the destination: $dest" ;;
  esac
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$stage"/. "$dest"/
  echo "Installed $dest"
done

if [[ "$want_grok" -eq 1 ]]; then
  echo "Grok: invoke /$NAME."
fi
if [[ "$want_grok_bot" -eq 1 ]]; then
  cat <<EOF
Grok Bot paste-in prompt (same SKILL.md). On the bot computer the folder is ~/.grok/skills/${NAME}/.
If that computer cannot read the copied folder, paste the prompt below.

----- BEGIN paste-in prompt -----
Follow the ${NAME} skill. The instructions are this SKILL.md; do not invent a different procedure.

EOF
  cat "$stage/SKILL.md"
  cat <<'EOF'

----- END paste-in prompt -----
EOF
fi
if [[ "$want_cursor" -eq 1 ]]; then
  echo "Cursor: invoke /$NAME. name matches folder."
fi
if [[ "$want_openai" -eq 1 ]]; then
  echo "OpenAI / ChatGPT app: zip the skill folder and upload it via Plugins → Skills → Add."
  echo "Codex: \$${NAME}"
fi
if [[ "$want_antigravity" -eq 1 ]]; then
  echo "Antigravity: description required. Project path is .agents/skills/${NAME}/ (one level). User path is ~/.gemini/config/skills/${NAME}/. CLI path is ~/.gemini/antigravity-cli/skills/${NAME}/."
fi
if [[ "$want_claude" -eq 1 ]]; then
  echo "Claude: invoke /$NAME."
fi

exit 0
