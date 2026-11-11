#!/usr/bin/env bash
# Compare public source repos with README WORKS block and portfolio manual list.
# Usage: works-check.sh README CONFIG REPOS
#   REPOS: every public repo of OWNER as "name<TAB>isFork<TAB>isArchived" lines (true/false),
#   from: gh repo list OWNER --visibility public --limit 1000 --json name,isFork,isArchived --jq '.[] | [.name, .isFork, .isArchived] | @tsv'
# Prints the issue body (Markdown) to stdout. Exit 0 = all fine, 10 = gaps, 2 = parse failure; any other code is an unexpected error.
set -euo pipefail
OWNER=bwaynesu

# Repo names linked from the WORKS block (HTML href and Markdown links alike).
readme_repos() {
  # A missing or doubled marker would make sed read to EOF; fail instead.
  local s e
  s=$({ grep -nF '<!-- WORKS:START -->' "$1" || true; } | cut -d: -f1 | tr '\n' ' ')
  e=$({ grep -nF '<!-- WORKS:END -->' "$1" || true; } | cut -d: -f1 | tr '\n' ' ')
  if ! [[ $s =~ ^[0-9]+\ $ && $e =~ ^[0-9]+\ $ ]] || [ "${s% }" -gt "${e% }" ]; then
    echo "::error::README needs exactly one WORKS markers pair (START before END)" >&2; exit 2
  fi
  sed -n '/<!-- WORKS:START -->/,/<!-- WORKS:END -->/p' "$1" |
    { grep -oiE "https?://(www\.)?github\.com/$OWNER/[A-Za-z0-9._-]+" || true; } |
    sed -E 's#.*/##; s/\.git$//; s/\.+$//' | sort -fu
}

# Names inside `<key>: { ... projects: [ ... ]` of the TS config.
# shortcut: line-based, ignores // comments only (not /* */ inside the list); upgrade if the list gets block comments.
config_list() {
  awk -v key="$2" -v owner="$OWNER" -v q="'" '
    { sub(/\/\/.*/, "") }
    $0 ~ "^[[:space:]]*" key ":[[:space:]]*[{]" { inkey = 1 }
    inkey && /projects:[[:space:]]*\[/ { inlist = 1; sub(/.*projects:[[:space:]]*\[/, "") }
    inkey && !inlist && /}/ { inkey = 0 } # object closed without a projects array
    inlist {
      end = index($0, "]"); if (end) $0 = substr($0, 1, end - 1)
      while (match($0, q owner "/[^" q "]+" q)) {
        s = substr($0, RSTART + length(owner) + 2, RLENGTH - length(owner) - 3); print s
        $0 = substr($0, RSTART + RLENGTH)
      }
      if (end) exit
    }' "$1" | sort -fu
}

# Lines of $1 whose lowercase form is absent from lowercase $2.
# FILENAME, not NR==FNR: an empty $2 (e.g. no excludes) would otherwise swallow $1.
minus() { awk 'FILENAME == ARGV[1] { seen[tolower($0)] = 1; next } !(tolower($0) in seen)' "$2" "$1"; }

main() {
  local readme=$1 config=$2 repos=$3 tmp
  tmp=$(mktemp -d)
  readme_repos "$readme" >"$tmp/a"
  config_list "$config" manual >"$tmp/b"
  config_list "$config" exclude >"$tmp/x"
  local fail=0
  if awk -F'\t' 'NF != 3 || $2 !~ /^(true|false)$/ || $3 !~ /^(true|false)$/' "$repos" | grep . >&2; then
    echo "::error::unexpected repo list format (above)" >&2; fail=1
  fi
  awk -F'\t' '$2 == "false" && $3 == "false" { print $1 }' "$repos" | sort -fu >"$tmp/act"
  for f in a b act; do [ -s "$tmp/$f" ] || { echo "::error::parsed 0 repos for list '$f'" >&2; fail=1; }; done
  # Names end up in the issue body; reject anything GitHub would not allow as a repo name.
  if grep -vhE '^[A-Za-z0-9._-]+$' "$tmp/b" "$tmp/x" >&2; then echo "::error::invalid repo name in config (above)" >&2; fail=1; fi
  [ $fail = 0 ] || exit 2

  minus "$tmp/act" "$tmp/x" >"$tmp/want"
  minus "$tmp/want" "$tmp/a" >"$tmp/missA"
  minus "$tmp/want" "$tmp/b" >"$tmp/missB"
  cat "$tmp/a" "$tmp/b" | sort -fu | minus /dev/stdin "$tmp/act" >"$tmp/deadnames"

  local bad=0
  section() { # title file [with-reason]
    [ -s "$2" ] || return 0; bad=1; echo "## $1"; echo
    while read -r n; do
      r=""
      [ -n "${3:-}" ] && r=$(awk -F'\t' -v n="$n" '
        tolower($1) == tolower(n) { r = ($2 == "true" ? "fork" : ""); if ($3 == "true") r = (r ? r "，" : "") "已封存"; print r; found = 1; exit }
        END { if (!found) print "找不到（已刪、私人或改名）" }' "$repos")
      echo "- \`$n\`${r:+：$r}"
    done <"$2"; echo
  }
  section "README WORKS 區漏列" "$tmp/missA"
  section "portfolio manual.projects 漏列" "$tmp/missB"
  section "已失效的連結" "$tmp/deadnames" reason
  rm -rf "$tmp"
  [ $bad = 0 ] && { echo "README 與 portfolio 都已列出全部公開 repo（扣掉 exclude）。"; exit 0; }
  echo "處理方式：把 repo 加進漏掉的清單，或加進 portfolio 的 \`automatic.exclude.projects\`；失效連結從清單移除或改成新名稱。"
  exit 10
}

main "$@"
