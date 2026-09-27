#!/usr/bin/env bash
#
# Inventory the live AWS account and scaffold Terraform import blocks.
#
# Every call is a describe/list -- nothing here mutates AWS, so it runs under
# a read-only role. A call the role denies is recorded and skipped, never
# fatal.
#
# Output layout:
#
#   .inventory/
#     raw/<slug>.json     verbatim AWS CLI output -- the source to write HCL from
#     raw/<slug>.err      the call that failed, when one did
#     inventory.tsv       env <tab> type <tab> id <tab> name <tab> detail
#     inventory.md        the same, grouped and readable, plus what was skipped
#     imports/<env>.tf    import blocks, commented out, address pre-filled
#     imports/<env>.sh    the same as `terraform import` command lines
#
# Terraform addresses are guessed from Name tags.
# They are suggestions: verify one before uncommenting it.

set -euo pipefail

[[ ${BASH_VERSINFO[0]} -ge 4 ]] || {
    echo "bash 4+ required (macOS ships 3.2: brew install bash)" >&2
    exit 1
}

REGION=${AWS_REGION:-__REGION__}
OUT=${INVENTORY_OUT:-.inventory}
ONLY=""
WITH_RECORDS=0

usage() {
    cat <<'EOF'
Inventory the live AWS account and scaffold Terraform import blocks.

  scripts/aws-inventory.sh                      everything -> .inventory/
  scripts/aws-inventory.sh --only network,data
  scripts/aws-inventory.sh --records            + every Route 53 record set

  -r, --region REGION   default __REGION__ (or $AWS_REGION)
  -p, --profile NAME    exports AWS_PROFILE for the run
  -o, --out DIR         default .inventory
      --only GROUPS     comma list of: network compute data storage dns iam ops
      --records         enumerate Route 53 record sets too (noisy)
  -h, --help

Read-only. Nothing it runs can change the account.
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
    -r | --region)
        REGION=$2
        shift 2
        ;;
    -p | --profile)
        export AWS_PROFILE=$2
        shift 2
        ;;
    -o | --out)
        OUT=$2
        shift 2
        ;;
    --only)
        ONLY=$2
        shift 2
        ;;
    --records)
        WITH_RECORDS=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
done

for bin in aws jq; do
    command -v "$bin" >/dev/null || {
        echo "$bin is required" >&2
        exit 1
    }
done

RAW=$OUT/raw
TSV=$OUT/inventory.tsv          # env  type  id  name  detail  (+ header)
ROWS=$OUT/.rows.tsv             # type  id  name  detail
CLASSIFIED=$OUT/.classified.tsv # env  type  id  name  detail
SKIPPED=$OUT/.skipped.txt

