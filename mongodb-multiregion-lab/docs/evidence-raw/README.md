# evidence-raw/

This directory contains the source evidence collected during the lab experiments: MongoDB log excerpts, `script`-recorded terminal sessions, command output, topology snapshots and benchmark results.

It is deliberately separate from `docs/01-evidence-log.md` so the interpreted findings and the underlying source material remain distinct.

**Documentation layers:**
- `docs/01-evidence-log.md` — curated results, tables, findings and interpretation.
- `docs/evidence-raw/` — source material used to verify the measurements and failure observations documented elsewhere in the repository.

Most files are direct captures from the lab. A small number of experiment-oriented files include short contextual headers or arrange output from the same captured command sequence into a clearer evidence order; where that occurs, the file states it explicitly. The MongoDB output, timings and observed states are preserved rather than rewritten as new results.

## Naming convention

`<scenario>-<what>-<region-or-node>-<YYYYMMDD>.<ext>`

For experiments with several related captures, a scenario directory may be used instead. For example:

```text
REC-01-majority-loss-recovery/
├── 01-before-rs-conf.txt
├── 02-before-rs-status.txt
├── 03-majority-lost.txt
├── 04-reconfiguration.txt
├── 05-recovered-rs-status.txt
└── 06-client-validation.txt
```

Other examples:
- `primary-failure-mongod-log-london-20260816.txt`
- `write-concern-majority-session-20260816.log` (from `script`)
- `rs-status-regional-outage-ireland-down-20260816.txt`

## How the evidence was captured

The evidence in this directory was collected directly from the lab environment during each experiment. Depending on the scenario, this included MongoDB command output, `rs.status()` / `rs.conf()` captures, `mongod` log excerpts, benchmark output and terminal sessions recorded with `script`.

Where files were collected from remote nodes, the output was copied directly into the repository rather than manually retyped. Examples of the collection commands used during the lab include:

```bash
# Capture a mongod log tail from a lab node
ssh -i ~/.ssh/id_ed25519 ubuntu@<node-ip> "sudo tail -100 /var/log/mongodb/mongod.log" \
  > docs/evidence-raw/<name>.txt

# Copy a script-recorded terminal session from a lab node
scp -i ~/.ssh/id_ed25519 ubuntu@<node-ip>:~/lab-logs/*.log docs/evidence-raw/
```

The files are kept as close as practical to the observed command and log output so the results referenced in the evidence log and detailed findings can be traced back to their source material.

## Evidence retention

The lab infrastructure was disposable and was torn down between some working sessions. Relevant logs and command output were therefore copied into this directory before teardown so the evidence remained available for later analysis and verification.
