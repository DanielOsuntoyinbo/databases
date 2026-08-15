# PSMDB Multi-Region Lab

Live 3-AWS-region Percona Server for MongoDB lab (London `eu-west-2`,
Ireland `eu-west-1`, Paris `eu-west-3`) for the Percona Live 2026 talk.
Full architecture and phased build plan: see
`docs/00-lab-architecture-and-build-plan.md`.

PSMDB version pinned: **7.0.39-21** (2026-08-05 — contains a critical CVE
fix, do not use an older 7.0.x build).

## Phase 1 — network foundation (this drop)

Builds:
- 3 VPCs, one per region, each with 2 public subnets across 2 AZs
- 3 regional Transit Gateways
- A full-mesh of 3 TGW peering attachments (lon↔ire, ire↔par, lon↔par)
- Static routes so each region's TGW and VPC route table can reach the
  other two regions' CIDRs

No EC2 instances yet — that's Phase 2. This phase's job is to prove
cross-region routing works before any MongoDB config goes anywhere.

## Prerequisites

- Terraform >= 1.7.0
- AWS provider ~> 5.60
- A single AWS credential/profile with access to all three regions
  (provider aliases handle the per-region routing — you don't need
  separate credentials per region)
- IAM permissions: VPC, EC2 (subnets/route tables/IGW), Transit Gateway
  (create/describe/peering) in `eu-west-2`, `eu-west-1`, `eu-west-3`

## Usage

```bash
export AWS_PROFILE=your-profile   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY

make init
make plan     # review before applying — check the 3x VPC, 3x TGW,
              # 3x peering attachment, 6x TGW route, 6x VPC route counts
make apply
make output   # prints vpc_ids / tgw_ids / peering_attachment_ids as JSON
```

Teardown (do this between working sessions — TGW attachments and
peering attachments bill hourly):

```bash
make destroy
```

## Validating Phase 1 before moving to Phase 2

No EC2 instances exist yet, so you can't `ping` across regions directly.
Confirm the network layer is actually correct with the AWS CLI instead:

```bash
# Peering attachments should show state = available in all 3 regions
aws ec2 describe-transit-gateway-peering-attachments --region eu-west-2
aws ec2 describe-transit-gateway-peering-attachments --region eu-west-1
aws ec2 describe-transit-gateway-peering-attachments --region eu-west-3

# Each region's TGW route table should show routes to both peer CIDRs
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <london tgw_route_table_id> \
  --filters "Name=type,Values=static" --region eu-west-2
```

If a peering attachment sits in `pendingAcceptance` instead of
`available`, the accepter-side resource didn't apply — re-run
`make apply`, Terraform will pick up the accepter resource.

Real cross-region ping validation happens in Phase 2, once the first
EC2 nodes exist in each region's subnets.

## Known cost note

Each TGW VPC attachment and each TGW peering attachment bills hourly
(~$0.05/hr each) regardless of traffic. With 3 VPC attachments + 3
peering attachments that's 6 attachment-hours running from `apply` to
`destroy` — `make destroy` overnight rather than leaving Phase 1 running
idle.