case $OUT in '' | / | /*/..* | .) # the run starts by wiping this directory
    echo "refusing to use '$OUT' as the output directory" >&2
    exit 1
    ;;
esac

rm -rf "$OUT"
mkdir -p "$RAW" "$OUT/imports"
: >"$ROWS"
: >"$SKIPPED"

log() {
    local fmt=$1
    shift
    # shellcheck disable=SC2059
    printf "$fmt\n" "$@" >&2
}

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
CALLER=$(aws sts get-caller-identity --query Arn --output text)
STAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

log 'account %s  region %s' "$ACCOUNT" "$REGION"
log 'caller  %s' "$CALLER"
log ''

# --- collection ------------------------------------------------------------

# The Name tag, whatever the API calls its tag list.
JQ_LIB='def nm: (((.Tags // .TagList // .tags // [])
                  | if type == "object"
                    then to_entries | map({Key: .key, Value: .value})
                    else . end)
                 | map(select(.Key == "Name")) | first | .Value // "");'

want() { [[ -z $ONLY ]] || [[ ",$ONLY," == *",$1,"* ]]; }

# aws_json <slug> <region> <aws args...>  ->  raw/<slug>.json, or a skip record
aws_json() {
    local slug=$1 region=$2
    shift 2
    if aws --region "$region" "$@" --output json >"$RAW/$slug.json" 2>"$RAW/$slug.err"; then
        rm -f "$RAW/$slug.err"
        return 0
    fi
    printf '%-34s %s\n' "$slug" "$(tr -d '\n' <"$RAW/$slug.err" | cut -c1-160)" >>"$SKIPPED"
    rm -f "$RAW/$slug.json"
    return 1
}

# from_raw <slug> <tf_type> <jq filter -> [id, name, detail]>
# Turns an already-fetched response into inventory rows. Lets one API call feed
# two resource types (ingress and egress rules, route tables and their
# associations) without asking AWS twice. A filter that does not fit the
# response is recorded like a denied call, so one bad shape cannot abort the run.
from_raw() {
    local slug=$1 type=$2 filter=$3
    local chunk=$OUT/.chunk.tsv err=$OUT/.chunk.err n
    [[ -f $RAW/$slug.json ]] || return 0

    if ! jq -r "$JQ_LIB $filter | @tsv" "$RAW/$slug.json" >"$chunk" 2>"$err"; then
        printf '%-34s %s\n' "$slug ($type)" "$(tr -d '\n' <"$err" | cut -c1-160)" >>"$SKIPPED"
        return 0
    fi

    awk -F'\t' -v OFS='\t' -v t="$type" '$1 != "" { print t, $1, $2, $3 }' "$chunk" >>"$ROWS"
    n=$(awk -F'\t' '$1 != ""' "$chunk" | wc -l | tr -d ' ')
    log '  %-40s %4d' "$type" "$n"
}

# collect_in <region> <slug> <tf_type> <jq filter> <aws args...>
collect_in() {
    local region=$1 slug=$2 type=$3 filter=$4
    shift 4
    aws_json "$slug" "$region" "$@" || return 0
    from_raw "$slug" "$type" "$filter"
}

collect() { collect_in "$REGION" "$@"; }

collect_network() {
    log 'network'

    collect vpcs aws_vpc \
        '.Vpcs[] | [.VpcId, nm, "cidr=\(.CidrBlock),default=\(.IsDefault)"]' \
        ec2 describe-vpcs

    collect subnets aws_subnet \
        '.Subnets[] | [.SubnetId, nm, "vpc=\(.VpcId),az=\(.AvailabilityZone),cidr=\(.CidrBlock),autopublic=\(.MapPublicIpOnLaunch),tier=\(((.Tags // []) | map(select(.Key == "Tier")) | first | .Value) // "")"]' \
        ec2 describe-subnets

    collect internet-gateways aws_internet_gateway \
        '.InternetGateways[] | [.InternetGatewayId, nm, "vpc=\(((.Attachments // [])[0].VpcId) // "")"]' \
        ec2 describe-internet-gateways

    collect nat-gateways aws_nat_gateway \
        '.NatGateways[] | select(.State != "deleted" and .State != "failed") | [.NatGatewayId, nm, "vpc=\(.VpcId),subnet=\(.SubnetId),state=\(.State)"]' \
        ec2 describe-nat-gateways

    collect eips aws_eip \
        '.Addresses[] | [.AllocationId, nm, "ip=\(.PublicIp),instance=\(.InstanceId // ""),eni=\(.NetworkInterfaceId // "")"]' \
        ec2 describe-addresses

    collect route-tables aws_route_table \
        '.RouteTables[] | [.RouteTableId, nm, "vpc=\(.VpcId),main=\(((.Associations // []) | map(.Main) | any)),routes=\((.Routes // []) | length)"]' \
        ec2 describe-route-tables

    # An association imports as subnet-id/route-table-id, not by its own id.
    from_raw route-tables aws_route_table_association \
        '.RouteTables[] | .RouteTableId as $rtb | .VpcId as $vpc
           | (.Associations // [])[] | select(.SubnetId != null)
           | ["\(.SubnetId)/\($rtb)", "", "vpc=\($vpc),subnet=\(.SubnetId),rtb=\($rtb)"]'

    collect security-groups aws_security_group \
        '.SecurityGroups[] | [.GroupId, .GroupName, "vpc=\(.VpcId),default=\(.GroupName == "default")"]' \
        ec2 describe-security-groups

    # This repo models rules as standalone resources, so each rule imports on
    # its own id. Inline ingress/egress blocks would churn on every plan.
    collect security-group-rules aws_vpc_security_group_ingress_rule \
        '.SecurityGroupRules[] | select(.IsEgress | not) | [.SecurityGroupRuleId, nm, "sg=\(.GroupId),proto=\(.IpProtocol),from=\(.FromPort // -1),to=\(.ToPort // -1),source=\((.CidrIpv4 // .CidrIpv6 // .PrefixListId // .ReferencedGroupInfo.GroupId) // "")"]' \
        ec2 describe-security-group-rules

    from_raw security-group-rules aws_vpc_security_group_egress_rule \
        '.SecurityGroupRules[] | select(.IsEgress) | [.SecurityGroupRuleId, nm, "sg=\(.GroupId),proto=\(.IpProtocol),from=\(.FromPort // -1),to=\(.ToPort // -1),dest=\((.CidrIpv4 // .CidrIpv6 // .PrefixListId // .ReferencedGroupInfo.GroupId) // "")"]'

    collect vpc-endpoints aws_vpc_endpoint \
        '.VpcEndpoints[] | [.VpcEndpointId, nm, "vpc=\(.VpcId),service=\(.ServiceName),type=\(.VpcEndpointType)"]' \
        ec2 describe-vpc-endpoints

    collect flow-logs aws_flow_log \
        '.FlowLogs[] | [.FlowLogId, nm, "vpc=\(.ResourceId),dest=\(.LogDestinationType)"]' \
        ec2 describe-flow-logs

    collect network-acls aws_network_acl \
        '.NetworkAcls[] | [.NetworkAclId, nm, "vpc=\(.VpcId),default=\(.IsDefault)"]' \
        ec2 describe-network-acls

    collect vpc-peering aws_vpc_peering_connection \
        '.VpcPeeringConnections[] | select(.Status.Code == "active") | [.VpcPeeringConnectionId, nm, "vpc=\(.RequesterVpcInfo.VpcId),peer=\(.AccepterVpcInfo.VpcId)"]' \
        ec2 describe-vpc-peering-connections
}

collect_compute() {
    log 'compute'

    collect instances aws_instance \
        '.Reservations[].Instances[] | select(.State.Name != "terminated") | [.InstanceId, nm, "vpc=\(.VpcId // ""),subnet=\(.SubnetId // ""),az=\(.Placement.AvailabilityZone),type=\(.InstanceType),state=\(.State.Name),ami=\(.ImageId),profile=\((.IamInstanceProfile.Arn) // "")"]' \
        ec2 describe-instances

    collect volumes aws_ebs_volume \
        '.Volumes[] | [.VolumeId, nm, "az=\(.AvailabilityZone),size=\(.Size),type=\(.VolumeType),instance=\((((.Attachments // [])[0]).InstanceId) // ""),device=\(((((.Attachments // [])[0]).Device) // "") | sub("^/dev/"; ""))"]' \
        ec2 describe-volumes

    collect key-pairs aws_key_pair \
        '.KeyPairs[] | [.KeyName, .KeyName, "fingerprint=\(.KeyFingerprint // "")"]' \
        ec2 describe-key-pairs

    collect amis aws_ami \
        '.Images[] | [.ImageId, (.Name // nm), "created=\(.CreationDate)"]' \
        ec2 describe-images --owners self

    collect launch-templates aws_launch_template \
        '.LaunchTemplates[] | [.LaunchTemplateId, .LaunchTemplateName, "version=\(.LatestVersionNumber)"]' \
        ec2 describe-launch-templates

    collect asgs aws_autoscaling_group \
        '.AutoScalingGroups[] | [.AutoScalingGroupName, .AutoScalingGroupName, "min=\(.MinSize),max=\(.MaxSize),desired=\(.DesiredCapacity)"]' \
        autoscaling describe-auto-scaling-groups

    collect albs aws_lb \
        '.LoadBalancers[] | [.LoadBalancerArn, .LoadBalancerName, "vpc=\(.VpcId),type=\(.Type),scheme=\(.Scheme),dns=\(.DNSName)"]' \
        elbv2 describe-load-balancers

    collect target-groups aws_lb_target_group \
        '.TargetGroups[] | [.TargetGroupArn, .TargetGroupName, "vpc=\(.VpcId // ""),port=\(.Port // 0),proto=\(.Protocol // "")"]' \
        elbv2 describe-target-groups

    collect elbs-classic aws_elb \
        '.LoadBalancerDescriptions[] | [.LoadBalancerName, .LoadBalancerName, "vpc=\(.VPCId // ""),dns=\(.DNSName)"]' \
        elb describe-load-balancers

    # Listeners are per load balancer, so they need a second round of calls.
    if [[ -f $RAW/albs.json ]]; then
        local arn tag
        while read -r arn; do
            tag=$(printf '%s' "${arn##*/}" | tr -c 'a-zA-Z0-9_.-' '-')
            collect "listeners-$tag" aws_lb_listener \
                '.Listeners[] | [.ListenerArn, "", "lb=\(.LoadBalancerArn | split("/") | .[-2]),port=\(.Port),proto=\(.Protocol)"]' \
                elbv2 describe-listeners --load-balancer-arn "$arn"
        done < <(jq -r '.LoadBalancers[].LoadBalancerArn' "$RAW/albs.json")
    fi
}

