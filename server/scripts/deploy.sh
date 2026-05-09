#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$SERVER_DIR/.." && pwd)"

DEPLOY_HOST="${DEPLOY_HOST:-39.104.67.175}"
DEPLOY_USER="${DEPLOY_USER:-root}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/doorsix/server}"
DEPLOY_PORT="${DEPLOY_PORT:-80}"
if [[ -z "${PUBLIC_BASE_URL:-}" ]]; then
  if [[ "$DEPLOY_PORT" == "80" ]]; then
    PUBLIC_BASE_URL="http://${DEPLOY_HOST}"
  else
    PUBLIC_BASE_URL="http://${DEPLOY_HOST}:${DEPLOY_PORT}"
  fi
fi
ROOM_TTL_SECONDS="${ROOM_TTL_SECONDS:-7200}"
APP_RELEASE_ROOT="${APP_RELEASE_ROOT:-/opt/doorsix/releases}"
PASSWORD_FILE="${DEPLOY_PASSWORD_FILE:-$REPO_DIR/.local/secrets/doorsix-root-password.txt}"
REMOTE_ARCHIVE="/tmp/doorsix-server.$$.tar.gz"
REMOTE_DEPLOY_SCRIPT="/tmp/doorsix-deploy.$$.sh"
ARCHIVE="$(mktemp -t doorsix-server.XXXXXX.tar.gz)"
REMOTE_SCRIPT_FILE="$(mktemp -t doorsix-remote-deploy.XXXXXX.sh)"
SSH_TARGET="${DEPLOY_USER}@${DEPLOY_HOST}"
SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o ServerAliveInterval=20
  -o ServerAliveCountMax=3
)

cleanup() {
  rm -f "$ARCHIVE" "$REMOTE_SCRIPT_FILE"
}
trap cleanup EXIT

password_available() {
  [[ -f "$PASSWORD_FILE" && -s "$PASSWORD_FILE" ]]
}

ssh_with_expect() {
  local remote_command="$1"

  DEPLOY_PASSWORD_FILE="$PASSWORD_FILE" \
  DEPLOY_TARGET="$SSH_TARGET" \
  DEPLOY_REMOTE_COMMAND="$remote_command" \
  expect <<'EXPECT'
set timeout -1
set fh [open $env(DEPLOY_PASSWORD_FILE) r]
set password [string trimright [read $fh] "\r\n"]
close $fh
set opts [list -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=20 -o ServerAliveCountMax=3]
spawn ssh {*}$opts $env(DEPLOY_TARGET) $env(DEPLOY_REMOTE_COMMAND)
expect {
  -re "(?i)password:" {
    send -- "$password\r"
    exp_continue
  }
  -re "(?i)are you sure you want to continue connecting" {
    send -- "yes\r"
    exp_continue
  }
  eof
}
catch wait result
exit [lindex $result 3]
EXPECT
}

scp_with_expect() {
  local local_path="$1"
  local remote_path="$2"

  DEPLOY_PASSWORD_FILE="$PASSWORD_FILE" \
  DEPLOY_TARGET="$SSH_TARGET" \
  DEPLOY_LOCAL_PATH="$local_path" \
  DEPLOY_REMOTE_PATH="$remote_path" \
  expect <<'EXPECT'
set timeout -1
set fh [open $env(DEPLOY_PASSWORD_FILE) r]
set password [string trimright [read $fh] "\r\n"]
close $fh
set opts [list -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=20 -o ServerAliveCountMax=3]
set remote "$env(DEPLOY_TARGET):$env(DEPLOY_REMOTE_PATH)"
spawn scp {*}$opts $env(DEPLOY_LOCAL_PATH) $remote
expect {
  -re "(?i)password:" {
    send -- "$password\r"
    exp_continue
  }
  -re "(?i)are you sure you want to continue connecting" {
    send -- "yes\r"
    exp_continue
  }
  eof
}
catch wait result
exit [lindex $result 3]
EXPECT
}

remote_ssh() {
  local remote_command="$1"

  if password_available && command -v sshpass >/dev/null 2>&1; then
    sshpass -f "$PASSWORD_FILE" ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$remote_command"
  elif password_available && command -v expect >/dev/null 2>&1; then
    ssh_with_expect "$remote_command"
  else
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$remote_command"
  fi
}

copy_to_remote() {
  local local_path="$1"
  local remote_path="$2"

  if password_available && command -v sshpass >/dev/null 2>&1; then
    sshpass -f "$PASSWORD_FILE" scp "${SSH_OPTS[@]}" "$local_path" "${SSH_TARGET}:${remote_path}"
  elif password_available && command -v expect >/dev/null 2>&1; then
    scp_with_expect "$local_path" "$remote_path"
  else
    scp "${SSH_OPTS[@]}" "$local_path" "${SSH_TARGET}:${remote_path}"
  fi
}

