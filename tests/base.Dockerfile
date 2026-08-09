# Test base image: Ubuntu 24.04 x86_64 running as root, carrying only what the
# hosted base image already provides before environment.sh runs — a CA store,
# curl, git, jq and the Claude Code CLI. Nothing this repo's script is supposed
# to install is baked in here, so every case still observes a clean container.
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

ENTRYPOINT ["/bin/bash"]