collect_data() {
    log 'data'

    collect rds-instances aws_db_instance \
        '.DBInstances[] | [.DBInstanceIdentifier, .DBInstanceIdentifier, "engine=\(.Engine)-\(.EngineVersion),class=\(.DBInstanceClass),multiaz=\(.MultiAZ),vpc=\(.DBSubnetGroup.VpcId // ""),subnetgroup=\(.DBSubnetGroup.DBSubnetGroupName // ""),cluster=\(.DBClusterIdentifier // "")"]' \
        rds describe-db-instances

    collect rds-clusters aws_rds_cluster \
        '.DBClusters[] | [.DBClusterIdentifier, .DBClusterIdentifier, "engine=\(.Engine)-\(.EngineVersion),members=\((.DBClusterMembers // []) | length)"]' \
        rds describe-db-clusters

    collect rds-subnet-groups aws_db_subnet_group \
        '.DBSubnetGroups[] | [.DBSubnetGroupName, .DBSubnetGroupName, "vpc=\(.VpcId),subnets=\((.Subnets // []) | length)"]' \
        rds describe-db-subnet-groups

    collect rds-parameter-groups aws_db_parameter_group \
        '.DBParameterGroups[] | select(.DBParameterGroupName | startswith("default.") | not) | [.DBParameterGroupName, .DBParameterGroupName, "family=\(.DBParameterGroupFamily)"]' \
        rds describe-db-parameter-groups

    collect elasticache aws_elasticache_cluster \
        '.CacheClusters[] | [.CacheClusterId, .CacheClusterId, "engine=\(.Engine)-\(.EngineVersion),class=\(.CacheNodeType)"]' \
        elasticache describe-cache-clusters

    collect elasticache-groups aws_elasticache_replication_group \
        '.ReplicationGroups[] | [.ReplicationGroupId, .ReplicationGroupId, "status=\(.Status),members=\((.MemberClusters // []) | length)"]' \
        elasticache describe-replication-groups

    collect dynamodb aws_dynamodb_table \
        '.TableNames[] | [., ., ""]' \
        dynamodb list-tables

    collect msk aws_msk_cluster \
        '.ClusterInfoList[] | [.ClusterArn, .ClusterName, "type=\(.ClusterType // "")"]' \
        kafka list-clusters-v2
}

