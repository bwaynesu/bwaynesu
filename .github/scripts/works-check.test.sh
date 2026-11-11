#!/usr/bin/env bash
# Self-check for works-check.sh. Run: bash .github/scripts/works-check.test.sh
set -uo pipefail
S="$(dirname "$0")/works-check.sh"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0
check() { # name expected-exit expected-substring actual-exit output
  if [ "$2" != "$4" ] || ! grep -qF -- "$3" <<<"$5"; then echo "FAIL $1 (exit $4)"; echo "$5"; fails=$((fails+1)); else echo "ok   $1"; fi
}
cat >"$T/readme" <<'R'
<a href="https://github.com/bwaynesu/Outside">x</a>
<!-- WORKS:START -->
<td><a href="https://github.com/bwaynesu/RepoA">A</a> <img src="https://img.shields.io/github/stars/bwaynesu/NotALink"></td>
- **[repob](https://github.com/bwaynesu/RepoB)**: see https://github.com/bwaynesu/Gone.
<!-- WORKS:END -->
R
cat >"$T/config" <<'C'
      automatic: {
        exclude: {
          projects: [
            'bwaynesu/Skip',
            // 'bwaynesu/Commented',
          ], // example: ['arifszn/my-project1']
        },
      },
      manual: {
        projects: [
          'bwaynesu/RepoA',
          'bwaynesu/OldFork', 'bwaynesu/RepoB',
        ], // example: ['arifszn/my-project1']
      },
C
sed -i 's#<!-- WORKS:END -->#<a href="https://github.com/bwaynesu/Arch">arch</a>\n&#' "$T/readme"
# Same shape as `gh repo list --json name,isFork,isArchived --jq '.[] | [.name, .isFork, .isArchived] | @tsv'`.
tsv() { while [ $# -gt 0 ]; do printf '%s\t%s\t%s\n' "$1" "$2" "$3"; shift 3; done; }
tsv RepoA false false RepoB false false RepoC false false Skip false false Outside false false \
  OldFork true false Arch false true >"$T/active"
out=$(bash "$S" "$T/readme" "$T/config" "$T/active"); rc=$?
check "missing in both lists" 10 '`RepoC`' $rc "$out"
check "outside-block link not counted" 10 '- `Outside`' $rc "$out"
grep -q 'Skip' <<<"$out" && { echo "FAIL excluded repo reported"; fails=$((fails+1)); }
grep -q 'NotALink\|Commented\|arifszn' <<<"$out" && { echo "FAIL non-link or comment parsed"; fails=$((fails+1)); }
check "dead link: fork" 10 '`OldFork`：fork' $rc "$out"
check "dead link: archived" 10 '`Arch`：已封存' $rc "$out"
check "dead link: not in public list, trailing dot stripped" 10 '`Gone`：找不到（已刪、私人或改名）' $rc "$out"
grep -q '`RepoC` (' <<<"$out" && { echo "FAIL reason attached to a missing (not dead) repo"; fails=$((fails+1)); }
tsv repoa false false REPOB false false RepoC false false Skip false false Outside false false Gone false false \
  OtherFork true false >"$T/active2"
sed -i 's#RepoB)#RepoB) https://github.com/bwaynesu/RepoC https://github.com/bwaynesu/Outside#; /bwaynesu\/Arch/d' "$T/readme"
sed -i "s#'bwaynesu/OldFork', 'bwaynesu/RepoB',#'bwaynesu/RepoB', 'bwaynesu/RepoC', 'bwaynesu/Outside', 'bwaynesu/Gone',#" "$T/config"
out=$(bash "$S" "$T/readme" "$T/config" "$T/active2"); rc=$?
check "all listed, case-insensitive" 0 '都已列出' $rc "$out"
printf '<!-- WORKS:START -->\n<!-- WORKS:END -->\n' >"$T/empty"
out=$(bash "$S" "$T/empty" "$T/config" "$T/active2" 2>&1); rc=$?
check "empty README block fails loudly" 2 "parsed 0 repos for list 'a'" $rc "$out"
sed 's/manual: {/manuals: {/' "$T/config" >"$T/badcfg"
out=$(bash "$S" "$T/readme" "$T/badcfg" "$T/active2" 2>&1); rc=$?
check "missing manual list fails loudly" 2 "list 'b'" $rc "$out"
: >"$T/none"; out=$(bash "$S" "$T/readme" "$T/config" "$T/none" 2>&1); rc=$?
check "empty repo list fails loudly" 2 "list 'act'" $rc "$out"
printf 'RepoA\nRepoB\n' >"$T/namesonly"; out=$(bash "$S" "$T/readme" "$T/config" "$T/namesonly" 2>&1); rc=$?
check "repo list without fork/archived columns fails loudly" 2 "unexpected repo list format" $rc "$out"
tsv RepoA true false >"$T/allforks"; out=$(bash "$S" "$T/readme" "$T/config" "$T/allforks" 2>&1); rc=$?
check "only forks counts as empty active list" 2 "list 'act'" $rc "$out"
# exclude object without a projects array must not swallow manual's list.
printf "exclude: {\n  forks: true,\n},\nmanual: {\n  projects: ['bwaynesu/A'],\n},\n" >"$T/noexcl"
printf '<!-- WORKS:START -->\nhttps://github.com/bwaynesu/B\n<!-- WORKS:END -->\n' >"$T/readmeB"
tsv A false false B false false >"$T/activeAB"
out=$(bash "$S" "$T/readmeB" "$T/noexcl" "$T/activeAB" 2>&1); rc=$?
check "exclude without projects keeps manual list" 10 $'README WORKS 區漏列\n\n- `A`' $rc "$out"
head -n 3 "$T/readme" >"$T/noend"
out=$(bash "$S" "$T/noend" "$T/config" "$T/active2" 2>&1); rc=$?
check "missing END marker fails loudly" 2 "WORKS markers" $rc "$out"
{ cat "$T/readme"; echo '<!-- WORKS:START -->'; } >"$T/twostart"
out=$(bash "$S" "$T/twostart" "$T/config" "$T/active2" 2>&1); rc=$?
check "duplicate START marker fails loudly" 2 "WORKS markers" $rc "$out"
{ echo 'See WORKS:START below.'; echo '<!-- WORKS:END -->'; echo 'https://github.com/bwaynesu/RepoA'; echo '<!-- WORKS:START -->'; } >"$T/reversed"
out=$(bash "$S" "$T/reversed" "$T/config" "$T/active2" 2>&1); rc=$?
check "reversed markers caught despite marker text elsewhere" 2 "WORKS markers" $rc "$out"
sed "s#'bwaynesu/RepoA',#'bwaynesu/Repo A',#" "$T/config" >"$T/badname"
out=$(bash "$S" "$T/readme" "$T/badname" "$T/active2" 2>&1); rc=$?
check "invalid repo name in config fails loudly" 2 "invalid repo name" $rc "$out"
[ $fails = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
