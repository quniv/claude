# The Dev environment .env lives in SSM Parameter Store. These recipes only know
# the dev parameter: prod is managed from the admin repo by the secrets owner.
# Needs the AWS CLI with credentials allowed on this parameter. Run `just` to list.

param  := "/__PROJECT__/dev/__SERVICE__/env"
file   := ".env.dev"
region := "__REGION__"

# SSM -> .env.dev (git-ignored, mode 600); remembers the AWS version you pulled
env-pull:
    #!/usr/bin/env bash
    set -euo pipefail
    umask 077
    aws ssm get-parameter --name {{ param }} --region {{ region }} --with-decryption \
      --query Parameter.Value --output text > {{ file }}
    aws ssm get-parameter --name {{ param }} --region {{ region }} \
      --query Parameter.Version --output text > {{ file }}.version
    echo "{{ file }}: $(wc -l < {{ file }}) lines, AWS version $(cat {{ file }}.version)"

# Key names that differ between .env.dev and AWS (+ added, - removed, ~ changed); values never shown
env-diff:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f {{ file }} ] || { echo "{{ file }} is missing: run 'just env-pull' first" >&2; exit 1; }
    remote=$(mktemp)
    trap 'rm -f "$remote"' EXIT
    aws ssm get-parameter --name {{ param }} --region {{ region }} --with-decryption \
      --query Parameter.Value --output text > "$remote"
    keys() { grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$1" | tr -d = | sort -u; }
    comm -23 <(keys {{ file }}) <(keys "$remote") | sed 's/^/+ /'
    comm -13 <(keys {{ file }}) <(keys "$remote") | sed 's/^/- /'
    for k in $(comm -12 <(keys {{ file }}) <(keys "$remote")); do
      [ "$(grep -m1 "^$k=" {{ file }})" = "$(grep -m1 "^$k=" "$remote")" ] || echo "~ $k"
    done

# .env.dev -> SSM after showing the diff and asking; refused if AWS changed since your pull
env-push:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f {{ file }} ] || { echo "{{ file }} is missing: run 'just env-pull' first" >&2; exit 1; }
    remote=$(aws ssm get-parameter --name {{ param }} --region {{ region }} --query Parameter.Version --output text)
    pulled=$(cat {{ file }}.version 2>/dev/null || echo none)
    if [ "$remote" != "$pulled" ]; then
      echo "AWS is at version $remote, you pulled $pulled: someone changed it. Run 'just env-pull', redo your edit, push again." >&2
      exit 1
    fi
    echo "Changes vs AWS version $remote:"
    just env-diff
    read -rp "Push {{ file }} to {{ param }}? [y/N] " ok
    [ "$ok" = y ] || exit 1
    # file:// keeps the value out of argv; $(cat) drops trailing newlines so it does not grow per round trip.
    upload=$(mktemp)
    trap 'rm -f "$upload"' EXIT
    printf '%s' "$(cat {{ file }})" > "$upload"
    aws ssm put-parameter --name {{ param }} --region {{ region }} --type SecureString \
      --value "file://$upload" --overwrite --query Version --output text > {{ file }}.version
    echo "Pushed: now version $(cat {{ file }}.version)."
    echo "Apply it: just restart, or wait for the next dev deploy."

# Versions of the dev parameter in AWS; never values
env-versions:
    aws ssm get-parameter-history --name {{ param }} --region {{ region }} \
      --query 'Parameters[].[Version, LastModifiedDate, LastModifiedUser]' --output table