collect_storage() {
    log 'storage'

    # Buckets are global; only get-bucket-location says which region one is in.
    if aws_json s3-buckets "$REGION" s3api list-buckets; then
        local n=0 bucket loc
        while read -r bucket; do
            loc=$(aws s3api get-bucket-location --bucket "$bucket" \
                --query 'LocationConstraint' --output text 2>/dev/null || echo unknown)
            case $loc in None | null | '') loc=us-east-1 ;; esac
            printf 'aws_s3_bucket\t%s\t%s\tregion=%s\n' "$bucket" "$bucket" "$loc" >>"$ROWS"
            n=$((n + 1))
        done < <(jq -r '.Buckets[].Name' "$RAW/s3-buckets.json")
        log '  %-40s %4d' aws_s3_bucket "$n"
    fi

    collect efs aws_efs_file_system \
        '.FileSystems[] | [.FileSystemId, (.Name // nm), "size=\(.SizeInBytes.Value),encrypted=\(.Encrypted)"]' \
        efs describe-file-systems

    collect ecr aws_ecr_repository \
        '.repositories[] | [.repositoryName, .repositoryName, "uri=\(.repositoryUri)"]' \
        ecr describe-repositories
}

collect_dns() {
    log 'dns and edge'

    collect_in us-east-1 route53-zones aws_route53_zone \
        '.HostedZones[] | [(.Id | sub("^/hostedzone/"; "")), .Name, "private=\(.Config.PrivateZone),records=\(.ResourceRecordSetCount)"]' \
        route53 list-hosted-zones

    if [[ $WITH_RECORDS -eq 1 && -f $RAW/route53-zones.json ]]; then
        local zone
        while read -r zone; do
            # aws_route53_record imports as ZONEID_name_type.
            collect_in us-east-1 "route53-records-$zone" aws_route53_record \
                ".ResourceRecordSets[] | select(.Type != \"SOA\") | [\"${zone}_\(.Name)_\(.Type)\", .Name, \"zone=${zone},type=\(.Type)\"]" \
                route53 list-resource-record-sets --hosted-zone-id "$zone"
        done < <(jq -r '.HostedZones[].Id | sub("^/hostedzone/"; "")' "$RAW/route53-zones.json")
    fi

    collect acm aws_acm_certificate \
        '.CertificateSummaryList[] | [.CertificateArn, .DomainName, "status=\(.Status // ""),inuse=\(.InUse // false)"]' \
        acm list-certificates

    # CloudFront only accepts certificates issued in us-east-1.
    collect_in us-east-1 acm-us-east-1 aws_acm_certificate \
        '.CertificateSummaryList[] | [.CertificateArn, .DomainName, "region=us-east-1,status=\(.Status // "")"]' \
        acm list-certificates

    collect_in us-east-1 cloudfront aws_cloudfront_distribution \
        '.DistributionList.Items[]? | [.Id, (((.Aliases.Items // [])[0]) // .DomainName), "domain=\(.DomainName),enabled=\(.Enabled)"]' \
        cloudfront list-distributions
}

