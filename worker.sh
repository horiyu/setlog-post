#!/bin/bash
# Drain queue/ one job at a time (`setlog-post post` starts one of these; extra ones
# exit at the lock). Each job runs post.sh with its output in <job>/post.log, then
# moves to done/ with result.json. done/ keeps the newest 20 (videos of the newest 5).
# Retry one by hand:  ./post.sh done/<job>
cd "$(dirname "$0")"
mkdir -p state queue done
exec 9> state/worker.lock
flock -n 9 || exit 0
log() { echo "$(date '+%F %T') $*"; }
{
while :; do
  job=$(ls queue 2>/dev/null | grep -v '^\.' | sort | head -1)
  [ -n "$job" ] || break
  log "=== $job"
  echo "$job" > state/current
  if ./post.sh "queue/$job" > "queue/$job/post.log" 2>&1; then ok=true; else ok=false; fi
  python3 - "queue/$job" "$job" "$ok" <<'EOF'
import datetime, json, os, sys
d, job, ok = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
with open(os.path.join(d, "post.log"), encoding="utf-8", errors="replace") as fh:
    lines = [l.rstrip() for l in fh if l.strip()]
meta = json.load(open(os.path.join(d, "job.json"), encoding="utf-8"))
res = {"ok": ok, "job": job, "rooms": meta.get("rooms"), "dry": meta.get("dry", False),
       "finished": datetime.datetime.now().astimezone().isoformat(timespec="seconds")}
if not ok:
    # post.sh's own progress lines start with a date; the reason is the last line that does not.
    reasons = [l for l in lines if not l[:4].isdigit()]
    res["error"] = (reasons or lines or ["post.sh failed"])[-1]
with open(os.path.join(d, "result.json"), "w", encoding="utf-8") as fh:
    json.dump(res, fh, ensure_ascii=False)
EOF
  rm -f state/current
  log "$([ $ok = true ] && echo posted || echo FAILED) $job"
  mv "queue/$job" "done/$job"
  ls -d done/*/ 2>/dev/null | sort | head -n -20 | xargs -r rm -rf
  ls -d done/*/ 2>/dev/null | sort | head -n -5 | while read -r d; do rm -f "$d"video.*; done
done
log "queue empty"
} >> state/worker.log 2>&1
