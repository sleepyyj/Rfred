#!/bin/bash
# Next semver tag for a main push.
#
# Beszel-style tags: vMAJOR.MINOR.PATCH. A push to main always releases.
# The tag points at that commit. Nothing pushes a follow-up version commit.
#
#   feat: ...                 minor
#   fix: / chore: / anything  patch
#   type!: or BREAKING CHANGE major
#   several commits           the highest of those
#
# Usage: next-version.sh [auto|major|minor|patch]
# Prints shell assignments: bump, ver, tag, prev
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

mode="${1:-auto}"
case "$mode" in
  auto|major|minor|patch) ;;
  --check) mode="--check" ;;
  *)
    echo "Usage: next-version.sh [auto|major|minor|patch|--check]" >&2
    exit 1
    ;;
esac

# Highest change in one commit message. Major outranks minor, minor outranks patch.
classify() {
  local text="$1"
  if printf '%s\n' "$text" | grep -Eq '^[[:alnum:]]+(\([^)]*\))?!:|^BREAKING CHANGE:'; then
    printf 'major'
  elif printf '%s\n' "$text" | grep -Eq '^[Ff]eat(\([^)]*\))?:'; then
    printf 'minor'
  else
    printf 'patch'
  fi
}

higher() {
  case "$1:$2" in
    major:*|*:major) printf 'major' ;;
    minor:*|*:minor) printf 'minor' ;;
    *) printf 'patch' ;;
  esac
}

if [ "$mode" = "--check" ]; then
  [ "$(classify 'feat: Add pins')" = minor ]
  [ "$(classify 'fix: Skip a duplicate paste')" = patch ]
  [ "$(classify 'chore: Note the signing certificate')" = patch ]
  [ "$(classify 'Show clipboard previews')" = patch ]
  [ "$(classify 'feat!: Replace the pasteboard format')" = major ]
  [ "$(classify "$(printf '%s\n\n%s' 'fix: tidy clips' 'BREAKING CHANGE: drop v1 clips')")" = major ]
  [ "$(higher patch minor)" = minor ]
  [ "$(higher minor major)" = major ]
  [ "$(higher patch patch)" = patch ]
  echo "next-version checks passed"
  exit 0
fi

last="$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
if [ -n "$last" ] && [ -z "$(git rev-list "${last}..HEAD")" ]; then
  echo "No commits since ${last}" >&2
  exit 2
fi

if [ "$mode" = auto ]; then
  mode="patch"
  if [ -n "$last" ]; then
    while IFS= read -r -d $'\x1e' message; do
      [ -n "$message" ] || continue
      mode="$(higher "$mode" "$(classify "$message")")"
    done < <(git log --format='%s%n%b%x1e' "${last}..HEAD")
  fi
fi

if [ -n "$last" ]; then
  ver="${last#v}"
else
  ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
fi
maj="${ver%%.*}"
rest="${ver#*.}"
min="${rest%%.*}"
pat="${rest#*.}"
case "$mode" in
  major)
    maj=$((maj + 1))
    min=0
    pat=0
    ;;
  minor)
    min=$((min + 1))
    pat=0
    ;;
  patch)
    pat=$((pat + 1))
    ;;
esac
ver="${maj}.${min}.${pat}"
tag="v${ver}"
if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "Tag ${tag} already exists" >&2
  exit 1
fi
printf 'bump=%s\nver=%s\ntag=%s\nprev=%s\n' "$mode" "$ver" "$tag" "${last:-}"