collect_iam() {
    log 'iam (global)'

    collect_in us-east-1 iam-roles aws_iam_role \
        '.Roles[] | select(.Path | startswith("/aws-service-role/") | not) | [.RoleName, .RoleName, "path=\(.Path),created=\(.CreateDate)"]' \
        iam list-roles

    collect_in us-east-1 iam-policies aws_iam_policy \
        '.Policies[] | [.Arn, .PolicyName, "attached=\(.AttachmentCount)"]' \
        iam list-policies --scope Local

    collect_in us-east-1 iam-users aws_iam_user \
        '.Users[] | [.UserName, .UserName, "created=\(.CreateDate)"]' \
        iam list-users

    collect_in us-east-1 iam-groups aws_iam_group \
        '.Groups[] | [.GroupName, .GroupName, "path=\(.Path)"]' \
        iam list-groups

    collect_in us-east-1 iam-instance-profiles aws_iam_instance_profile \
        '.InstanceProfiles[] | [.InstanceProfileName, .InstanceProfileName, "roles=\((.Roles // []) | map(.RoleName) | join(" "))"]' \
        iam list-instance-profiles

    collect_in us-east-1 iam-oidc aws_iam_openid_connect_provider \
        '.OpenIDConnectProviderList[] | [.Arn, (.Arn | split("/") | last), ""]' \
        iam list-open-id-connect-providers

    collect_in us-east-1 iam-saml aws_iam_saml_provider \
        '.SAMLProviderList[] | [.Arn, (.Arn | split("/") | last), ""]' \
        iam list-saml-providers

    # A managed-policy attachment imports as role-name/policy-arn.
    if [[ -f $RAW/iam-roles.json ]]; then
        local role tag
        while read -r role; do
            tag=$(printf '%s' "$role" | tr -c 'a-zA-Z0-9_.-' '-')
            collect_in us-east-1 "iam-attached-$tag" aws_iam_role_policy_attachment \
                ".AttachedPolicies[] | [\"${role}/\(.PolicyArn)\", \"${role}\", \"role=${role},policy=\(.PolicyName)\"]" \
                iam list-attached-role-policies --role-name "$role"
        done < <(jq -r '.Roles[] | select(.Path | startswith("/aws-service-role/") | not) | .RoleName' "$RAW/iam-roles.json")
    fi
}

