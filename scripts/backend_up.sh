#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
backend_dir="$repo_root/Backend"
env_file="$backend_dir/.env.local"
example_file="$backend_dir/.env.local.example"
backend_bin="$backend_dir/.build/arm64-apple-macosx/debug/VibeWriteBackend"
backend_log="/tmp/vibewrite-backend.log"

if [[ ! -f "$env_file" ]]; then
  if [[ -f "$example_file" ]]; then
    cat >&2 <<EOF
Missing $env_file.
Copy $example_file to $env_file and fill in the local values first.
EOF
  else
    cat >&2 <<EOF
Missing $env_file and $example_file.
Create $env_file with the backend environment values first.
EOF
  fi
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

required_vars=(
  ADMIN_SECRET_ENCRYPTION_KEY
  ADMIN_USERNAME
  ADMIN_PASSWORD
)

for var_name in "${required_vars[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required backend env var: $var_name" >&2
    exit 1
  fi
done

persistence_mode="${VIBEWRITE_BACKEND_PERSISTENCE:-}"
if [[ "$persistence_mode" == "postgres" || "$persistence_mode" == "postgresql" ]]; then
  if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "Missing required backend env var: DATABASE_URL" >&2
    exit 1
  fi
fi

provider="${VIBEWRITE_AI_PROVIDER:-codex}"
if [[ "$provider" != "codex" && -z "${MINIMAX_API_KEY:-}" ]]; then
  echo "Missing required backend env var: MINIMAX_API_KEY" >&2
  exit 1
fi

cd "$backend_dir"
swift build

pkill -f "./.build/arm64-apple-macosx/debug/VibeWriteBackend serve --hostname 127.0.0.1 --port 8080" || true

backend_pid="$(python3 - <<'PY'
import os
import subprocess
root = os.getcwd()
binary = os.path.join(root, ".build/arm64-apple-macosx/debug/VibeWriteBackend")
log_path = "/tmp/vibewrite-backend.log"
with open(log_path, "ab", buffering=0) as log_handle, open("/dev/null", "rb") as devnull:
    process = subprocess.Popen(
        [binary, "serve", "--hostname", "127.0.0.1", "--port", "8080"],
        cwd=root,
        stdin=devnull,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        env=os.environ.copy(),
        start_new_session=True,
    )
print(process.pid)
PY
)"

for _ in {1..30}; do
  if curl -sf http://127.0.0.1:8080/v3/health >/dev/null; then
    echo "Backend ready on http://127.0.0.1:8080 (pid $backend_pid)"
    exit 0
  fi
  sleep 1
done

echo "Backend failed to become ready. See $backend_log" >&2
tail -n 40 "$backend_log" >&2 || true
exit 1
