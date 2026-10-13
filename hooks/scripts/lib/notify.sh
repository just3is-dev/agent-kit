#!/usr/bin/env bash
# Локальные уведомления: состояние (время начала хода) и отправка.

notify_state_dir() {
  printf '%s\n' "${TMPDIR:-/tmp}/agent-kit-notify"
}

# notify_ts_file <session_id> — файл с временем начала хода сессии.
notify_ts_file() {
  printf '%s\n' "$(notify_state_dir)/$1"
}

# notify_send <сообщение> — заголовок "Claude — <проект>", текст сообщения.
notify_send() {
  local msg="$1"
  local title="Claude — $(basename "${CLAUDE_PROJECT_DIR:-$PWD}")"
  "$(cd "$(dirname "$0")" && pwd)/notify-send.sh" "$title" "$msg"
}
