#!/usr/bin/env bash
#
# Keep secrets as files in a local, git-ignored secrets/ folder and sync them
# with AWS on demand, one environment at a time.
#
#   secrets.sh status <env>            what differs between secrets/ and AWS (key names only)
#   secrets.sh pull <env> [name...]    AWS -> secrets/; asks before overwriting a local change
#   secrets.sh push <env> [name...]    secrets/ -> AWS as new versions; asks first
#   secrets.sh history <name>          versions, never values
#   secrets.sh scaffold <env> <from>   new <env> files with <from>'s key names, values empty
#   secrets.sh new <env> <service> [example]
#                                      new /<project>/<env>/<service>/env from the service's
#                                      .env.example key names, values empty
#
#   secrets/ssm/<project>/<env>/<path>             <->  SSM SecureString /<project>/<env>/<path>
#   secrets/secretsmanager/<project>/<env>/<name>  <->  Secrets Manager secret <project>/<env>/<name>
#
# A name ending in / (or naming a folder) means every secret under that prefix:
# `push dev /<project>/dev/api` pushes all of dev's api secrets.
# A command touches only its environment's names, and only with credentials for
# that environment's account (ACCOUNTS below). No names: pull takes every secret
# of the environment, push every local file of it. secrets/.versions records the
# AWS version each file last synced with, so a push refuses to overwrite a change
# someone else made in AWS since.

set -euo pipefail
umask 077

# Name prefix of every secret: /<PROJECT>/<env>/... in SSM, <PROJECT>/<env>/... in Secrets Manager.
PROJECT=__PROJECT__
# Environment -> the AWS account it lives in. Anything missing here is refused.
# Environments may share one account: names and the typed prod confirmation keep them apart.
declare -A ACCOUNTS=(
    [dev]=__DEV_ACCOUNT_ID__
    [prod]=__PROD_ACCOUNT_ID__
)
# Secrets a deploy already loads; any other secret is stored but no app reads it yet.
# Example: [/acme/dev/api/env]="acme_api scripts/deploy.sh, on the next push to develop"
declare -A LOADED_BY=()
REGION=${AWS_REGION:-__REGION__}
DIR=${SECRETS_DIR:-secrets}
INDEX=$DIR/.versions
ENV=""
RC=0
export AWS_PAGER=""

die() {
    echo "secrets: $*" >&2
    exit 1
}

aws_() { aws --region "$REGION" "$@"; }