collect_ops() {
    log 'ops'

    collect log-groups aws_cloudwatch_log_group \
        '.logGroups[] | [.logGroupName, .logGroupName, "retention=\(.retentionInDays // 0),bytes=\(.storedBytes // 0)"]' \
        logs describe-log-groups

    collect alarms aws_cloudwatch_metric_alarm \
        '.MetricAlarms[] | [.AlarmName, .AlarmName, "metric=\(.MetricName // ""),ns=\(.Namespace // "")"]' \
        cloudwatch describe-alarms

    collect event-rules aws_cloudwatch_event_rule \
        '.Rules[] | [.Name, .Name, "schedule=\(.ScheduleExpression // ""),state=\(.State)"]' \
        events list-rules

    collect sns aws_sns_topic \
        '.Topics[] | [.TopicArn, (.TopicArn | split(":") | last), ""]' \
        sns list-topics

    collect sqs aws_sqs_queue \
        '.QueueUrls[]? | [., (. | split("/") | last), ""]' \
        sqs list-queues

    collect lambda aws_lambda_function \
        '.Functions[] | [.FunctionName, .FunctionName, "runtime=\(.Runtime // "container"),memory=\(.MemorySize)"]' \
        lambda list-functions

    # Metadata only. The readonly role denies every secret and parameter value,
    # and a value read at plan time would land in state anyway.
    collect secrets aws_secretsmanager_secret \
        '.SecretList[] | [.ARN, .Name, "rotation=\(.RotationEnabled // false)"]' \
        secretsmanager list-secrets

    collect ssm-parameters aws_ssm_parameter \
        '.Parameters[] | [.Name, .Name, "type=\(.Type),tier=\(.Tier // "")"]' \
        ssm describe-parameters

    collect kms-aliases aws_kms_alias \
        '.Aliases[] | select(.AliasName | startswith("alias/aws/") | not) | [.AliasName, .AliasName, "key=\(.TargetKeyId // "")"]' \
        kms list-aliases
}

if want network; then collect_network; fi
if want compute; then collect_compute; fi
if want data; then collect_data; fi
if want storage; then collect_storage; fi
if want dns; then collect_dns; fi
if want iam; then collect_iam; fi
if want ops; then collect_ops; fi

# --- classify --------------------------------------------------------------
#
# The environment comes from the name, then from the detail, then from the VPC
# or the instance the resource hangs off. Whatever is left lands in
# imports/unassigned.tf for a human to place.

awk -F'\t' -v OFS='\t' '
  # AcmeProdVPC and acme-prod-vpc have to read the same, so break camel case into
  # words first -- otherwise "prod" sits mid-word and no boundary matches.
  function words(s,   out, i, c, p) {
    out = ""
    p = ""
    for (i = 1; i <= length(s); i++) {
      c = substr(s, i, 1)
      if (c ~ /[A-Z]/ && p ~ /[a-z0-9]/) out = out "-"
      out = out c
      p = c
    }
    return tolower(out)
  }
  function envof(s,   t) {
    t = words(s)
    if (t ~ /(^|[^a-z])(prod|production|prd)([^a-z]|$)/)                return "prod"
    if (t ~ /(^|[^a-z])(stg|staging|stage|dev|test|uat|qa)([^a-z]|$)/)  return "stg"
    if (t ~ /(tfstate|terraform|oidc|githubactions)/)                   return "shared"
    return ""
  }
  # A volume carries no vpc=, only its instance; a rule carries only its group.
  function inherit(detail,   v, h, g) {
    if (match(detail, /vpc=vpc-[0-9a-z]+/)) {
      v = substr(detail, RSTART + 4, RLENGTH - 4)
      if (v in vpcenv) return vpcenv[v]
    }
    if (match(detail, /instance=i-[0-9a-z]+/)) {
      h = substr(detail, RSTART + 9, RLENGTH - 9)
      if (h in instenv) return instenv[h]
    }
    if (match(detail, /sg=sg-[0-9a-z]+/)) {
      g = substr(detail, RSTART + 3, RLENGTH - 3)
      if (g in sgenv) return sgenv[g]
    }
    return ""
  }
  # What a resource hangs off beats a substring of its own detail: "device=xvda"
  # or an AMI name should not outvote the VPC the thing actually sits in.
  function classify(name, detail,   e) {
    e = envof(name)
    if (e == "") e = inherit(detail)
    if (e == "") e = envof(detail)
    return e
  }
  FNR == 1 { pass++ }
  # 1 VPCs, 2 the things others hang off (volumes/EIPs on instances, rules on
  # groups), 3 everything.
  pass == 1 { if ($1 == "aws_vpc") { e = envof($3); if (e != "") vpcenv[$2] = e } next }
  pass == 2 {
    e = classify($3, $4)
    if (e != "" && $1 == "aws_instance")       instenv[$2] = e
    if (e != "" && $1 == "aws_security_group") sgenv[$2]   = e
    next
  }
  {
    e = classify($3, $4)
    if (e == "") e = ($1 ~ /^aws_iam/) ? "shared" : "unassigned"
    print e, $1, $2, $3, $4
  }
