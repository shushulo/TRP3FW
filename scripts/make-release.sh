#!/usr/bin/env bash
#
# make-release.sh -- build the stripped release branch from the dev branch.
#
# Model (three locations, two branches per line):
#
#   v<N>-dev   gitea only, NEVER GitHub.  Full tree: code + tests/ + thoughts/
#              + CLAUDE.md.  This is where you work.
#   v<N>       gitea AND GitHub.  Stripped: code only.  Regenerated from
#              v<N>-dev by this script at each release; never committed to
#              directly, and force-moved every time.
#
# Versioning is unified with the branch line: branch v1.6 -> TRP3FW.VERSION
# "1.6.0" -> tag "v1.6.0".  core/init.lua is the single source of truth; the
# .toc, the README badge and the tag are all checked against it below.
#
# This script PREPARES the release locally and stops.  It prints the push
# commands but never pushes, and never touches GitHub.  Review, then push.
#
# Usage:   scripts/make-release.sh [--dev-branch v1.6-dev]
#
set -euo pipefail

DEV_BRANCH="v1.6-dev"
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dev-branch) DEV_BRANCH="$2"; shift 2 ;;
		-h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

# Release branch is the dev branch minus the -dev suffix: v1.6-dev -> v1.6
RELEASE_BRANCH="${DEV_BRANCH%-dev}"
if [[ "$RELEASE_BRANCH" == "$DEV_BRANCH" ]]; then
	echo "error: --dev-branch must end in -dev (got '$DEV_BRANCH')" >&2
	exit 1
fi

cd "$(git rev-parse --show-toplevel)"

fail() { echo "  FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok:   $*"; }

# --------------------------------------------------------------------------
# Preflight.  Everything that can reject the release happens BEFORE we mutate
# any branch, so a failed run leaves the repo exactly as it found it.
# --------------------------------------------------------------------------
echo "==> Preflight"

[[ -n "$(git status --porcelain)" ]] && \
	fail "working tree is dirty; commit or stash first"
ok "working tree clean"

git rev-parse --verify --quiet "$DEV_BRANCH" >/dev/null || \
	fail "dev branch '$DEV_BRANCH' does not exist"
ok "dev branch '$DEV_BRANCH' exists"

STARTING_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# Read the canonical version out of the DEV branch (not the working tree, which
# may be sitting on some other branch).
VERSION="$(git show "$DEV_BRANCH:core/init.lua" \
	| sed -n 's/^TRP3FW\.VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
	| head -1)"
[[ -n "$VERSION" ]] || fail "could not read TRP3FW.VERSION from core/init.lua"
ok "core/init.lua declares version '$VERSION'"

# .toc must agree.
TOC_VERSION="$(git show "$DEV_BRANCH:TRP3FW.toc" \
	| sed -n 's/^##[[:space:]]*Version:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' \
	| head -1)"
[[ "$TOC_VERSION" == "$VERSION" ]] || \
	fail "TRP3FW.toc says '$TOC_VERSION' but core/init.lua says '$VERSION'"
ok "TRP3FW.toc agrees"

# README badge must agree.  The badge escapes '-' as '--', so 1.6.0-beta would
# appear as 1.6.0--beta; normalise before comparing.
README_VERSION="$(git show "$DEV_BRANCH:README.md" \
	| sed -n 's|.*/badge/version-\([^-][^)]*\)-blue\.svg.*|\1|p' \
	| head -1 | sed 's/--/-/g')"
[[ "$README_VERSION" == "$VERSION" ]] || \
	fail "README badge says '$README_VERSION' but core/init.lua says '$VERSION'"
ok "README badge agrees"

# Branch name must agree with the version: v1.6 <-> 1.6.x
BRANCH_SERIES="${RELEASE_BRANCH#v}"
case "$VERSION" in
	"$BRANCH_SERIES".*) ok "version '$VERSION' matches branch series '$BRANCH_SERIES'" ;;
	*) fail "version '$VERSION' does not match release branch '$RELEASE_BRANCH'" ;;
esac

