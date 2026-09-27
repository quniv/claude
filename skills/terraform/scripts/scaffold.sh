#!/usr/bin/env bash
# Copy the boilerplate template into a new directory and fill in its tokens.
#
#   scaffold.sh <dest> --prefix acme --account-id 123456789012 --region eu-west-1 \
#               --github-org acme-inc --github-repo acme-terraform [--aws-profile acme]
#
# Refuses a non-empty destination and fails if any __TOKEN__ survives.

set -euo pipefail

TEMPLATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/template" && pwd)"

die() {
    echo "scaffold: $*" >&2
    exit 1
}

[[ $# -ge 1 && $1 != -* ]] || die "usage: scaffold.sh <dest> --prefix P --account-id N --region R --github-org O --github-repo R [--aws-profile P]"
DEST=$1
shift

PREFIX="" ACCOUNT_ID="" REGION="" GITHUB_ORG="" GITHUB_REPO="" AWS_PROFILE_NAME=""
while [[ $# -gt 0 ]]; do
    [[ $# -ge 2 ]] || die "missing value for $1"
    case $1 in
    --prefix) PREFIX=$2 ;;
    --account-id) ACCOUNT_ID=$2 ;;
    --region) REGION=$2 ;;
    --github-org) GITHUB_ORG=$2 ;;
    --github-repo) GITHUB_REPO=$2 ;;
    --aws-profile) AWS_PROFILE_NAME=$2 ;;
    *) die "unknown option: $1" ;;
    esac
    shift 2
done
AWS_PROFILE_NAME=${AWS_PROFILE_NAME:-$PREFIX}

# The prefix lands in S3 bucket and IAM names, so it must be valid in both.
[[ $PREFIX =~ ^[a-z][a-z0-9-]{0,19}$ && $PREFIX != *- ]] || die "--prefix: 1-20 chars, lowercase letters, digits, hyphens"
[[ $ACCOUNT_ID =~ ^[0-9]{12}$ ]] || die "--account-id: 12 digits"
[[ $REGION =~ ^[a-z]{2}(-[a-z]+)+-[0-9]$ ]] || die "--region: e.g. eu-west-1"
[[ $GITHUB_ORG =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die "--github-org: GitHub owner name"
[[ $GITHUB_REPO =~ ^[A-Za-z0-9._-]+$ ]] || die "--github-repo: GitHub repository name"
[[ $AWS_PROFILE_NAME =~ ^[A-Za-z0-9._-]+$ ]] || die "--aws-profile: profile name"

if [[ -e $DEST ]]; then
    [[ -d $DEST && -z $(ls -A "$DEST") ]] || die "$DEST exists and is not an empty directory"
fi

mkdir -p "$DEST"
cp -R "$TEMPLATE/." "$DEST/"

# Every value above is validated to contain no sed metacharacters except '-', '.'.
while IFS= read -r -d '' f; do
    sed -i.bak \
        -e "s/__PREFIX__/$PREFIX/g" \
        -e "s/__ACCOUNT_ID__/$ACCOUNT_ID/g" \
        -e "s/__REGION__/$REGION/g" \
        -e "s/__GITHUB_ORG__/$GITHUB_ORG/g" \
        -e "s/__GITHUB_REPO__/$GITHUB_REPO/g" \
        -e "s/__AWS_PROFILE__/$AWS_PROFILE_NAME/g" \
        "$f"
    rm -f "$f.bak"
done < <(find "$DEST" -type f -print0)

if left=$(grep -rnoE '__[A-Z_]+__' "$DEST"); then
    die "unreplaced tokens:"$'\n'"$left"
fi

chmod +x "$DEST/scripts/aws-inventory.sh"

cat <<EOF
Scaffolded $DEST ($PREFIX, $ACCOUNT_ID, $REGION, $GITHUB_ORG/$GITHUB_REPO).

Next:
  cd $DEST && git init
  terraform fmt -check -recursive && just check
  export AWS_PROFILE=$AWS_PROFILE_NAME && just bootstrap
EOF