is_ssm() { [[ $1 == /* ]]; }

short() { echo "${1:0:8}"; }

ssm_prefix() { echo "/$PROJECT/$ENV/"; }
sm_prefix() { echo "$PROJECT/$ENV/"; }
in_env() { [[ $1 == "$(ssm_prefix)"* || $1 == "$(sm_prefix)"* ]]; }

# /<project>/<env>/... or <project>/<env>/... -> <env>
env_of() {
    local n=${1#/}
    [[ $n == "$PROJECT"/*/?* ]] || return 0
    n=${n#"$PROJECT"/}
    echo "${n%%/*}"
}

check_names() {
    local n
    for n in "$@"; do
        in_env "$n" || die "$n is not a $ENV secret: names start with $(ssm_prefix) or $(sm_prefix)"
        [[ $n =~ ^[A-Za-z0-9_.@+=/-]+$ && $n != *//* ]] || die "$n is not a valid secret name"
    done
}

# Exact names pass through; a prefix (trailing /, or a folder) becomes every
# known name under it: local files for push, AWS secrets for pull.
expand_names() {
    local mode=$1 n m p hit
    shift
    local -a known
    if [[ $mode == push ]]; then mapfile -t known < <(local_names); else mapfile -t known < <(remote_names); fi
    for n in "$@"; do
        p=${n%/}/
        hit=0
        for m in "${known[@]}"; do
            if [[ $m == "$n" || $m == "$p"* ]]; then
                echo "$m"
                hit=1
            fi
        done
        if [[ $hit == 0 && $n != */ ]]; then echo "$n"; fi
    done | awk '!seen[$0]++'
}

path_of() {
    if is_ssm "$1"; then echo "$DIR/ssm$1"; else echo "$DIR/secretsmanager/$1"; fi
}

name_of() {
    local rel=${1#"$DIR"/}
    case $rel in
    ssm/*) echo "/${rel#ssm/}" ;;
    secretsmanager/*) echo "${rel#secretsmanager/}" ;;
    esac
}

local_names() {
    # Skip dotfiles and editor backups (vim swap, foo~).
    find "$DIR/ssm$(ssm_prefix)" "$DIR/secretsmanager/$(sm_prefix)" -type f ! -name '.*' ! -name '*~' 2>/dev/null |
        while read -r f; do name_of "$f"; done | sort
}

# --- AWS --------------------------------------------------------------------

set_env() {
    ENV=$1
    [[ $ENV =~ ^[a-z0-9-]+$ ]] || die "environment must look like dev or prod"
    [[ -n ${ACCOUNTS[$ENV]:-} ]] || die "$ENV is not set up: add its AWS account to ACCOUNTS in scripts/secrets.sh"
}

use_env() {
    set_env "$1"
    local acct
    acct=$(aws sts get-caller-identity --query Account --output text) || die "no AWS credentials; export AWS_PROFILE first"
    [[ $acct == "${ACCOUNTS[$ENV]}" ]] || die "AWS_PROFILE points at account $acct, but $ENV lives in ${ACCOUNTS[$ENV]}"
}

# This environment's secrets; service-owned ones (RDS master passwords) are left out.
remote_names() {
    {
        aws_ ssm describe-parameters --parameter-filters Key=Type,Values=SecureString \
            "Key=Name,Option=BeginsWith,Values=$(ssm_prefix)" --query 'Parameters[].Name' --output text
        aws_ secretsmanager list-secrets --filters "Key=name,Values=$(sm_prefix)" \
            --query 'SecretList[?OwningService==null].Name' --output text
    } | tr '\t' '\n' | grep -vxE 'None|' || true
}

# Current AWS version; empty when the secret does not exist.
remote_version() {
    if is_ssm "$1"; then
        aws_ ssm describe-parameters --parameter-filters "Key=Name,Values=$1" \
            --query 'Parameters[0].Version' --output text | grep -vx None || true
    else
        aws_ secretsmanager describe-secret --secret-id "$1" --output json 2>/dev/null |
            jq -r '.VersionIdsToStages // {} | to_entries[] | select(.value | index("AWSCURRENT")) | .key' || true
    fi
}

# The service that rotates this secret; empty when nobody does.
owner() {
    is_ssm "$1" && return 0
    aws_ secretsmanager describe-secret --secret-id "$1" --query OwningService --output text 2>/dev/null |
        grep -vx None || true
}

# Writes the value to $2 byte for byte (no trailing newline added).
read_value() {
    if is_ssm "$1"; then
        aws_ ssm get-parameter --name "$1" --with-decryption --output json |
            jq -j '.Parameter.Value' >"$2"
    else
        aws_ secretsmanager get-secret-value --secret-id "$1" --output json |
            jq -j 'if .SecretString then .SecretString else error("binary secrets are not supported") end' >"$2"
    fi
}

# Uploads $2 via file:// so the value never appears in argv; prints the new version.
write_value() {
    local name=$1 file=$2 exists=$3
    if is_ssm "$name"; then
        if [[ -n $exists ]]; then
            local tier key
            read -r tier key < <(aws_ ssm describe-parameters --parameter-filters "Key=Name,Values=$name" \
                --query 'Parameters[0].[Tier,KeyId]' --output text)
            aws_ ssm put-parameter --name "$name" --type SecureString --tier "$tier" --key-id "$key" \
                --overwrite --value "file://$file" --query Version --output text
        else
            aws_ ssm put-parameter --name "$name" --type SecureString --tier Intelligent-Tiering \
                --value "file://$file" --query Version --output text
        fi
    else
        if [[ -n $exists ]]; then
            aws_ secretsmanager put-secret-value --secret-id "$name" --secret-string "file://$file" \
                --query VersionId --output text
        else
            aws_ secretsmanager create-secret --name "$name" --secret-string "file://$file" \
                --query VersionId --output text
        fi
    fi
}

# --- local state ------------------------------------------------------------

init_dir() {
    mkdir -p "$DIR"
    # Second guard next to the root .gitignore.
    [[ -f $DIR/.gitignore ]] || echo '*' >"$DIR/.gitignore"
}

synced_version() {
    [[ -f $INDEX ]] && awk -F'\t' -v n="$1" '$1 == n { print $2 }' "$INDEX" || true
}

record_version() {
    {
        [[ -f $INDEX ]] && awk -F'\t' -v n="$1" '$1 != n' "$INDEX"
        printf '%s\t%s\n' "$1" "$2"
    } >"$INDEX.tmp"
    mv "$INDEX.tmp" "$INDEX"
}

# AWS values are compared in a private scratch dir, on tmpfs where the OS has one.
make_workdir() {
    [[ -z ${WORK:-} ]] || return 0
    WORK=$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/secrets.XXXXXX")
    trap 'shred -u "$WORK"/* 2>/dev/null || rm -f "$WORK"/*; rmdir "$WORK"' EXIT
}

# --- comparing --------------------------------------------------------------

same() { [[ $(<"$1") == "$(<"$2")" ]]; } # ignores trailing newlines

# Key names added (+), removed (-) or changed (~) going from $1 to $2; never values.
summarize() {
    local from=$1 to=$2
    if jq -e 'type == "object"' "$to" >/dev/null 2>&1 && jq -e 'type == "object"' "$from" >/dev/null 2>&1; then
        jq -rn --slurpfile a "$from" --slurpfile b "$to" '$a[0] as $o | $b[0] as $n
          | ($n | keys[] as $k | select($o | has($k) | not) | "    + " + $k),
            ($o | keys[] as $k | select($n | has($k) | not) | "    - " + $k),
            ($n | keys[] as $k | select(($o | has($k)) and $o[$k] != $n[$k]) | "    ~ " + $k)'
    elif grep -qE '^[A-Za-z_][A-Za-z0-9_]*=' "$to" "$from" 2>/dev/null; then
        awk -F= 'FILENAME == ARGV[1] { if ($1 ~ /^[A-Za-z_][A-Za-z0-9_]*$/) old[$1] = substr($0, length($1) + 2); next }
                 $1 ~ /^[A-Za-z_][A-Za-z0-9_]*$/ { k = $1; seen[k] = 1; v = substr($0, length(k) + 2)
                   if (!(k in old)) print "    + " k; else if (old[k] != v) print "    ~ " k }
                 END { for (k in old) if (!(k in seen)) print "    - " k }' "$from" "$to"
    else
        echo "    content changed ($(wc -c <"$from" | tr -d ' ') -> $(wc -c <"$to" | tr -d ' ') bytes)"
    fi
}

# Prod needs its name typed, so a reflexive "y" can't change it.
# Keys with no value: KEY= lines, or "" in a JSON object.
empty_keys() {
    if jq -e 'type == "object"' "$1" >/dev/null 2>&1; then
        jq -r 'to_entries[] | select(.value == "") | .key' "$1"
    else
        grep -oE '^[A-Za-z_][A-Za-z0-9_]*=$' "$1" | tr -d '=' || true
    fi
}

confirm() {
    local answer
    { exec 3</dev/tty; } 2>/dev/null || die "needs a terminal to confirm"
    if [[ $ENV == prod ]]; then
        read -r -p "$1 Type prod to confirm: " answer <&3
    else
        read -r -p "$1 [y/N] " answer <&3
    fi
    exec 3<&-
    [[ $ENV == prod && $answer == prod ]] || [[ $ENV != prod && $answer == [yY] ]]
}

# Keep AWS's lack of a final newline; editors add one.
match_final_newline() {
    if [[ -s $1 && -n $(tail -c1 "$1") ]]; then
        printf '%s' "$(<"$2")" >"$2.trim" && mv "$2.trim" "$2"
    fi
}

# --- commands ---------------------------------------------------------------

pull_one() {
    local name=$1 file ver own remote=$WORK/remote
    file=$(path_of "$name")
    own=$(owner "$name")
    if [[ -n $own ]]; then
        echo "skip    $name (rotated by $own)"
        return 0
    fi
    ver=$(remote_version "$name")
    if [[ -z $ver ]]; then
        echo "skip    $name (not in AWS)"
        RC=1
        return 0
    fi
    read_value "$name" "$remote"
    if [[ -f $file ]]; then
        if same "$file" "$remote"; then
            record_version "$name" "$ver"
            echo "same    $name"
            return 0
        fi
        echo "$name: your local file differs from AWS version $(short "$ver"); pulling changes:"
        summarize "$file" "$remote"
        if ! confirm "Overwrite $file?"; then
            echo "kept    $name"
            return 0
        fi
    fi
    mkdir -p "$(dirname "$file")"
    cp "$remote" "$file"
    record_version "$name" "$ver"
    echo "pulled  $name -> $file"
}

push_one() {
    local name=$1 file ver synced own remote=$WORK/remote upload=$WORK/upload
    file=$(path_of "$name")
    if [[ ! -f $file || ! -s $file ]]; then
        echo "skip    $name (no file, or empty: $file)"
        RC=1
        return 0
    fi
    own=$(owner "$name")
    if [[ -n $own ]]; then
        echo "skip    $name (rotated by $own; change it there)"
        RC=1
        return 0
    fi
    ver=$(remote_version "$name")
    if [[ -n $ver ]]; then
        read_value "$name" "$remote"
        if same "$file" "$remote"; then
            record_version "$name" "$ver"
            echo "same    $name"
            return 0
        fi
        synced=$(synced_version "$name")
        if [[ $synced != "$ver" ]]; then
            echo "CONFLICT $name: AWS is at version $(short "$ver") but you last synced ${synced:+version }$(short "${synced:-never}")."
            echo "         Pull it, redo your edit, then push."
            RC=1
            return 0
        fi
        echo "$name: changes against AWS version $(short "$ver"):"
    else
        : >"$remote"
        echo "$name: new secret, keys:"
    fi
    summarize "$remote" "$file"
    local empty
    empty=$(empty_keys "$file" | paste -sd, -)
    [[ -z $empty ]] || echo "    ! empty values: $empty"
    if ! confirm "Push to AWS?"; then
        echo "kept    $name"
        return 0
    fi
    cp "$file" "$upload"
    match_final_newline "$remote" "$upload"
    ver=$(write_value "$name" "$upload" "$ver")
    record_version "$name" "$ver"
    echo "pushed  $name (version $(short "$ver"))"
    echo "        loaded by: ${LOADED_BY[$name]:-no deploy yet; wire one before relying on it}"
}

status_one() {
    local name=$1 file ver synced own remote=$WORK/remote
    file=$(path_of "$name")
    own=$(owner "$name")
    if [[ -n $own ]]; then
        echo "rotated by $own   $name"
        return 0
    fi
    ver=$(remote_version "$name")
    if [[ -z $ver ]]; then
        echo "local only     $name (push creates it)"
        return 0
    fi
    if [[ ! -f $file ]]; then
        echo "not pulled     $name"
        return 0
    fi
    read_value "$name" "$remote"
    if same "$file" "$remote"; then
        echo "in sync        $name"
        return 0
    fi
    synced=$(synced_version "$name")
    if [[ $synced == "$ver" ]]; then
        echo "local change   $name"
    else
        echo "AWS changed    $name (since your last sync; pull before pushing)"
    fi
    summarize "$remote" "$file"
}

cmd_pull() {
    local -a names=("$@")
    check_names "$@"
    if ((${#names[@]})); then mapfile -t names < <(expand_names pull "$@"); else mapfile -t names < <(remote_names); fi
    ((${#names[@]})) || {
        echo "No $ENV secrets in AWS${*:+ matching $*}."
        return 0
    }
    init_dir
    make_workdir
    local name
    for name in "${names[@]}"; do pull_one "$name"; done
}

cmd_push() {
    local -a names=("$@")
    check_names "$@"
    if ((${#names[@]})); then mapfile -t names < <(expand_names push "$@"); else mapfile -t names < <(local_names); fi
    ((${#names[@]})) || {
        echo "No $ENV files${*:+ matching $*} under $DIR/ssm$(ssm_prefix) or $DIR/secretsmanager/$(sm_prefix)."
        return 0
    }
    make_workdir
    local name
    for name in "${names[@]}"; do push_one "$name"; done
}

cmd_status() {
    local -a names
    mapfile -t names < <({
        remote_names
        local_names
    } | sort -u)
    ((${#names[@]})) || {
        echo "No $ENV secrets in AWS or $DIR/."
        return 0
    }
    make_workdir
    local name
    for name in "${names[@]}"; do status_one "$name"; done
}

# New files for $ENV carrying $1's key names with empty values; never copies a value.
cmd_scaffold() {
    local from=$1 name target src dst
    local -a names
    mapfile -t names < <(ENV=$from local_names)
    ((${#names[@]})) || die "no $from files under $DIR/; run: just secrets-pull $from"
    for name in "${names[@]}"; do
        if [[ $name == /* ]]; then target="/$PROJECT/$ENV/${name#"/$PROJECT/$from/"}"; else target="$PROJECT/$ENV/${name#"$PROJECT/$from/"}"; fi
        src=$(path_of "$name")
        dst=$(path_of "$target")
        if [[ -e $dst ]]; then
            echo "exists  $dst (left as is)"
            continue
        fi
        mkdir -p "$(dirname "$dst")"
        if jq -e 'type == "object"' "$src" >/dev/null 2>&1; then
            jq 'map_values("")' "$src" >"$dst"
        elif grep -qE '^[A-Za-z_][A-Za-z0-9_]*=' "$src"; then
            # Comments are dropped: they often hold old values.
            grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$src" >"$dst"
        else
            echo "skip    $name (neither KEY=value lines nor a JSON object)"
            continue
        fi
        echo "created $dst ($(empty_keys "$dst" | wc -l | tr -d ' ') keys, all empty)"
    done
    echo "Fill in the values, then: just secrets-push $ENV"
}

# First secret of a service: key names from its .env.example, values empty.
# Default example: the sibling repo <PROJECT>_<service>/.env.example next to this repo.
cmd_new() {
    local service=$1 example=${2:-} name dst
    [[ $service =~ ^[a-z0-9-]+$ ]] || die "service must look like api or worker"
    example=${example:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/${PROJECT}_$service/.env.example}
    name="$(ssm_prefix)$service/env"
    dst=$(path_of "$name")
    [[ ! -e $dst ]] || die "$dst already exists"
    [[ -z $(remote_version "$name") ]] || die "$name already exists in AWS; run: just secrets-pull $ENV $name"
    [[ -f $example ]] || die "no $example; create $dst by hand with KEY=value lines, then push"
    mkdir -p "$(dirname "$dst")"
    # Keys only: example values are placeholders that must not reach AWS by accident.
    grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$example" >"$dst" || die "$example has no KEY=value lines"
    echo "created $dst ($(wc -l <"$dst" | tr -d ' ') keys from $example, all empty)"
    echo "Fill in the values, then: just secrets-push $ENV $name"
}

cmd_history() {
    if is_ssm "$1"; then
        aws_ ssm get-parameter-history --name "$1" \
            --query 'Parameters[].[Version,LastModifiedDate,LastModifiedUser]' --output text | column -t
    else
        aws_ secretsmanager list-secret-version-ids --secret-id "$1" \
            --query 'Versions[].[VersionId,CreatedDate,join(`","`, VersionStages || `[]`)]' --output text | column -t
    fi
}

main() {
    local bin cmd=${1:-}
    [[ "$PROJECT ${ACCOUNTS[*]} $REGION" != *__*__* ]] || die "fill in the placeholders at the top of $0 (PROJECT, ACCOUNTS, REGION)"
    for bin in aws jq; do command -v "$bin" >/dev/null || die "$bin is required"; done
    shift || true
    case $cmd in
    status)
        [[ $# -eq 1 ]] || die "usage: secrets.sh status <env>"
        use_env "$1"
        cmd_status
        ;;
    pull | push)
        [[ $# -ge 1 ]] || die "usage: secrets.sh $cmd <env> [name...]"
        use_env "$1"
        shift
        "cmd_$cmd" "$@"
        ;;
    new)
        [[ $# -ge 2 && $# -le 3 ]] || die "usage: secrets.sh new <env> <service> [example-file]"
        use_env "$1"
        cmd_new "$2" "${3:-}"
        ;;
    scaffold)
        [[ $# -eq 2 && $1 != "$2" ]] || die "usage: secrets.sh scaffold <env> <from-env>"
        set_env "$2"
        set_env "$1"
        cmd_scaffold "$2"
        ;;
    history)
        [[ $# -eq 1 && -n $1 ]] || die "usage: secrets.sh history <name>"
        [[ -n $(env_of "$1") ]] || die "$1 is not under /$PROJECT/<env>/ or $PROJECT/<env>/"
        use_env "$(env_of "$1")"
        cmd_history "$1"
        ;;
    *) die "usage: secrets.sh status <env> | pull <env> [name...] | push <env> [name...] | history <name> | scaffold <env> <from-env> | new <env> <service>" ;;
    esac
    exit "$RC"
}

# Sourcing (for tests) loads the functions without running anything.
[[ ${BASH_SOURCE[0]} != "$0" ]] || main "$@"
