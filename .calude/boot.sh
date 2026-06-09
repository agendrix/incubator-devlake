#!/bin/bash
# boot.sh — runs after every snapshot restore in /invoke.
# Boots services, reconciles drift via the `changed` helper, then runs
# long-lived (typically `bin/dev &` + `wait`).
# Edit this file, then commit and push to keep changes.
# See also: .calude/snapshot.sh (runs once when the snapshot is built).
set -euo pipefail

cd /home/agent/workspace
export PATH="$HOME/.local/bin:$PATH"
export CGO_ENABLED=1 PKG_CONFIG_PATH=/usr/local/lib/pkgconfig LD_LIBRARY_PATH=/usr/local/lib

sudo ldconfig

start-postgres
psql -U postgres -h localhost -tc "SELECT 1 FROM pg_database WHERE datname='lake'" | grep -q 1 || psql -U postgres -h localhost -c "CREATE DATABASE lake"

changed backend/go.sum backend/go.mod && ( cd backend && go mod download )

changed backend/python/poetry.lock backend/python/pyproject.toml backend/python/requirements.txt && ( cd backend/python && { [ -f pyproject.toml ] && poetry install || pip install -r requirements.txt; } )

changed config-ui/yarn.lock config-ui/package.json && ( cd config-ui && corepack enable 2>/dev/null; yarn install )

( cd backend && make dev ) &
( cd config-ui && yarn start ) &

wait