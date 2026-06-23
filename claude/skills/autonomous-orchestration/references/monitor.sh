#!/bin/bash
# Autonomous-orchestration: background poll-until-terminal monitor.
# Run with run_in_background:true. The harness re-invokes you when it exits, so you don't poll in-context.
# Watches one external status until it reaches a TERMINAL state on a FRESH run (not a stale pinned one),
# or a max-wall-clock cap. Edit the STATUS() function for your source (CI, deploy, queue, job, ...).
#
# Key idea: track the run/build id. A status pinned to an OLD id won't change until the right trigger fires,
# so wait for the id to differ from the known-stale one AND reach pass/fail.

set +e
MAX=${MAX:-4200}          # cap wall-clock (s). >300s pays a prompt-cache miss; that's fine for long waits.
INTERVAL=${INTERVAL:-180} # poll cadence (s). Stay <=270 to keep cache warm, or accept the miss.
STALE_ID=${STALE_ID:-""}  # an id known to be stale; we wait for something different. "" = accept any terminal.

# Print "<bucket> <id>" for the thing you're watching. EDIT THIS for your source.
# Example (GitHub PR check via gh):
#   gh pr checks "$PR" --json name,bucket,link \
#     | python3 -c "import json,sys;d=json.load(sys.stdin);c=next((x for x in d if x['name']=='$CHECK'),None);print((c['bucket'] if c else 'missing'),(c.get('link') if c else '-'))"
STATUS() {
  echo "missing -"   # <-- replace
}

start=$SECONDS
echo "Monitoring (max ${MAX}s, every ${INTERVAL}s; stale id='${STALE_ID}')."
while true; do
  read -r bucket id <<<"$(STATUS 2>/dev/null)"
  echo "$(date +%H:%M:%S) bucket=$bucket id=$id elapsed=$((SECONDS-start))s"
  fresh=1; [ -n "$STALE_ID" ] && [ "$id" = "$STALE_ID" ] && fresh=0
  if [ "$fresh" = 1 ] && { [ "$bucket" = "pass" ] || [ "$bucket" = "fail" ] || [ "$bucket" = "success" ] || [ "$bucket" = "failure" ]; }; then
    echo "TERMINAL bucket=$bucket id=$id"; break
  fi
  if [ $((SECONDS-start)) -gt "$MAX" ]; then echo "TIMEOUT bucket=$bucket id=$id"; break; fi
  sleep "$INTERVAL"
done