# Refuse to rebuild a version that is already tagged -- that would mean either a
# double release or an untracked version bump.
TAG="v$VERSION"
if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
	fail "tag '$TAG' already exists; bump TRP3FW.VERSION before releasing again"
fi
ok "tag '$TAG' is free"

# --------------------------------------------------------------------------
# Build.  Force-move the release branch onto the dev tip, then strip.
# --------------------------------------------------------------------------
echo "==> Building $RELEASE_BRANCH from $DEV_BRANCH"

if git rev-parse --verify --quiet "$RELEASE_BRANCH" >/dev/null; then
	PREVIOUS="$(git rev-parse --short "$RELEASE_BRANCH")"
	echo "  note: discarding previous $RELEASE_BRANCH ($PREVIOUS)"
fi

git branch -f "$RELEASE_BRANCH" "$DEV_BRANCH"
git checkout --quiet "$RELEASE_BRANCH"

# Everything the dev branch carries that must not ship.
git rm -r --quiet --ignore-unmatch tests/ thoughts/ CLAUDE.md scripts/

# Drop the test wiring from the .toc: the WoWUnit OptionalDep, and every line
# from the integration-tests comment to end of file.
python - "$VERSION" <<'PYEOF'
import re, sys

with open("TRP3FW.toc", encoding="utf-8", newline="") as fh:
    toc = fh.read()

toc = toc.replace(
    "## OptionalDeps: TotalRP3, MyRolePlay, XRP, WoWUnit",
    "## OptionalDeps: TotalRP3, MyRolePlay, XRP",
)

# Remove the trailing test-loading block (integration tests + WoWUnit specs).
toc = re.sub(r"\n*# Integration tests.*$", "\n", toc, flags=re.S)

with open("TRP3FW.toc", "w", encoding="utf-8", newline="") as fh:
    fh.write(toc)
PYEOF

# Verify nothing test-shaped survived into the shipping .toc.
if grep -qiE "wowunit|tests\\\\|tests/" TRP3FW.toc; then
	echo "  FAIL: TRP3FW.toc still references tests after stripping:" >&2
	grep -niE "wowunit|tests\\\\|tests/" TRP3FW.toc >&2
	git checkout --quiet "$STARTING_BRANCH"
	exit 1
fi
ok "TRP3FW.toc stripped clean"

# Every .lua the .toc loads must actually exist in the stripped tree, or the
# addon breaks at load time for users.
MISSING=0
while IFS= read -r entry; do
	path="${entry//\\//}"
	[[ -f "$path" ]] || { echo "  FAIL: .toc loads missing file: $path" >&2; MISSING=1; }
done < <(grep -E '^[^#[:space:]].*\.(lua|xml)[[:space:]]*$' TRP3FW.toc | tr -d '\r')
[[ "$MISSING" -eq 0 ]] || { git checkout --quiet "$STARTING_BRANCH"; exit 1; }
ok "all .toc-referenced files present"

git add -A
git commit --quiet -m "Release $VERSION: strip dev-only tree for distribution

Regenerated from $DEV_BRANCH by scripts/make-release.sh. Removes tests/,
thoughts/, CLAUDE.md and scripts/, and drops the WoWUnit OptionalDep plus the
test-loading lines from TRP3FW.toc so the addon loads cleanly without them."

echo
echo "==> Done. $RELEASE_BRANCH is built at $(git rev-parse --short HEAD)"
echo
echo "Review:"
echo "    git show --stat $RELEASE_BRANCH"
echo "    git diff $DEV_BRANCH $RELEASE_BRANCH -- TRP3FW.toc"
echo
echo "Then tag and push (dev -> gitea only; release -> both):"
echo "    git tag -a $TAG -m 'TRP3FW $VERSION'"
echo "    git push gitea $DEV_BRANCH"
echo "    git push gitea $RELEASE_BRANCH --force-with-lease"
echo "    git push gitea $TAG"
echo "    git push origin $RELEASE_BRANCH --force-with-lease"
echo "    git push origin $TAG"
echo
echo "Returning to $STARTING_BRANCH"
git checkout --quiet "$STARTING_BRANCH"
