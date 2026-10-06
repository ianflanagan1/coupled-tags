#!/bin/sh
# coupled-tags-lint: check COUPLED:<key>. tags in a repository.
#
# Reports:
#   - malformed tags (key not [a-z0-9-] or not terminated by ".")
#   - orphan keys (only one site, so the other end was removed or never tagged)
#
# Usage: coupled-tags-lint.sh [-l] [-x path]... [dir]
#   -l       list every key and its sites
#   -x path  exclude a path prefix (relative to dir); repeatable
#   dir      directory to scan (default: .)
#
# The skill directory (the parent of this script's scripts/ directory) is excluded
# automatically, so a vendored copy of the skill, whose docs contain example tags,
# does not trip the checks.
#
# Exit status: 0 clean, 1 problems found, 2 usage error.

set -eu

usage() {
    sed -n '8,11p' "$0" | sed 's/^# \{0,1\}//'
}

list=0
excludes=''
while getopts 'lx:h' opt; do
    case $opt in
        l) list=1 ;;
        x) excludes="$excludes
${OPTARG%/}" ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
[ $# -le 1 ] || { usage >&2; exit 2; }

self_dir=$(cd "$(dirname "$0")/.." && pwd -P)
cd "${1:-.}"
root=$(pwd -P)
case $self_dir in
    "$root"/*) excludes="$excludes
${self_dir#"$root"/}" ;;
esac

# Tracked and untracked-but-not-ignored files in a git work tree; plain grep otherwise.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    search() { git grep --untracked -I -n -F 'COUPLED:' -- . || true; }
else
    search() {
        grep -r -I -n -F 'COUPLED:' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor . \
            | sed 's|^\./||' || true
    }
fi

search | EXCLUDES="$excludes" LIST="$list" awk '
BEGIN {
    nex = split(ENVIRON["EXCLUDES"], ex, "\n")
    list = ENVIRON["LIST"] == "1"
    err = "cat 1>&2"
}
{
    i = index($0, ":");  path = substr($0, 1, i - 1);  rest = substr($0, i + 1)
    j = index(rest, ":"); line = substr(rest, 1, j - 1); text = substr(rest, j + 1)

    for (k = 1; k <= nex; k++)
        if (ex[k] != "" && (path == ex[k] || index(path, ex[k] "/") == 1)) next

    while ((p = index(text, "COUPLED:")) > 0) {
        text = substr(text, p + 8)
        # Prose mentions such as `COUPLED:<key>.` or `COUPLED:` are not tags.
        if (text !~ /^[A-Za-z0-9_-]/) continue
        # A grep pattern such as `COUPLED:<key>\.` mentions a tag; it is not one.
        if (text ~ /^[a-z0-9-]+\\\./) continue
        if (match(text, /^[a-z0-9-]+\./)) {
            key = substr(text, 1, RLENGTH - 1)
            if (!(key in count)) order[++nkeys] = key
            count[key]++
            sites[key] = sites[key] "\n    " path ":" line
        } else {
            printf "%s:%s Malformed tag. Must be `COUPLED:<key>.` with key [a-z0-9-]\n", path, line | err
            problems++
        }
    }
}
END {
    for (k = 1; k <= nkeys; k++) {
        key = order[k]
        if (list) printf "%s (%d)%s\n", key, count[key], sites[key]
        if (count[key] < 2) {
            printf "%s Orphan key with only one site\n", substr(sites[key], 6) | err
            problems++
        }
    }
    close(err)
    exit problems ? 1 : 0
}'
