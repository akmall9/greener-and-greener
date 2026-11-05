#!/usr/bin/env bash
#
# green.sh — fill your GitHub contribution graph with commits.
#
# Creates one small real file change per commit (an activity log), so every
# commit has actual content. Works for "today onward" habit tracking and for
# backfilling past days (backdated commits).
#
# Requires: git >= 2.28 and GNU date (standard on Linux).
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
REPO="$SCRIPT_DIR"
DAYS=7
PER_DAY=1
PER_DAY_SET=0
NATURAL=0
MAX_PER_DAY=4
START=""
END=""
REMOTE=""
BRANCH="main"
BRANCH_SET=0
PUSH=0
WEEKDAYS_ONLY=0
DRY_RUN=0
NAME=""
EMAIL=""
MESSAGE=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

usage() {
  cat <<'EOF'
green.sh — make your GitHub contribution graph greener.

Usage:
  ./green.sh [options]

Options:
  -d, --days N          Number of days to fill, ending today. Default: 7
  -p, --per-day N       Commits per day. Default: 1
      --natural         Vary commits per day (0-4) like a real person:
                        fewer on weekends, occasional days off/rest streaks.
                        Mutually exclusive with --per-day.
      --max-per-day N   Cap for --natural. Default: 4
  -s, --start DATE      Start date (YYYY-MM-DD). Overrides --days.
  -e, --end DATE        End date (YYYY-MM-DD). Default: today
  -r, --repo PATH       Repo to commit into. Default: this script's folder
  -R, --remote URL      Set/replace the "origin" remote
      --branch NAME     Branch to use. Default: main
      --name NAME       Set local git user.name
      --email EMAIL     Set local git user.email (must match a GitHub email!)
      --message TEXT    Commit message. Placeholders: {date} {time} {n}
      --weekdays-only   Skip Saturday and Sunday
      --push            Push to origin when done
      --dry-run         Show what would happen, change nothing
  -h, --help            Show this help

Examples:
  ./green.sh --days 30 --per-day 2 --push
  ./green.sh --days 90 --natural
  ./green.sh --start 2026-01-01 --end 2026-06-30 --per-day 3
  ./green.sh --days 365 --weekdays-only --remote git@github.com:me/activity.git --push
  ./green.sh --days 10 --message "chore(log): {date} {time}"

GitHub only counts a commit when:
  * the author email is a verified email on your GitHub account,
  * the commit is on the default branch (or gh-pages) of a repo you own,
  * for private repos, "Include private contributions" is enabled in settings,
  * the commit date is not in the future.
EOF
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while (($#)); do
  case "$1" in
    -d|--days)        DAYS="${2:?--days needs a value}"; shift 2 ;;
    -p|--per-day)     PER_DAY="${2:?--per-day needs a value}"; PER_DAY_SET=1; shift 2 ;;
    --natural)        NATURAL=1; shift ;;
    --max-per-day)    MAX_PER_DAY="${2:?--max-per-day needs a value}"; shift 2 ;;
    -s|--start)       START="${2:?--start needs a value}"; shift 2 ;;
    -e|--end)         END="${2:?--end needs a value}"; shift 2 ;;
    -r|--repo)        REPO="${2:?--repo needs a value}"; shift 2 ;;
    -R|--remote)      REMOTE="${2:?--remote needs a value}"; shift 2 ;;
    --branch)         BRANCH="${2:?--branch needs a value}"; BRANCH_SET=1; shift 2 ;;
    --name)           NAME="${2:?--name needs a value}"; shift 2 ;;
    --email)          EMAIL="${2:?--email needs a value}"; shift 2 ;;
    --message)        MESSAGE="${2:?--message needs a value}"; shift 2 ;;
    --weekdays-only)  WEEKDAYS_ONLY=1; shift ;;
    --push)           PUSH=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                die "unknown option: $1 (try --help)" ;;
  esac
done

[[ "$DAYS"    =~ ^[0-9]+$ ]] || die "--days must be a number"
[[ "$PER_DAY" =~ ^[0-9]+$ ]] || die "--per-day must be a number"
(( DAYS >= 1 ))    || die "--days must be >= 1"
(( PER_DAY >= 1 )) || die "--per-day must be >= 1"
(( PER_DAY <= 50 )) || die "--per-day above 50 is silly, keep it <= 50"
[[ "$MAX_PER_DAY" =~ ^[0-9]+$ ]] || die "--max-per-day must be a number"
(( MAX_PER_DAY >= 1 )) || die "--max-per-day must be >= 1"
(( MAX_PER_DAY <= 20 )) || die "--max-per-day above 20 is silly, keep it <= 20"
(( ! (NATURAL && PER_DAY_SET) )) || die "use either --natural or --per-day, not both"

