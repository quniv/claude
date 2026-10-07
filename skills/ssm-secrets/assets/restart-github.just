# Dev container reloads the SSM .env: runs the restart workflow on __DEV_BRANCH__ (no build, no migrations)
# Uses your `gh` login; it needs write access to the repo's Actions.
restart:
    gh workflow run restart.yml --ref __DEV_BRANCH__ -f environment=dev
    @echo "Started. Follow it with: gh run watch"
