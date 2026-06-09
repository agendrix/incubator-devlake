#!/bin/bash
# snapshot.sh — runs once during /warm to build the snapshot baseline.
# Output of this script is what gets baked into the persisted snapshot.
# Edit this file, then commit and push to keep changes.
# See also: .calude/boot.sh (runs after every snapshot restore).
set -euo pipefail

cat > .calude/mise.toml <<'EOF'
[tools]
go = "1.20.5"
python = "3.9"
EOF

calude-mise-sync || true

sudo apt-get update
sudo apt-get install -y libssh2-1-dev libssl-dev zlib1g-dev cmake pkg-config default-libmysqlclient-dev

# Build libgit2 1.3.2 (required by backend CGO bindings)
if [ ! -f /usr/local/lib/libgit2.so ]; then
  tmp=$(mktemp -d)
  cd "$tmp"
  wget -qO- https://github.com/libgit2/libgit2/archive/refs/tags/v1.3.2.tar.gz | tar -xz
  cd libgit2-1.3.2
  mkdir build && cd build
  cmake .. -DBUILD_SHARED_LIBS=ON -DCMAKE_INSTALL_PREFIX=/usr/local
  make -j"$(nproc)"
  sudo make install
  sudo ldconfig
  cd /home/agent/workspace
  rm -rf "$tmp"
fi

cd /home/agent/workspace

# Go backend deps
changed backend/go.sum backend/go.mod && ( cd backend && export CGO_ENABLED=1 PKG_CONFIG_PATH=/usr/local/lib/pkgconfig && go mod download )

# Python plugins via Poetry
if ! command -v poetry >/dev/null 2>&1; then
  curl -sSL https://install.python-poetry.org | python3 -
fi
export PATH="$HOME/.local/bin:$PATH"
changed backend/python/poetry.lock backend/python/pyproject.toml backend/python/requirements.txt && ( cd backend/python && [ -f pyproject.toml ] && poetry install || pip install -r requirements.txt )

# config-ui (yarn berry via .yarnrc.yml)
changed config-ui/yarn.lock config-ui/package.json && ( cd config-ui && corepack enable 2>/dev/null; yarn install )

start-postgres
psql -U postgres -h localhost -tc "SELECT 1 FROM pg_database WHERE datname='lake'" | grep -q 1 || psql -U postgres -h localhost -c "CREATE DATABASE lake"