# ---------------------------------------------------------------------------
# Work out the date range
# ---------------------------------------------------------------------------
TODAY_MIDNIGHT="$(date -d "$(date +%F) 00:00:00" +%s)"

if [[ -n "$START" ]]; then
  START_EPOCH="$(date -d "$START 00:00:00" +%s 2>/dev/null)" \
    || die "could not parse --start '$START' (use YYYY-MM-DD)"
else
  START_EPOCH="$(date -d "$(date +%F) -$((DAYS - 1)) days" +%s)"
fi

if [[ -n "$END" ]]; then
  END_EPOCH="$(date -d "$END 00:00:00" +%s 2>/dev/null)" \
    || die "could not parse --end '$END' (use YYYY-MM-DD)"
else
  END_EPOCH="$TODAY_MIDNIGHT"
fi

(( START_EPOCH <= END_EPOCH )) \
  || die "start date is after end date"

(( END_EPOCH <= TODAY_MIDNIGHT )) \
  || die "end date is in the future; GitHub won't count future commits"

# ---------------------------------------------------------------------------
# Prepare the repo
# ---------------------------------------------------------------------------
if (( ! DRY_RUN )); then
  mkdir -p "$REPO"
  cd "$REPO"

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    git init -q -b "$BRANCH"
    info "initialised new git repo at $REPO"
  fi

  if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    current="$(git symbolic-ref --short -q HEAD || true)"
    if [[ "$current" != "$BRANCH" ]]; then
      git checkout -q -B "$BRANCH"
    fi
  elif (( BRANCH_SET )); then
    current="$(git symbolic-ref --short -q HEAD || true)"
    [[ "$current" == "$BRANCH" ]] || die "repo is on branch '$current', not '$BRANCH'"
  fi

  [[ -n "$NAME"  ]] && git config user.name  "$NAME"
  [[ -n "$EMAIL" ]] && git config user.email "$EMAIL"

  [[ -n "$(git config user.name  || true)" ]] \
    || die "git user.name is not set (use --name, or: git config --global user.name 'You')"
  [[ -n "$(git config user.email || true)" ]] \
    || die "git user.email is not set (use --email, or: git config --global user.email 'you@example.com')"

  if [[ -n "$REMOTE" ]]; then
    if git remote get-url origin >/dev/null 2>&1; then
      git remote set-url origin "$REMOTE"
    else
      git remote add origin "$REMOTE"
    fi
    info "origin -> $REMOTE"
  fi
else
  info "[dry-run] repo would be: $REPO"
fi

GIT_NAME="$(git config user.name  || true)"
GIT_EMAIL="$(git config user.email || true)"
[[ -n "$GIT_NAME"  ]] || GIT_NAME="Your Name"
[[ -n "$GIT_EMAIL" ]] || GIT_EMAIL="you@example.com"

# ---------------------------------------------------------------------------
# Commit loop
# ---------------------------------------------------------------------------
total=0
day="$START_EPOCH"
rest_left=0

next_day() { date -d "$(date -d "@$1" +%F) +1 day" +%s; }

