# Dev container reloads the SSM .env: runs the custom 'restart' pipeline on __DEV_BRANCH__ (no build, no migrations)
# Needs BITBUCKET_EMAIL and BITBUCKET_API_TOKEN (Atlassian API token, Bitbucket scope write:pipeline:bitbucket).
restart:
    #!/usr/bin/env bash
    set -euo pipefail
    repo="__BITBUCKET_REPO__"
    : "${BITBUCKET_EMAIL:?set it to your Atlassian account email}"
    : "${BITBUCKET_API_TOKEN:?create an Atlassian API token with the Bitbucket scope write:pipeline:bitbucket}"
    out=$(curl -sS --fail-with-body -u "$BITBUCKET_EMAIL:$BITBUCKET_API_TOKEN" -H 'Content-Type: application/json' \
      -X POST "https://api.bitbucket.org/2.0/repositories/$repo/pipelines/" \
      -d '{"target":{"type":"pipeline_ref_target","ref_type":"branch","ref_name":"__DEV_BRANCH__","selector":{"type":"custom","pattern":"restart"}}}') \
      || { echo "Bitbucket refused the request${out:+: $out}" >&2; exit 1; }
    build=$(sed -n 's/.*"build_number": *\([0-9]*\).*/\1/p' <<< "$out")
    echo "Restart pipeline #$build: https://bitbucket.org/$repo/pipelines/results/$build"
