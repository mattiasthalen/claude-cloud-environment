# Test base image: Ubuntu 24.04 x86_64 running as root, carrying only what the
# hosted base image already provides before environment.sh runs — a CA store,
# curl, git, jq, uv and the Claude Code CLI. Nothing this repo's script is
# supposed to install is baked in here, so every case still observes a clean
# container.
#
# The image is built once and reused; each case gets a fresh container from it.
FROM ubuntu:24.04

# Empty in the common case. A harness running behind a TLS-intercepting proxy
# drops that proxy's CA here so the container can reach vendor repositories.
COPY ca/ /usr/local/share/ca-certificates/

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git jq \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ENV PATH=/root/.local/bin:$PATH

RUN curl -fsSL https://claude.ai/install.sh | bash

# uv, which the hosted base image already carries and which environment.sh's
# non-apt phase installs snow with. The script does not bootstrap it, so a base
# without it would not be the base the script actually runs against.
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# The hosted base image exports SSL_CERT_FILE, and tools that ship their own
# trust store rather than reading the system one (uv among them) need it: behind
# a TLS-intercepting proxy the CA copied in above is in the system bundle and
# nowhere else. Without a proxy this names the ordinary system bundle.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

ENTRYPOINT ["/bin/bash"]