' "$ROWS" "$ROWS" "$ROWS" | sort -t$'\t' -k1,1 -k2,2 -k4,4 >"$CLASSIFIED"

{
    printf 'env\ttype\tid\tname\tdetail\n'
    cat "$CLASSIFIED"
} >"$TSV"

rm -f "$OUT/.chunk.tsv" "$OUT/.chunk.err"

# --- import scaffolding ----------------------------------------------------

# One address name per resource: AcmeProd-PaymentsAPI becomes payments_api.
slug() {
    printf '%s' "$1" |
        sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' |
        tr 'A-Z' 'a-z' |
        sed -E 's#^arn:[^[:space:]]*[:/]##
                s/^__PREFIX__[-_]//
                s/(^|[-_])(prod|production|prd|stg|staging|stage|dev|test|uat|qa)([-_]|$)/\1/g
                s/[^a-z0-9]+/_/g
                s/^_+//
                s/_+$//'
}

# field <key> <detail>  ->  the value of key=... in a comma-separated detail
field() { printf '%s' "$2" | tr ',' '\n' | sed -n "s/^$1=//p" | head -1; }

declare -A INSTANCE_NAME=() # instance id  -> Name tag
declare -A SG_NAME=()       # security group id -> group name

# A plain resource address named after the resource, or after its owner for
# rules, Elastic IPs and volumes. A starting point: rename to fit the stack.
address() {
    local type=$1 id=$2 name=$3 detail=$4
    local s host

    s=$(slug "$name")
    [[ -n $s ]] || s=$(slug "$id")
    [[ -n $s ]] || s=TODO

    case $type in
    aws_vpc_security_group_ingress_rule | aws_vpc_security_group_egress_rule)
        host=$(field sg "$detail")
        [[ -z $host || -z ${SG_NAME[$host]:-} ]] || s="$(slug "${SG_NAME[$host]}")_$(slug "$id")"
        ;;
    aws_eip)
        host=$(field instance "$detail")
        [[ -z $host || -z ${INSTANCE_NAME[$host]:-} ]] || s=$(slug "${INSTANCE_NAME[$host]}")
        ;;
    aws_ebs_volume)
        host=$(field instance "$detail")
        [[ -z $host || -z ${INSTANCE_NAME[$host]:-} ]] || s=$(slug "${INSTANCE_NAME[$host]}")
        # A root volume lives inside aws_instance.root_block_device; importing it
        # on its own gives Terraform two owners of one disk.
        case $(field device "$detail") in
        xvda | sda1 | nvme0n1)
            echo "SKIP:root volume of ${host:-?} -- comes in with the instance"
            return
            ;;
        esac
        ;;
    esac

    echo "${type}.${s}"
}

# Tab is IFS whitespace, so `read` folds a run of them into one separator and an
# untagged resource shifts its detail into the name column. US does not fold.
US=$'\037'

while IFS=$US read -r _ type id name _rest; do
    case $type in
    aws_instance) INSTANCE_NAME[$id]=$name ;;
    aws_security_group) SG_NAME[$id]=$name ;;
    esac
done < <(tr '\t' "$US" <"$CLASSIFIED")

# A bucket's other aspects are separate resources, each importing on the bucket name.
S3_COMPANIONS=(
    aws_s3_bucket_public_access_block
    aws_s3_bucket_ownership_controls
    aws_s3_bucket_versioning
    aws_s3_bucket_server_side_encryption_configuration
    aws_s3_bucket_lifecycle_configuration
    aws_s3_bucket_cors_configuration
    aws_s3_bucket_policy
)

stack_of() {
    case $1 in
    shared) echo shared ;;
    prod) echo envs/prod ;;
    stg) echo envs/stg ;;
    *) echo 'STACK' ;;
    esac
}

emit() { # emit <tf file> <sh file> <stack> <address> <id> <note>
    {
        [[ -z $6 ]] || echo "# $6"
        echo '# import {'
        echo "#   to = $4"
        echo "#   id = \"$5\""
        echo '# }'
        echo
    } >>"$1"
    echo "# terraform -chdir=$3 import '$4' '$5'" >>"$2"
}

