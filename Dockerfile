ARG OPENCLAW_VERSION=latest
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}

USER root

# Extra tools (procps, curl, git, openssl already in base image)
RUN apt-get update && apt-get install -y \
    cron \
    jq \
    gnupg \
    build-essential \
    python3 \
    python3-pip \
    python-is-python3 \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    sqlite3 \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# xurl CLI (X/Twitter API v2) — pinned version with SHA256 verification
ARG XURL_VERSION=1.0.3
ARG XURL_SHA256_AMD64=34bc67bfbaf29ae121f7788fbd2491d3a8b95cb3947333ad39732e694497c182
ARG XURL_SHA256_ARM64=3b56605e66508d7bc77c36cc711d41307b4cd76aec09111890b33f9d82975483
RUN ARCH=$(dpkg --print-architecture) \
    && case "$ARCH" in \
         amd64) XURL_ARCH="x86_64"; XURL_SHA256="${XURL_SHA256_AMD64}" ;; \
         arm64) XURL_ARCH="arm64";  XURL_SHA256="${XURL_SHA256_ARM64}" ;; \
         *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/xdevplatform/xurl/releases/download/v${XURL_VERSION}/xurl_Linux_${XURL_ARCH}.tar.gz" \
         -o /tmp/xurl.tar.gz \
    && echo "${XURL_SHA256}  /tmp/xurl.tar.gz" | sha256sum -c - \
    && tar -xz -C /usr/local/bin -f /tmp/xurl.tar.gz xurl \
    && chmod +x /usr/local/bin/xurl \
    && rm /tmp/xurl.tar.gz

# Google Workspace CLI — pinned version
RUN npm install -g @googleworkspace/cli@0.22.1

# Agent templates (read-only source for entrypoint to copy into workspace)
COPY --chown=node:node agents/ /opt/openclaw-agents/

# Entrypoint and init scripts
COPY --chown=node:node docker-entrypoint.sh /usr/local/bin/
COPY --chown=node:node init.d/ /usr/local/lib/openclaw-init.d/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/lib/openclaw-init.d/*.sh

# Ensure home is owned by node + compile cache for low-power hosts
RUN mkdir -p /var/tmp/openclaw-compile-cache \
    && chown -R node:node /home/node /var/tmp/openclaw-compile-cache

ENV PATH="/home/node/.local/bin:${PATH}"

# Entrypoint runs as root to fix volume permissions, then drops to node
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured"]
