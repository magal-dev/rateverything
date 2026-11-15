# Ambiente de desenvolvimento do Rateverything para GitHub Codespaces.
# Mesmas versões usadas localmente: GHC 9.10.3 + cabal 3.16.1.0 (via ghcup).
FROM mcr.microsoft.com/devcontainers/base:bookworm

# Dependências de sistema do GHC, libpq-dev (driver do PostgreSQL), psql e
# sqlite3 (só para importar dados da versão SQLite).
RUN apt-get update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends \
        build-essential curl libffi-dev libgmp-dev libgmp10 libncurses-dev \
        libtinfo-dev pkg-config zlib1g-dev libpq-dev postgresql-client sqlite3 python3 \
    && rm -rf /var/lib/apt/lists/*

USER vscode
ENV BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
    BOOTSTRAP_HASKELL_GHC_VERSION=9.10.3 \
    BOOTSTRAP_HASKELL_CABAL_VERSION=3.16.1.0 \
    BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1 \
    BOOTSTRAP_HASKELL_ADJUST_BASHRC=1
RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh

ENV PATH="/home/vscode/.ghcup/bin:/home/vscode/.cabal/bin:${PATH}"