gen_imports() {
    local env=$1 stack tf sh count=0 last=''
    stack=$(stack_of "$env")
    tf=$OUT/imports/$env.tf
    sh=$OUT/imports/$env.sh

    {
        echo "# $stack/imports.tf -- generated $STAMP by scripts/aws-inventory.sh"
        echo '#'
        echo "#   cp $OUT/imports/$env.tf $stack/imports.tf"
        echo '#'
        echo "# Addresses are guessed from Name tags; rename to fit the stack. Uncomment a"
        echo '# block only together with the HCL that declares the resource, then'
        echo "#   just plan $stack"
        echo '# until it reads 0 to add, 0 to change, 0 to destroy. Delete the block once'
        echo '# the apply has run.'
        echo '#'
        echo '# AZ, RULE and TODO inside an address are placeholders to fill in by hand.'
        echo
    } >"$tf"

    {
        echo '#!/usr/bin/env bash'
        echo "# The same imports as $env.tf, for a Terraform older than 1.5."
        echo "# Uncomment a line once its resource is declared in $stack."
        echo 'set -euo pipefail'
        echo
    } >"$sh"

    local e type id name detail addr companion
    while IFS=$US read -r e type id name detail; do
        [[ $e == "$env" ]] || continue

        if [[ $type != "$last" ]]; then
            printf '\n# --- %s %s\n\n' "$type" \
                "$(printf '%*s' "$((70 - ${#type}))" '' | tr ' ' '-')" >>"$tf"
            last=$type
        fi

        addr=$(address "$type" "$id" "$name" "$detail")
        if [[ $addr == SKIP:* ]]; then
            printf '# %s -- %s\n\n' "$id" "${addr#SKIP:}" >>"$tf"
            continue
        fi
        emit "$tf" "$sh" "$stack" "$addr" "$id" "${name:-(untagged)}  $detail"
        count=$((count + 1))

        if [[ $type == aws_s3_bucket ]]; then
            for companion in "${S3_COMPANIONS[@]}"; do
                emit "$tf" "$sh" "$stack" \
                    "${companion}.$(slug "$name")" "$id" \
                    "${companion} -- only if the live bucket has one"
                count=$((count + 1))
            done
        fi
    done < <(tr '\t' "$US" <"$CLASSIFIED")

    chmod +x "$sh"
    log '  %-40s %4d' "imports/$env.tf" "$count"
}

log ''
log 'scaffolding'
for env in shared stg prod unassigned; do
    gen_imports "$env"
done

# --- summary ---------------------------------------------------------------

{
    echo '# AWS inventory'
    echo
    echo '| | |'
    echo '|---|---|'
    echo "| Account | \`$ACCOUNT\` |"
    echo "| Region | \`$REGION\` |"
    echo "| Caller | \`$CALLER\` |"
    echo "| Taken | $STAMP |"
    echo "| Resources | $(wc -l <"$CLASSIFIED" | tr -d ' ') |"
    echo
    echo 'Environment is guessed from the Name tag, then from the VPC the resource sits'
    echo 'in. Whatever is left over is in `imports/unassigned.tf`.'
    echo

    for env in shared stg prod unassigned; do
        n=$(awk -F'\t' -v e="$env" '$1 == e' "$CLASSIFIED" | wc -l | tr -d ' ')
        [[ $n -gt 0 ]] || continue
        echo "## $env — $n resources"
        echo
        echo "\`$(stack_of "$env")\` · scaffold in \`imports/$env.tf\`"
        echo
        echo '| type | name | id | detail |'
        echo '|---|---|---|---|'
        awk -F'\t' -v e="$env" '$1 == e {
            printf "| `%s` | %s | `%s` | %s |\n", $2, ($4 == "" ? "—" : $4), $3, $5
        }' "$CLASSIFIED"
        echo
    done

    if [[ -s $SKIPPED ]]; then
        echo '## Skipped calls'
        echo
        echo 'Denied by the role, unsupported in this region, or the service is unused.'
        echo
        echo '```'
        cat "$SKIPPED"
        echo '```'
    fi
} >"$OUT/inventory.md"

log ''
log 'wrote %s' "$OUT/inventory.md"
log '      %s' "$TSV"
log '      %s/imports/{shared,stg,prod,unassigned}.{tf,sh}' "$OUT"
if [[ -s $SKIPPED ]]; then
    log '%s calls skipped -- listed at the end of inventory.md' "$(wc -l <"$SKIPPED" | tr -d ' ')"
fi
