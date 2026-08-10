#!/usr/bin/env bash
#
# make-release.sh -- build the stripped release branch from the dev branch.
#
# Model (three branches, each with one job):
#
#   v<N>-dev   gitea only, NEVER GitHub.  Full tree: code + tests/ + thoughts/
#              + CLAUDE.md.  This is where you work.
#   v<N>       gitea AND GitHub.  Stripped: code only.  Regenerated from
#              v<N>-dev by this script at each release; never committed to
#              directly, and force-moved every time.
#   main       gitea AND GitHub.  Tracks the LATEST release, whatever series it
#              came from, so the GitHub landing page is never stale.  Same
#              stripped shape as v<N>; only ever updated by merging v<N> in,
#              which this script does for you.
#
# Versioning is unified with the branch LINE, not the patch number: branch v1.6
# carries the whole 1.6.x series (1.6.0, 1.6.1, ...).  Only a series bump earns
# a new branch (1.7.0 -> v1.7-dev -> v1.7).  core/init.lua is the single source
# of truth for the version; --bump rewrites the .toc and README badge from it so
# they cannot drift, and the tag is derived from it too.
#
# This script PREPARES the release locally and stops.  It builds the release
# branch, creates the tag, and merges into main -- all local.  It prints the
# push commands but never pushes, and never touches GitHub.  Review, then push.
#
# Nothing about a release is meant to live in your head: if a step is needed, it
# is either done here or printed at the end.  Adding a manual step to the
# process means adding it to this script.
#
# The headless test suite must pass before anything is built.  Point LUA at a
# Lua 5.1 interpreter if it is not on PATH (the usual Windows install location
# is tried automatically).
#
# Usage:   scripts/make-release.sh [--bump X.Y.Z] [--dev-branch v1.6-dev]
#                                  [--skip-tests] [--no-main]
#
#   --bump X.Y.Z  Set the version first: rewrites core/init.lua, TRP3FW.toc and
#                 the README badge, then commits that to the dev branch.  Without
#                 it the script releases whatever version the dev branch already
#                 declares.
#   --no-main     Build and tag, but do not merge into main.
#
set -euo pipefail

DEV_BRANCH="v1.6-dev"
SKIP_TESTS=0
BUMP_TO=""
MERGE_MAIN=1
MAIN_BRANCH="main"
while [[ $# -gt 0 ]]; do
	case "$1" in
		--bump)       BUMP_TO="$2"; shift 2 ;;
		--dev-branch) DEV_BRANCH="$2"; shift 2 ;;
		--skip-tests) SKIP_TESTS=1; shift ;;
		--no-main)    MERGE_MAIN=0; shift ;;
		-h|--help)    sed -n '2,44p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