while (( day <= END_EPOCH )); do
  day_str="$(date -d "@$day" +%F)"
  dow="$(date -d "@$day" +%u)"          # 1 = Monday ... 7 = Sunday

  if (( WEEKDAYS_ONLY && dow > 5 )); then
    day="$(next_day "$day")"
    continue
  fi

  # ---- How many commits today? --------------------------------------------
  if (( NATURAL )); then
    # Every so often take a short break (holiday, busy week, etc.).
    if (( rest_left > 0 )); then
      rest_left=$((rest_left - 1))
      day="$(next_day "$day")"
      continue
    fi
    if (( day != TODAY_MIDNIGHT )) && (( RANDOM % 100 < 1 )); then
      rest_left=$(( 2 + RANDOM % 4 ))
      day="$(next_day "$day")"
      continue
    fi

    r=$(( RANDOM % 100 ))
    if (( dow <= 5 )); then               # Mon-Fri: fairly busy
      if   (( r < 7 ));  then count=0     #   day off
      elif (( r < 62 )); then count=1
      elif (( r < 87 )); then count=2
      elif (( r < 97 )); then count=3
      else                    count=4; fi
    else                                  # Sat-Sun: lighter
      if   (( r < 30 )); then count=0
      elif (( r < 75 )); then count=1
      elif (( r < 93 )); then count=2
      else                    count=3; fi
    fi
    if (( count > MAX_PER_DAY )); then count=$MAX_PER_DAY; fi
  else
    count=$PER_DAY
  fi

  if (( count == 0 )); then
    day="$(next_day "$day")"
    continue
  fi

  # ---- When? ---------------------------------------------------------------
  # Weekdays look like office hours, weekends drift later. Keeping everything
  # after 07:00 local also keeps the UTC date equal to the local date.
  if (( NATURAL )); then
    if (( dow <= 5 )); then start_h=9;  end_h=20
    else                    start_h=10; end_h=23; fi
  else
    start_h=8; end_h=22
  fi

  now="$(date +%s)"
  if (( day == TODAY_MIDNIGHT && now < day + start_h * 3600 )); then
    # Today's active window hasn't started yet; leave it for later.
    day="$(next_day "$day")"
    continue
  fi

  # (RANDOM is only 15 bits, so combine two for a full-day spread.)
  times=()
  for (( n = 1; n <= count; n++ )); do
    rnd=$(( (RANDOM << 15 | RANDOM) ))
    hour=$(( start_h + rnd % (end_h - start_h + 1) ))
    minute=$(( RANDOM % 60 ))
    second=$(( RANDOM % 60 ))
    ts_epoch=$(( day + hour * 3600 + minute * 60 + second ))
    if (( day == TODAY_MIDNIGHT && ts_epoch > now )); then
      ts_epoch=$(( now - 60 - RANDOM % 3600 ))
      if (( ts_epoch <= day )); then ts_epoch=$(( day + 1 )); fi
    fi
    times+=( "$ts_epoch" )
  done
  mapfile -t times < <(printf '%s\n' "${times[@]}" | sort -n)
  count=${#times[@]}

  for (( n = 1; n <= count; n++ )); do
    ts_epoch="${times[$((n - 1))]}"

    ts="$(date -d "@$ts_epoch" +'%Y-%m-%d %H:%M:%S')"
    hh="$(date -d "@$ts_epoch" +%H)"
    mm="$(date -d "@$ts_epoch" +%M)"

    if [[ -n "$MESSAGE" ]]; then
      msg="${MESSAGE//\{date\}/$day_str}"
      msg="${msg//\{time\}/$hh:$mm}"
      msg="${msg//\{n\}/$n}"
    else
      msg="chore(log): $day_str $hh:$mm"
    fi

    if (( DRY_RUN )); then
      info "[dry-run] $ts  $msg"
    else
      mkdir -p activity
      file="activity/$day_str.md"
      if [[ ! -f "$file" ]]; then
        printf '# %s\n\n' "$day_str" > "$file"
      fi
      printf -- '- %s — log entry %d\n' "$hh:$mm" "$n" >> "$file"

      git add -- "$file"
      GIT_AUTHOR_DATE="$ts" \
      GIT_COMMITTER_DATE="$ts" \
        git -c commit.gpgsign=false commit -q -m "$msg"
      info "  $ts  $msg"
    fi

    total=$((total + 1))
  done

  day="$(next_day "$day")"
done

# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------
if (( total == 0 )); then
  info ""
  info "no commits to make (empty range, or every day was a weekend)."
  exit 0
fi

if (( PUSH )); then
  if (( DRY_RUN )); then
    info "[dry-run] would push to origin"
  else
    git remote get-url origin >/dev/null 2>&1 \
      || die "no 'origin' remote (use --remote URL)"
    branch="$(git symbolic-ref --short -q HEAD)"
    info "pushing $branch to origin ..."
    git push -q -u origin "$branch"
    info "pushed."
  fi
fi

info ""
if (( DRY_RUN )); then
  info "dry run complete: $total commit(s) planned."
else
  info "done: $total commit(s) across $REPO"
  (( PUSH )) || info "next: git -C \"$REPO\" push -u origin $(git symbolic-ref --short -q HEAD)"
fi
