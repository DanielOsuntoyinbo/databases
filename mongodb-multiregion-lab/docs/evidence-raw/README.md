# evidence-raw/

Unedited captures from the nodes — real log tails, `script`-recorded
terminal sessions, raw command output pulled straight off a node before
it's torn down. This is deliberately separate from `docs/01-evidence-log.md`.

**The split:**
- `docs/01-evidence-log.md` — curated, slide-ready. Tables, findings,
  interpretation. What you'd actually put in front of an audience.
- `docs/evidence-raw/` — unedited source material backing it up. What
  you'd point to if someone in Q&A asks "is that number real?"

## Naming convention

`<scenario>-<what>-<region-or-node>-<YYYYMMDD>.<ext>`

Examples:
- `primary-failure-mongod-log-london-20260816.txt`
- `write-concern-majority-session-20260816.log` (from `script`)
- `rs-status-regional-outage-ireland-down-20260816.txt`

## How things land here

Pull directly from a node into this directory rather than copy-pasting
through a terminal — keeps formatting exact and avoids transcription
errors:

```bash
# a log tail
ssh -i ~/.ssh/id_ed25519 ubuntu@<node-ip> "sudo tail -100 /var/log/mongodb/mongod.log" \
  > docs/evidence-raw/<name>.txt

# a script-recorded session from a node
scp -i ~/.ssh/id_ed25519 ubuntu@<node-ip>:~/lab-logs/*.log docs/evidence-raw/
```

## Node disposability reminder

Nodes get destroyed between working sessions (`make destroy`) — anything
only living on a node (bash history, unsaved `script` logs, log files)
is gone once that happens. Pull anything worth keeping into this
directory *before* tearing down, not after.