# X.Y.Z only -- the tag, the branch-series check and the .toc all assume it.
if [[ -n "$BUMP_TO" && ! "$BUMP_TO" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "error: --bump expects X.Y.Z (got '$BUMP_TO')" >&2
	exit 2
fi

# Release branch is the dev branch minus the -dev suffix: v1.6-dev -> v1.6
RELEASE_BRANCH="${DEV_BRANCH%-dev}"
if [[ "$RELEASE_BRANCH" == "$DEV_BRANCH" ]]; then
	echo "error: --dev-branch must end in -dev (got '$DEV_BRANCH')" >&2
	exit 1
fi

cd "$(git rev-parse --show-toplevel)"

fail() { echo "  FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok:   $*"; }

# Always return to whatever branch the caller was on, however we exit -- an
# early failure must never strand them on the half-built release branch.
STARTING_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
restore_branch() {
	local current
	current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
	if [[ -n "$STARTING_BRANCH" && "$current" != "$STARTING_BRANCH" ]]; then
		git checkout --quiet "$STARTING_BRANCH" 2>/dev/null \
			|| echo "warning: could not return to $STARTING_BRANCH (you are on $current)" >&2
	fi
}
trap restore_branch EXIT

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

# --bump: rewrite the version in all three places from one argument, then commit
# it to the dev branch.  The three used to be edited by hand and the script only
# CHECKED that they agreed, which meant a release could fail preflight for a
# reason ("README badge says X") that was pure clerical drift.  Deriving them
# removes the drift instead of reporting it.
if [[ -n "$BUMP_TO" ]]; then
	if [[ "$STARTING_BRANCH" != "$DEV_BRANCH" ]]; then
		git checkout --quiet "$DEV_BRANCH" || fail "could not switch to $DEV_BRANCH to bump"
	fi

	python - "$BUMP_TO" <<'PYEOF'
import re, sys

version = sys.argv[1]
edits = [
    ("core/init.lua", r'(TRP3FW\.VERSION\s*=\s*")[^"]*(")', rf'\g<1>{version}\g<2>'),
    ("TRP3FW.toc",    r'(?m)^(##\s*Version:\s*).*$',        rf'\g<1>{version}'),
    # The badge escapes '-' as '--'; a plain X.Y.Z has none, but keep the
    # replacement confined to the version segment either way.
    ("README.md",     r'(badge/version-)[^-]*(-blue\.svg)',  rf'\g<1>{version}\g<2>'),
]

for path, pattern, repl in edits:
    with open(path, encoding="utf-8", newline="") as fh:
        src = fh.read()
    new, n = re.subn(pattern, repl, src, count=1)
    if n != 1:
        sys.exit(f"could not rewrite version in {path} (matched {n} times)")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(new)
PYEOF

	if [[ -n "$(git status --porcelain)" ]]; then
		git add core/init.lua TRP3FW.toc README.md
		git commit --quiet -m "Bump version to $BUMP_TO"
		ok "bumped to $BUMP_TO and committed to $DEV_BRANCH"
	else
		ok "already at $BUMP_TO; nothing to bump"
	fi
fi

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

# Headless test suite.  Run against the DEV branch's tree, which is what we are
# about to strip -- so check it out first if we are not already on it.
if [[ "$SKIP_TESTS" -eq 1 ]]; then
	echo "  SKIPPED: tests (--skip-tests)"
else
	LUA="${LUA:-}"
	if [[ -z "$LUA" ]]; then
		for candidate in lua lua5.1 "/c/Program Files (x86)/Lua/5.1/lua.exe"; do
			if command -v "$candidate" >/dev/null 2>&1; then LUA="$candidate"; break; fi
		done
	fi
	[[ -n "$LUA" ]] || fail "no Lua 5.1 interpreter found; set LUA=/path/to/lua.exe"

	if [[ "$STARTING_BRANCH" != "$DEV_BRANCH" ]]; then
		git checkout --quiet "$DEV_BRANCH"
	fi

	if TEST_OUT="$("$LUA" tests/run_headless.lua 2>&1)"; then
		ok "tests pass ($(printf '%s' "$TEST_OUT" | sed -n 's/.*Passed: \([0-9]*\).*/\1/p' | tail -1) assertions)"
	else
		echo "$TEST_OUT" | tail -20 >&2
		fail "headless test suite failed; not building a release"
	fi
fi

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
#
# The dotfiles are a deliberate split rather than a blanket sweep:
#
#   .gitignore              STRIPPED. Its entries (other_addons/, thoughts/debug/, .claude/)
#                           name paths that do not exist on a release branch, and it points at
#                           scripts/make-release.sh, which is stripped too. Nothing for it to do.
#   .git-blame-ignore-revs  STRIPPED. Names a dev-branch commit and only takes effect when a
#                           contributor wires it into blame.ignoreRevsFile by hand.
#   .gitattributes          KEPT. This one is load-bearing: the blobs are stored with CRLF, so
#                           `* text=auto eol=lf` is what normalises them to LF on checkout.
#                           Dropping it would make checkouts differ by each machine's
#                           core.autocrlf. WoW itself reads either ending fine, but there is no
#                           upside to inconsistency and it costs 10 lines to keep.
git rm -r --quiet --ignore-unmatch tests/ thoughts/ CLAUDE.md scripts/ .gitea/ \
	.gitignore .git-blame-ignore-revs

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
	exit 1
fi
ok "TRP3FW.toc stripped clean"

# Verify the strip list actually took. Catches both directions: a dev-only path that
# survived, and .gitattributes being swept up by a future broadened `git rm`.
#
# Tests the INDEX (git ls-files), not the filesystem. thoughts/debug/ and thoughts/errors/
# are gitignored scratch dirs, so they survive `git rm` and the branch switch as untracked
# leftovers -- present on disk, but never part of the release commit. A filesystem test
# fails on those for no reason; what ships is what git has staged.
STRIP_FAIL=0
for unwanted in tests thoughts CLAUDE.md scripts .gitea .gitignore .git-blame-ignore-revs \
	other_addons .claude; do
	if [[ -n "$(git ls-files -- "$unwanted")" ]]; then
		echo "  FAIL: '$unwanted' is still tracked and would ship on the release branch" >&2
		STRIP_FAIL=1
	fi
done
[[ -n "$(git ls-files -- .gitattributes)" ]] || {
	echo "  FAIL: .gitattributes must be KEPT (normalises the CRLF-stored blobs on checkout)" >&2
	STRIP_FAIL=1
}
[[ "$STRIP_FAIL" -eq 0 ]] || exit 1
ok "dev-only files stripped, .gitattributes retained"

# Every .lua the .toc loads must actually exist in the stripped tree, or the
# addon breaks at load time for users.
MISSING=0
while IFS= read -r entry; do
	path="${entry//\\//}"
	[[ -f "$path" ]] || { echo "  FAIL: .toc loads missing file: $path" >&2; MISSING=1; }
done < <(grep -E '^[^#[:space:]].*\.(lua|xml)[[:space:]]*$' TRP3FW.toc | tr -d '\r')
[[ "$MISSING" -eq 0 ]] || exit 1
ok "all .toc-referenced files present"

# Stage the strip.
#
# `git add -A` alone is NOT safe here: we just deleted .gitignore, so everything it was
# suppressing (other_addons/ -- 2636 vendored third-party files, ~247 MB, not ours to
# redistribute -- plus thoughts/debug/ and thoughts/errors/ scratch dumps) becomes stageable
# and would be committed into the release. The pathspec exclusions below re-state those rules
# so the build never depends on .gitignore still being around.
git add -A -- . \
	':(exclude)other_addons' \
	':(exclude)thoughts' \
	':(exclude).claude'

# Belt and braces: if anything from those trees reached the index anyway, drop it rather than
# shipping it. Cheap, and the failure mode it guards against is publishing other people's code.
git rm -r --quiet --cached --ignore-unmatch other_addons thoughts .claude
git commit --quiet -m "Release $VERSION: strip dev-only tree for distribution

Regenerated from $DEV_BRANCH by scripts/make-release.sh. Removes tests/,
thoughts/, CLAUDE.md, scripts/ and .gitea/, and drops the WoWUnit OptionalDep plus the
test-loading lines from TRP3FW.toc so the addon loads cleanly without them."

# Audit the COMMIT, which is the thing that actually gets pushed. The strip check above runs
# before `git add`, so it cannot see anything introduced at staging time -- which is exactly
# how other_addons/ (2636 third-party files) once reached a build, after .gitignore was
# stripped and `git add -A` happily staged everything it had been suppressing.
COMMIT_FAIL=0
for unwanted in tests thoughts CLAUDE.md scripts .gitea .gitignore .git-blame-ignore-revs \
	other_addons .claude; do
	if git ls-tree -r --name-only HEAD | grep -qE "^${unwanted}(/|$)"; then
		echo "  FAIL: '$unwanted' is IN the release commit" >&2
		COMMIT_FAIL=1
	fi
done
[[ "$COMMIT_FAIL" -eq 0 ]] || {
	echo "  The release branch is left in place for inspection; nothing was pushed." >&2
	exit 1
}

# A release is ~70 files. Anything wildly above that means a tree leaked in.
TRACKED="$(git ls-tree -r --name-only HEAD | wc -l)"
if [[ "$TRACKED" -gt 200 ]]; then
	echo "  FAIL: release commit has $TRACKED files (expected ~70); something leaked" >&2
	exit 1
fi
ok "release commit contains $TRACKED files, no dev-only trees"

RELEASE_COMMIT="$(git rev-parse HEAD)"

# --------------------------------------------------------------------------
# Tag.  On the RELEASE commit, not the dev tip -- v1.6.0 set that precedent and
# the tag should point at the tree users actually receive.  Created here rather
# than left to the operator, because doing it by hand is how it lands on the
# wrong commit.
# --------------------------------------------------------------------------
echo "==> Tagging"
git tag -a "$TAG" -m "TRP3FW $VERSION" "$RELEASE_COMMIT"
ok "$TAG -> $(git rev-parse --short "$RELEASE_COMMIT") (the release commit)"

# --------------------------------------------------------------------------
# main.  Tracks the latest release so the GitHub landing page is never stale.
#
# This was a manual `git merge` that lived nowhere except somebody's memory, and
# it was duly forgotten: main sat on 1.6.0 while 1.6.1 was built, tagged and
# ready.  It is a scripted step now.
#
# The merge is always --no-ff and always takes the release branch's tree
# wholesale: main is a mirror of the newest release, never a place work happens,
# so there is nothing on it worth preserving in a conflict.
# --------------------------------------------------------------------------
if [[ "$MERGE_MAIN" -eq 1 ]]; then
	echo "==> Merging into $MAIN_BRANCH"
	if git rev-parse --verify --quiet "$MAIN_BRANCH" >/dev/null; then
		git checkout --quiet "$MAIN_BRANCH"
		# -X theirs resolves in favour of the release branch. Because v<N> is
		# force-rebuilt each release, main's previous parent is an orphaned
		# commit and a content conflict is expected, not exceptional.
		if git merge --no-ff -X theirs --quiet \
			-m "Merge $TAG into $MAIN_BRANCH" "$RELEASE_BRANCH"; then
			:
		else
			fail "merge into $MAIN_BRANCH conflicted; resolve by hand (release branch and tag are built)"
		fi

		# The merge must leave main byte-identical to the release branch. -X theirs
		# resolves conflicting hunks, but a file deleted on one side and modified on
		# the other can still survive; compare trees rather than trusting the merge.
		if [[ -n "$(git diff --stat "$RELEASE_BRANCH" "$MAIN_BRANCH")" ]]; then
			echo "  FAIL: $MAIN_BRANCH does not match $RELEASE_BRANCH after merge:" >&2
			git diff --stat "$RELEASE_BRANCH" "$MAIN_BRANCH" >&2
			exit 1
		fi
		ok "$MAIN_BRANCH matches $RELEASE_BRANCH exactly"
	else
		git checkout --quiet -b "$MAIN_BRANCH" "$RELEASE_BRANCH"
		ok "created $MAIN_BRANCH at $RELEASE_BRANCH"
	fi
fi

echo
echo "==> Done."
echo "    $RELEASE_BRANCH  $(git rev-parse --short "$RELEASE_COMMIT")"
echo "    $TAG        -> $(git rev-parse --short "$RELEASE_COMMIT")"
[[ "$MERGE_MAIN" -eq 1 ]] && \
	echo "    $MAIN_BRANCH         $(git rev-parse --short "$MAIN_BRANCH")"
echo
echo "Review:"
echo "    git show --stat $RELEASE_BRANCH"
echo "    git diff $DEV_BRANCH $RELEASE_BRANCH -- TRP3FW.toc"
echo
echo "Push (dev -> gitea only; release, tag and main -> both):"
echo "    git push gitea $DEV_BRANCH"
echo "    git push gitea $RELEASE_BRANCH --force-with-lease"
echo "    git push gitea $TAG"
[[ "$MERGE_MAIN" -eq 1 ]] && echo "    git push gitea $MAIN_BRANCH"
echo "    git push origin $RELEASE_BRANCH --force-with-lease"
echo "    git push origin $TAG"
[[ "$MERGE_MAIN" -eq 1 ]] && echo "    git push origin $MAIN_BRANCH"
echo
echo "Nothing has been pushed. Re-running before pushing is safe: it rebuilds the"
echo "release branch and re-merges main. Delete the tag first ($TAG) if you do."
echo
echo "Returning to $STARTING_BRANCH"
