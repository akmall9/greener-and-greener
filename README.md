# git-greener

A small script that fills your GitHub contribution graph by making commits
with real (if tiny) content — one activity-log entry per commit.

Every commit changes `activity/YYYY-MM-DD.md`, so nothing is empty and the repo
still makes sense if someone opens it. Commit dates are set with
`GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE`, which is how past days get filled in.

> This is cosmetic. It does not create real work, and a green graph is not a
> measure of skill. Use it as a habit/streak tracker if you like, but don't
> pretend the squares are something they aren't.

## Quick start

```bash
# 1. make your own empty repo on GitHub, then:
cd git-greener
chmod +x green.sh

# 2. backfill the last 90 days + today, 1 commit per day, push it
./green.sh --days 90 --natural \
  --remote git@github.com:YOURNAME/activity.git \
  --email you@example.com \
  --push
```

If you skip `--email`, the script uses your existing git identity. That identity
**must** match a verified email on your GitHub account or the commits won't
count.

## Common usage

```bash
# just today, one commit
./green.sh --days 1

# a natural-looking history: gaps, weekends off, busy days
./green.sh --days 90 --natural

# last month, two commits a day, weekdays only
./green.sh --days 30 --per-day 2 --weekdays-only

# a specific historical window
./green.sh --start 2026-01-01 --end 2026-06-30 --per-day 3

# preview with no changes
./green.sh --days 365 --per-day 1 --dry-run

# custom commit messages ({date}, {time}, {n} are substituted)
./green.sh --days 7 --message "chore(log): {date} {time}"
```

## Options

| Flag | Meaning |
| --- | --- |
| `-d, --days N` | Days to fill, ending today (default `7`) |
| `-p, --per-day N` | Commits per day (default `1`, max `50`) |
| `--natural` | Vary 0–4 commits/day like a real person |
| `--max-per-day N` | Cap for `--natural` (default `4`) |
| `-s, --start DATE` | Start date `YYYY-MM-DD` (overrides `--days`) |
| `-e, --end DATE` | End date `YYYY-MM-DD` (default today) |
| `-r, --repo PATH` | Repo to commit into (default: this folder) |
| `-R, --remote URL` | Set/replace the `origin` remote |
| `--branch NAME` | Branch to use (default `main`) |
| `--name NAME` | Set local `user.name` |
| `--email EMAIL` | Set local `user.email` |
| `--message TEXT` | Commit message template |
| `--weekdays-only` | Skip Sat/Sun |
| `--push` | Push to `origin` when done |
| `--dry-run` | Print planned commits, change nothing |

## Natural-looking history

`--natural` decides the count per day instead of using a flat `--per-day`:
weekdays get 0–4 commits (mostly 1–2), weekends are lighter, and there are
occasional rest streaks of 3–6 days. Commit times also follow a schedule
(roughly 09:00–20:00 on weekdays, later on weekends) instead of being uniform.

```bash
./green.sh --days 90 --natural              # ~1.3 commits/day, 15–20% empty days
./green.sh --days 180 --natural --max-per-day 3
```

Because GitHub shades each day relative to your busiest day, this variance is
what makes the graph look organic: light-green single-commit days, darker
multi-commit days, and honest gaps.

## Making it stay green

Backfilling only fixes the past. To keep it green going forward, run it on a
schedule. Example crontab (`crontab -e`), once a day at 20:17:

```cron
17 20 * * * cd /home/mall/my-project/git-greener && ./green.sh --days 1 --natural --push >> .green.log 2>&1
```

Or use a systemd timer, a GitHub Action with a `schedule:` trigger, or any CI
job. Note that a scheduled job that commits every day will still produce a
visible pattern — that's fine, it's your call.

## Why a commit might not turn the square green

GitHub only counts a contribution when **all** of these are true:

1. The commit's author email is added and **verified** on your GitHub account.
2. The commit is on the **default branch** (or `gh-pages`) of a repo.
3. The repo is owned by you (or you're a collaborator on it).
4. For private repos, **Settings → Profile → Include private contributions**
   is enabled.
5. The commit date is in the past, not the future.

Other gotchas:

- The graph is based on the **commit author date**, which this script sets.
- Contributions are only counted once the commit is pushed (and the repo exists
  on GitHub).
- Very old dates are fine, but commits dated before your account existed may be
  ignored by some views.
- If you use two-factor / signing requirements, the script disables GPG signing
  per-commit (`-c commit.gpgsign=false`), so it won't fail on a missing key.

## macOS note

`date -d` is GNU-specific. On macOS, install coreutils (`brew install coreutils`)
and either use `gdate` or put it on your PATH as `date` (e.g. via a symlink).
