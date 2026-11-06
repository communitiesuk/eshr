#!/usr/bin/env bash
# hosts/github.sh — the GitHub module for the git-workflow script.
#
# Usage:
#   bash hosts/github.sh propose <branch> <trunk>   open a pull request from the
#                                                pushed branch onto the trunk,
#                                                its title the first commit's
#                                                subject and its description
#                                                every commit's message and
#                                                body, oldest first; when one
#                                                is already open, rewrite its
#                                                title and description from
#                                                those instead; prints its URL
#   bash hosts/github.sh merge <branch> <trunk>     merge that pull request with a
#                                                merge commit, never a squash
#                                                or a rebase. It merges only:
#                                                branch teardown (local, remote
#                                                and worktree) is the caller's,
#                                                so gh never trips over the
#                                                artefact's worktree.
#   bash hosts/github.sh link <pr-url> <branch> <path>
#                                                print the URL that shows
#                                                <path> as it stands at the
#                                                tip of <branch>, in the
#                                                repository the pull request
#                                                <pr-url> belongs to; prints
#                                                nothing and exits 1 when
#                                                <pr-url> is not a pull
#                                                request URL
#   bash hosts/github.sh settings                   print squash=<true|false>
#                                                rebase=<true|false> as the
#                                                repository allows them
#
# Depends on gh. Exit 0 done; 1 the host refused or the command failed;
# 127 gh is not on PATH.
set -u
command -v gh >/dev/null 2>&1 || exit 127
case "${1:-}" in
  propose)
    [ $# -ge 3 ] || { echo "usage: propose <branch> <trunk>" >&2; exit 2; }
    title="$(git log --reverse --format=%s "$3..$2" | sed -n 1p)"
    body="$(git log --reverse --format=%B "$3..$2")"
    url="$(gh pr view "$2" --json state,url --jq 'select(.state == "OPEN") | .url' 2>/dev/null)"
    if [ -n "$url" ]; then
      gh pr edit "$2" --title "$title" --body "$body" >/dev/null || exit 1
      printf '%s\n' "$url"
    else
      gh pr create --head "$2" --base "$3" --title "$title" --body "$body" || exit 1
    fi ;;
  merge)
    [ $# -ge 3 ] || { echo "usage: merge <branch> <trunk>" >&2; exit 2; }
    gh pr merge "$2" --merge || exit 1 ;;
  link)
    [ $# -ge 4 ] || { echo "usage: link <pr-url> <branch> <path>" >&2; exit 2; }
    case "$2" in https://*/pull/[0-9]*) ;; *) exit 1 ;; esac
    printf '%s/blob/%s/%s\n' "${2%/pull/*}" "$3" "$4" ;;
  settings)
    out="$(gh repo view --json squashMergeAllowed,rebaseMergeAllowed)" || exit 1
    sq=false; rb=false
    printf '%s' "$out" | grep -qE '"squashMergeAllowed":[[:space:]]*true' && sq=true
    printf '%s' "$out" | grep -qE '"rebaseMergeAllowed":[[:space:]]*true' && rb=true
    printf 'squash=%s rebase=%s\n' "$sq" "$rb" ;;
  *) echo "usage: hosts/github.sh propose|merge|link|settings" >&2; exit 2 ;;
esac
