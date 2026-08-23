# evidence-raw/

This directory contains unedited captures from the lab nodes: real log tails, `script`-recorded terminal sessions, and raw command output collected before the corresponding infrastructure was torn down.

It is deliberately separate from `docs/01-evidence-log.md` so the interpreted findings and the underlying source material remain distinct.

**Documentation layers:**
- `docs/01-evidence-log.md` — curated results, tables, findings and interpretation.
- `docs/evidence-raw/` — unedited source material that can be used to verify the measurements and failure observations documented elsewhere in the repository.

## Naming convention

`<scenario>-<what>-<region-or-node>-<YYYYMMDD>.<ext>`

Examples:
- `primary-failure-mongod-log-london-20260816.txt`
- `write-concern-majority-session-20260816.log` (from `script`)
- `rs-status-regional-outage-ireland-down-20260816.txt`

## Capturing evidence

Raw output should be copied directly from a node into this directory rather than manually transcribed through a terminal. This preserves formatting and reduces the risk of transcription errors.

```bash
# Capture a log tail
ssh -i ~/.ssh/id_ed25519 ubuntu@<node-ip> "sudo tail -100 /var/log/mongodb/mongod.log" \
  > docs/evidence-raw/<name>.txt

# Copy a script-recorded session from a node
scp -i ~/.ssh/id_ed25519 ubuntu@<node-ip>:~/lab-logs/*.log docs/evidence-raw/
```

## Node lifecycle and evidence retention

Lab nodes are disposable and may be destroyed between working sessions with `make destroy`. Any evidence that exists only on a node — including shell history, unsaved `script` sessions and log files — is lost when that node is destroyed.

Evidence intended for later analysis or verification should therefore be copied into this directory before teardown.
