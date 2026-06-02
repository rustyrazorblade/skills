#!/usr/bin/env bash
# Sets up VPC peering between two easy-db-lab DCs: peering connection, routes, and security groups.
#
# Usage: setup-vpc-peering.sh --dc1 <dc1-name> --vpc1 <vpc1-id> --cidr1 <cidr1> \
#                              --dc2 <dc2-name> --vpc2 <vpc2-id> --cidr2 <cidr2> \
#                              --region <region>
#
# What it does:
#   1. Creates a VPC peering connection between vpc1 and vpc2
#   2. Accepts the peering connection
#   3. Waits for the peering connection to become active
#   4. Finds route tables for each VPC and adds cross-DC routes
#   5. Finds security groups for each VPC and authorizes all-protocol ingress from the other CIDR
#
# Run once per DC pair. For 3 DCs, run three times: dc1↔dc2, dc1↔dc3, dc2↔dc3.

set -euo pipefail

DC1="" VPC1="" CIDR1=""
DC2="" VPC2="" CIDR2=""
REGION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dc1)     DC1="$2";     shift 2 ;;
    --vpc1)    VPC1="$2";    shift 2 ;;
    --cidr1)   CIDR1="$2";   shift 2 ;;
    --dc2)     DC2="$2";     shift 2 ;;
    --vpc2)    VPC2="$2";    shift 2 ;;
    --cidr2)   CIDR2="$2";   shift 2 ;;
    --region)  REGION="$2";  shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

for var in DC1 VPC1 CIDR1 DC2 VPC2 CIDR2 REGION; do
  [[ -z "${!var}" ]] && { echo "error: --$(echo "$var" | tr '[:upper:]' '[:lower:]') is required" >&2; exit 1; }
done

echo "=== VPC Peering: $DC1 ($VPC1) ↔ $DC2 ($VPC2) ==="

# --- 1. Create peering connection ---
echo "Creating peering connection..."
PEER_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id "$VPC1" \
  --peer-vpc-id "$VPC2" \
  --region "$REGION" \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)
echo "peering: $PEER_ID"

# --- 2. Accept peering connection ---
echo "Accepting peering connection..."
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id "$PEER_ID" \
  --region "$REGION" > /dev/null

# --- 3. Wait for active ---
echo "Waiting for peering connection to become active..."
for i in $(seq 1 20); do
  STATUS=$(aws ec2 describe-vpc-peering-connections \
    --vpc-peering-connection-ids "$PEER_ID" \
    --region "$REGION" \
    --query 'VpcPeeringConnections[0].Status.Code' \
    --output text)
  [[ "$STATUS" == "active" ]] && break
  [[ "$STATUS" == "failed" || "$STATUS" == "rejected" || "$STATUS" == "deleted" ]] && \
    { echo "error: peering connection $PEER_ID entered status: $STATUS" >&2; exit 1; }
  echo "  status: $STATUS (attempt $i/20)..."
  sleep 5
done
[[ "$STATUS" != "active" ]] && { echo "error: timed out waiting for peering connection to become active" >&2; exit 1; }
echo "active: $PEER_ID"

# --- 4. Add routes ---
add_routes() {
  local vpc="$1" dest_cidr="$2" label="$3"
  local rt_ids
  rt_ids=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$vpc" \
    --region "$REGION" \
    --query 'RouteTables[*].RouteTableId' \
    --output text)
  for rt in $rt_ids; do
    echo "route: $label $rt -> $dest_cidr"
    aws ec2 create-route \
      --route-table-id "$rt" \
      --destination-cidr-block "$dest_cidr" \
      --vpc-peering-connection-id "$PEER_ID" \
      --region "$REGION" > /dev/null || echo "  (route may already exist, skipping)"
  done
}

echo "Adding routes..."
add_routes "$VPC1" "$CIDR2" "$DC1"
add_routes "$VPC2" "$CIDR1" "$DC2"

# --- 5. Update security groups ---
authorize_ingress() {
  local vpc="$1" src_cidr="$2" label="$3"
  local sg_ids
  sg_ids=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$vpc" \
    --region "$REGION" \
    --query 'SecurityGroups[*].GroupId' \
    --output text)
  for sg in $sg_ids; do
    echo "ingress: $label $sg <- $src_cidr"
    aws ec2 authorize-security-group-ingress \
      --group-id "$sg" \
      --protocol -1 \
      --cidr "$src_cidr" \
      --region "$REGION" > /dev/null || echo "  (rule may already exist, skipping)"
  done
}

echo "Updating security groups..."
authorize_ingress "$VPC1" "$CIDR2" "$DC1"
authorize_ingress "$VPC2" "$CIDR1" "$DC2"

echo ""
echo "Done: $DC1 ↔ $DC2 peering active"
echo "  peering: $PEER_ID"
echo "  $DC1: $VPC1 ($CIDR1)"
echo "  $DC2: $VPC2 ($CIDR2)"
