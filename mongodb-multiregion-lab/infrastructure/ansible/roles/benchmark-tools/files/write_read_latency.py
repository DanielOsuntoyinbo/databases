#!/usr/bin/env python3
"""
Write/read latency benchmark for the PSMDB multi-region lab.

Run this ON a replica set node (the primary, for write tests) rather
than from your workstation — that isolates the measurement to DB-side
replication-acknowledgment cost, not client-to-DB WAN latency from
danny-pc to AWS.

Examples:
  # single run
  python3 write_read_latency.py --op write --write-concern majority --concurrency 50 --duration 30
  python3 write_read_latency.py --op write --write-concern 1         --concurrency 50 --duration 30
  python3 write_read_latency.py --op read  --concurrency 50 --duration 30

  # ramp: same test repeated at increasing concurrency, one summary table
  python3 write_read_latency.py --op write --write-concern majority --ramp 10,25,50,100 --duration 20
"""
import argparse
import getpass
import json
import statistics
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

from pymongo import MongoClient, WriteConcern
from pymongo.read_preferences import ReadPreference


def percentile(sorted_data, pct):
    if not sorted_data:
        return None
    k = (len(sorted_data) - 1) * (pct / 100)
    f = int(k)
    c = min(f + 1, len(sorted_data) - 1)
    if f == c:
        return sorted_data[f]
    return sorted_data[f] + (sorted_data[c] - sorted_data[f]) * (k - f)


def make_client(uri, user, password):
    return MongoClient(uri, username=user, password=password, authSource="admin")


def worker_write(uri, user, password, write_concern, db_name, coll_name, stop_at, latencies, errors, lock, doc_size):
    client = make_client(uri, user, password)
    wc = WriteConcern(w=write_concern)
    coll = client[db_name].get_collection(coll_name, write_concern=wc)
    payload = "x" * doc_size
    local_latencies = []
    local_errors = 0
    while time.monotonic() < stop_at:
        start = time.perf_counter()
        try:
            coll.insert_one({"payload": payload, "ts": time.time()})
            local_latencies.append((time.perf_counter() - start) * 1000)
        except Exception:
            local_errors += 1
    with lock:
        latencies.extend(local_latencies)
        errors[0] += local_errors
    client.close()


def worker_read(uri, user, password, db_name, coll_name, stop_at, latencies, errors, lock):
    client = make_client(uri, user, password)
    coll = client.get_database(db_name, read_preference=ReadPreference.PRIMARY)[coll_name]
    local_latencies = []
    local_errors = 0
    while time.monotonic() < stop_at:
        start = time.perf_counter()
        try:
            list(coll.find().limit(1))
            local_latencies.append((time.perf_counter() - start) * 1000)
        except Exception:
            local_errors += 1
    with lock:
        latencies.extend(local_latencies)
        errors[0] += local_errors
    client.close()


def run_once(args, concurrency, password):
    latencies = []
    errors = [0]
    lock = threading.Lock()
    stop_at = time.monotonic() + args.duration

    wc = int(args.write_concern) if args.write_concern.isdigit() else args.write_concern

    with ThreadPoolExecutor(max_workers=concurrency) as ex:
        futures = []
        for _ in range(concurrency):
            if args.op == "write":
                futures.append(ex.submit(
                    worker_write, args.uri, args.user, password, wc,
                    args.db, args.collection, stop_at, latencies, errors, lock, args.doc_size,
                ))
            else:
                futures.append(ex.submit(
                    worker_read, args.uri, args.user, password,
                    args.db, args.collection, stop_at, latencies, errors, lock,
                ))
        for f in as_completed(futures):
            f.result()

    sorted_l = sorted(latencies)
    result = {
        "op": args.op,
        "write_concern": wc if args.op == "write" else None,
        "concurrency": concurrency,
        "duration_sec": args.duration,
        "count": len(latencies),
        "errors": errors[0],
        "throughput_ops_sec": round(len(latencies) / args.duration, 1) if latencies else 0,
    }
    if sorted_l:
        result["latency_ms"] = {
            "min": round(sorted_l[0], 2),
            "p50": round(percentile(sorted_l, 50), 2),
            "p95": round(percentile(sorted_l, 95), 2),
            "p99": round(percentile(sorted_l, 99), 2),
            "max": round(sorted_l[-1], 2),
            "mean": round(statistics.mean(sorted_l), 2),
        }
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--uri", default="mongodb://localhost:27017/?replicaSet=psmdb-multiregion-lab")
    p.add_argument("--user", default="psmdb_admin")
    p.add_argument("--op", choices=["write", "read"], required=True)
    p.add_argument("--write-concern", default="majority", help="'1' or 'majority' (write tests only)")
    p.add_argument("--concurrency", type=int, default=20, help="ignored if --ramp is set")
    p.add_argument("--ramp", default=None, help="comma-separated concurrency steps, e.g. 10,25,50,100")
    p.add_argument("--duration", type=int, default=20, help="seconds per step")
    p.add_argument("--doc-size", type=int, default=200, help="bytes of payload per write")
    p.add_argument("--db", default="benchmark")
    p.add_argument("--collection", default="latency_test")
    args = p.parse_args()

    password = getpass.getpass(f"Password for {args.user}: ")

    steps = [int(x) for x in args.ramp.split(",")] if args.ramp else [args.concurrency]

    results = []
    for c in steps:
        print(f"--- concurrency={c} duration={args.duration}s ---", flush=True)
        r = run_once(args, c, password)
        results.append(r)
        print(json.dumps(r, indent=2), flush=True)

    if len(results) > 1:
        print("\n=== Summary ===")
        print(f"{'concurrency':>11} {'ops/sec':>9} {'p50 ms':>8} {'p95 ms':>8} {'p99 ms':>8} {'errors':>7}")
        for r in results:
            lat = r.get("latency_ms", {})
            print(f"{r['concurrency']:>11} {r['throughput_ops_sec']:>9} "
                  f"{lat.get('p50', '-'):>8} {lat.get('p95', '-'):>8} {lat.get('p99', '-'):>8} {r['errors']:>7}")


if __name__ == "__main__":
    main()
