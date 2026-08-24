# evidence-raw/

This directory contains unedited captures from the lab nodes: real log tails, `script`-recorded terminal sessions, and raw command output collected during the experiments.

It is deliberately separate from `docs/01-evidence-log.md` so the interpreted findings and the underlying source material remain distinct.

**Documentation layers:**
- `docs/01-evidence-log.md` — curated results, tables, findings and interpretation.
- `docs/evidence-raw/` — unedited source material used to verify the measurements and failure observations documented elsewhere in the repository.

## Naming convention

`<scenario>-<what>-<region-or-node>-<YYYYMMDD>.<ext>`

Examples:
- `primary-failure-mongod-log-london-20260816.txt`
- `write-concern-majority-session-20260816.log` (from `script`)
- `rs-status-regional-outage-ireland-down-20260816.txt`

## How the evidence was captured

The raw evidence in this directory was collected directly from the lab environment during each experiment. Depending on the scenario, this included MongoDB command output, `rs.status()` / `rs.conf()` captures, `mongod` log excerpts, benchmark output and terminal sessions recorded with `script`.

Where files were collected from remote nodes, the output was copied directly into the repository rather than manually retyped. Examples of the collection commands used during the lab include:

```bash
# Capture a mongod log tail from a lab node
ssh -i ~/.ssh/id_ed25519 ubuntu@<node-ip> "sudo tail -100 /var/log/mongodb/mongod.log" \
  > docs/evidence-raw/<name>.txt

# Copy a script-recorded terminal session from a lab node
scp -i ~/.ssh/id_ed25519 ubuntu@<node-ip>:~/lab-logs/*.log docs/evidence-raw/
```

The files are intentionally left as close as practical to the captured output so the results referenced in the evidence log and detailed findings can be traced back to their source material.

## Evidence retention

The lab infrastructure was disposable and was torn down between some working sessions. Relevant logs and command output were therefore copied into this directory before teardown so the evidence remained available for later analysis and verification.