remote_script=$(cat <<'REMOTE_SCRIPT'
set -euo pipefail

install_runtime() {
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y nodejs npm redis curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y nodejs npm redis curl
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ca-certificates curl nodejs npm redis-server
  else
    echo "No supported package manager found for installing Node.js and Redis." >&2
    exit 1
  fi
}

start_redis() {
  if ! command -v systemctl >/dev/null 2>&1; then
    redis-server --daemonize yes || true
    return
  fi

  if systemctl list-unit-files redis.service >/dev/null 2>&1; then
    systemctl enable --now redis
  elif systemctl list-unit-files redis-server.service >/dev/null 2>&1; then
    systemctl enable --now redis-server
  else
    redis-server --daemonize yes || true
  fi
}

node_bin() {
  command -v node || command -v nodejs
}

write_env_file() {
  mkdir -p /etc/doorsix /var/log/doorsix/matches "$APP_RELEASE_ROOT/android" "$APP_RELEASE_ROOT/manifests" "$APP_RELEASE_ROOT/.tmp"
  cat > /etc/doorsix/server.env <<ENV
NODE_ENV=production
HOST=0.0.0.0
PORT=${DEPLOY_PORT}
PUBLIC_BASE_URL=${PUBLIC_BASE_URL}
REDIS_URL=redis://127.0.0.1:6379
ROOM_TTL_SECONDS=${ROOM_TTL_SECONDS}
MATCH_LOG_DIR=/var/log/doorsix/matches
APP_UPDATE_MANIFEST_PATH=${APP_RELEASE_ROOT}/manifests/latest-android-stable.json
APP_UPDATE_MANIFEST_URL=
APP_RELEASE_ANDROID_DIR=${APP_RELEASE_ROOT}/android
APP_UPDATE_ENVIRONMENT=prod
APP_UPDATE_DEFAULT_CHANNEL=stable
APP_UPDATE_DOWNLOAD_BASE_URL=${PUBLIC_BASE_URL}/downloads/android
ENV
  chmod 0644 /etc/doorsix/server.env
}

write_service() {
  local node_path
  node_path="$(node_bin)"

  cat > /etc/systemd/system/doorsix-server.service <<UNIT
[Unit]
Description=DoorSix multiplayer backend
After=network-online.target redis.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${DEPLOY_DIR}
EnvironmentFile=/etc/doorsix/server.env
ExecStart=${node_path} src/index.js
Restart=always
RestartSec=3
User=doorsix
Group=doorsix
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT
}

install_dependencies_if_needed() {
  if [[ -d "$DEPLOY_DIR/node_modules" ]]; then
    return
  fi

  cd "$DEPLOY_DIR"
  npm ci --omit=dev
}

prepare_user() {
  if ! id doorsix >/dev/null 2>&1; then
    useradd --system --home-dir /opt/doorsix --shell /sbin/nologin doorsix
  fi
}

wait_for_health() {
  local url="http://127.0.0.1:${DEPLOY_PORT}/health"
  local attempt

  for attempt in $(seq 1 30); do
    if command -v curl >/dev/null 2>&1; then
      if curl -fsS "$url" >/dev/null 2>&1; then
        return 0
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -qO- "$url" >/dev/null 2>&1; then
        return 0
      fi
    fi
    sleep 2
  done

  echo "Health check failed: $url" >&2
  journalctl -u doorsix-server --no-pager -n 120 >&2 || true
  exit 1
}

install_runtime
start_redis
prepare_user

mkdir -p "$DEPLOY_DIR"
find "$DEPLOY_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
tar -xzf "$REMOTE_ARCHIVE" -C "$DEPLOY_DIR"
rm -f "$REMOTE_ARCHIVE"

install_dependencies_if_needed
write_env_file
write_service

chown -R doorsix:doorsix "$DEPLOY_DIR" /var/log/doorsix "$APP_RELEASE_ROOT"

systemctl daemon-reload
systemctl enable --now doorsix-server
systemctl restart doorsix-server

wait_for_health
systemctl --no-pager --full status doorsix-server
REMOTE_SCRIPT
)

echo "Packaging DoorSix server from $SERVER_DIR"
printf '%s\n' "$remote_script" > "$REMOTE_SCRIPT_FILE"

COPYFILE_DISABLE=1 tar --format ustar \
  --exclude logs \
  --exclude .env \
  --exclude .tmp-test-logs \
  --exclude '._*' \
  -czf "$ARCHIVE" \
  -C "$SERVER_DIR" .

echo "Preparing remote host $SSH_TARGET"
remote_ssh "mkdir -p /tmp"

echo "Uploading archive to $SSH_TARGET:$REMOTE_ARCHIVE"
copy_to_remote "$ARCHIVE" "$REMOTE_ARCHIVE"

echo "Uploading deploy runner to $SSH_TARGET:$REMOTE_DEPLOY_SCRIPT"
copy_to_remote "$REMOTE_SCRIPT_FILE" "$REMOTE_DEPLOY_SCRIPT"

echo "Installing runtime and starting service"
remote_env=$(printf 'DEPLOY_DIR=%q REMOTE_ARCHIVE=%q DEPLOY_PORT=%q PUBLIC_BASE_URL=%q ROOM_TTL_SECONDS=%q APP_RELEASE_ROOT=%q' \
  "$DEPLOY_DIR" "$REMOTE_ARCHIVE" "$DEPLOY_PORT" "$PUBLIC_BASE_URL" "$ROOM_TTL_SECONDS" "$APP_RELEASE_ROOT")
remote_script_path=$(printf '%q' "$REMOTE_DEPLOY_SCRIPT")
remote_ssh "$remote_env bash $remote_script_path; status=\$?; rm -f $remote_script_path; exit \$status"

echo "Checking public health endpoint"
if curl -fsS "${PUBLIC_BASE_URL}/health"; then
  echo
else
  echo "Warning: service is healthy on the remote host, but ${PUBLIC_BASE_URL}/health is not reachable from this machine." >&2
  echo "Check the cloud security group or external network path for port ${DEPLOY_PORT}." >&2
fi
echo "DoorSix server deployed to ${PUBLIC_BASE_URL}"
