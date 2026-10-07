# Secrets live in secrets/ (git-ignored), one environment per command:
# secrets/ssm/__PROJECT__/<env>/... is SSM /__PROJECT__/<env>/...,
# secrets/secretsmanager/__PROJECT__/<env>/... is Secrets Manager __PROJECT__/<env>/...

# What differs between secrets/ and AWS for one env  (just secrets-status dev)
secrets-status env:
    ./scripts/secrets.sh status {{ quote(env) }}

# AWS -> secrets/ for one env  (no names: all of that env's secrets)
[positional-arguments]
secrets-pull env *names:
    ./scripts/secrets.sh pull "$@"

# secrets/ -> AWS for one env, after confirming  (no names: all of that env's files)
[positional-arguments]
secrets-push env *names:
    ./scripts/secrets.sh push "$@"

# First secret of a service, keys from ../__PROJECT___<service>/.env.example  (just secrets-new dev api)
secrets-new env service:
    ./scripts/secrets.sh new {{ quote(env) }} {{ quote(service) }}

# New files for env with another env's key names, values empty  (just secrets-scaffold prod dev)
secrets-scaffold env from:
    ./scripts/secrets.sh scaffold {{ quote(env) }} {{ quote(from) }}

# Versions of a secret in AWS, never values
secret-history name:
    ./scripts/secrets.sh history {{ quote(name) }}
