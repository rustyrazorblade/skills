#!/usr/bin/env bash
# vpc-peer.sh — peer two VPCs: create connection, add routes, open security groups.
#
# Usage:
#   vpc-peer.sh <vpc1-id> <vpc2-id>
#
# Environment variables:
#   AWS_PROFILE          — AWS profile to use (e.g. sandbox-admin)
#   AWS_DEFAULT_REGION   — AWS region (required)
#
# Both VPCs must be in the same region. CIDRs are discovered from the AWS API —
# never assumed from naming conventions or init arguments.

set -euo pipefail

VPC1=${1:-}
VPC2=${2:-}

if [[ -z "$VPC1" || -z "$VPC2" ]]; then
  echo "Usage: $0 <vpc1-id> <vpc2-id>" >&2
  echo "Set AWS_PROFILE and AWS_DEFAULT_REGION as needed." >&2
  exit 1
fi

if [[ -z "${AWS_DEFAULT_REGION:-}" ]]; then
  echo "Error: AWS_DEFAULT_REGION must be set." >&2
  exit 1
fi

REGION="$AWS_DEFAULT_REGION"
AWS_ARGS=(--region "$REGION")
[[ -n "${AWS_PROFILE:-}" ]] && AWS_ARGS+=(--profile "$AWS_PROFILE")

echo "=== VPC Peering: $VPC1 <-> $VPC2 (region: $REGION) ==="

# Discover CIDRs dynamically — never assume from init args or naming
echo "Discovering CIDRs..."
CIDR1=$(aws ec2 describe-vpcs --vpc-ids "$VPC1" "${AWS_ARGS[@]}" \
  --query 'Vpcs[0].CidrBlock' --output text)
CIDR2=$(aws ec2 describe-vpcs --vpc-ids "$VPC2" "${AWS_ARGS[@]}" \
  --query 'Vpcs[0].CidrBlock' --output text)
echo "  $VPC1: $CIDR1"
echo "  $VPC2: $CIDR2"

# Create and accept peering connection
echo "Creating peering connection..."
PEER_ID=$(aws ec2 create-vpc-peering-connection \
  --vpc-id "$VPC1" \
  --peer-vpc-id "$VPC2" \
  "${AWS_ARGS[@]}" \
  --query 'VpcPeeringConnection.VpcPeeringConnectionId' \
  --output text)
echo "  Peering ID: $PEER_ID"

echo "Accepting peering connection..."
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id "$PEER_ID" \
  "${AWS_ARGS[@]}" > /dev/null
echo "  Accepted."

# Add routes to every route table in each VPC
add_routes() {
  local VPC=$1 DEST_CIDR=$2
  local RTS
  RTS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC" \
    "${AWS_ARGS[@]}" \
    --query 'RouteTables[*].RouteTableId' \
    --output text)
  for RT in $RTS; do
    echo "  $RT: adding route $DEST_CIDR -> $PEER_ID"
    aws ec2 create-route \
      --route-table-id "$RT" \
      --destination-cidr-block "$DEST_CIDR" \
      --vpc-peering-connection-id "$PEER_ID" \
      "${AWS_ARGS[@]}" > /dev/null
  done
}

echo "Adding routes in $VPC1 (-> $CIDR2)..."
add_routes "$VPC1" "$CIDR2"

echo "Adding routes in $VPC2 (-> $CIDR1)..."
add_routes "$VPC2" "$CIDR1"

# Authorize cross-VPC traffic in all security groups for each VPC
open_sg() {
  local VPC=$1 CIDR=$2
  local SGS
  SGS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC" \
    "${AWS_ARGS[@]}" \
    --query 'SecurityGroups[*].GroupId' \
    --output text)
  for SG in $SGS; do
    echo "  $SG: authorizing all traffic from $CIDR"
    aws ec2 authorize-security-group-ingress \
      --group-id "$SG" \
      --protocol -1 \
      --cidr "$CIDR" \
      "${AWS_ARGS[@]}" > /dev/null \
      && true || echo "  (rule already exists, skipping)"
  done
}

echo "Updating $VPC1 security groups (allow $CIDR2)..."
open_sg "$VPC1" "$CIDR2"

echo "Updating $VPC2 security groups (allow $CIDR1)..."
open_sg "$VPC2" "$CIDR1"

echo ""
echo "=== Done ==="
echo "Peering connection: $PEER_ID"
echo "$VPC1 ($CIDR1) <-> $VPC2 ($CIDR2)"
