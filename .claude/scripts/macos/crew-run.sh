#!/usr/bin/env bash
# Runs one agent of the crew (the governor's own team, see .claude/crew.md) as a GitHub Copilot CLI
# custom agent in the background and prints a compact summary. Several runs can be alive at once.
#   bash .claude/scripts/macos/crew-run.sh start  <crew-agent> <prompt-file> [--scope g1,g2] [--model m] [--allow-overlap]
#   bash .claude/scripts/macos/crew-run.sh wait   <RUN_ID>     (blocks up to WAIT_MINUTES; run it in the background)
#   bash .claude/scripts/macos/crew-run.sh status <RUN_ID>     (returns at once)
#   bash .claude/scripts/macos/crew-run.sh stop   <RUN_ID>
#   bash .claude/scripts/macos/crew-run.sh list
#   bash .claude/scripts/macos/crew-run.sh check  <crew-agent> [--scope g1,g2]    (dry run: what would be granted)
#
# Differences from run-agent.sh (which belongs to the shared pipeline and is left untouched):
#  - only agents named crew-* run, from .github/agents/crew-<name>.agent.md, with settings from
#    .claude/crew.env and standing rules from .github/copilot/crew-rules.md;
#  - the model is chosen per agent (CREW_MODEL_<agent>), and the runner sets the model ids itself, so a
#    stale COPILOT_MODEL in the shell profile cannot send a run to the wrong provider route;
#  - write access is a SCOPE: the agent's profile (.github/copilot/permissions/crew-<name>.flags) lists
#    the paths it may ever write (the ceiling); --scope narrows a run to part of that, and the runner
#    refuses a scope outside the ceiling. Two live runs may not have overlapping scopes (so parallel
#    runs cannot overwrite each other), and at most MAX_PARALLEL_WRITERS writers run at once;
#  - health, FILES_CHANGED and the no-write check look only at the run's own scope, so a parallel run's
#    edits are neither blamed on nor credited to this one.
# Run files live in .work/runs/<RUN_ID>/ like the shared runner's, so pipeline-stats.sh counts them.
# Written for the bash 3.2 that ships with macOS; needs git, perl and pgrep.
set -euo pipefail

CONFIG_KEYS="WAIT_MINUTES TAIL_LINES POLL_SECONDS COPILOT_BIN COPILOT_WRAPPER MAX_RUN_MINUTES STALL_MINUTES REPEAT_STOP NO_WRITE_STOP LONG_RUN_MINUTES COPILOT_NO_CUSTOM_INSTRUCTIONS COPILOT_REASONING_EFFORT HUNG_CHILD_MINUTES MAX_PARALLEL_WRITERS"

ORIG_PWD="$PWD"
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT")"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
RUNS="$REPO_ROOT/.work/runs"
mkdir -p "$RUNS"

load_config() {
  local file="$REPO_ROOT/.claude/crew.env" k
  if [[ ! -f $file ]]; then echo "Missing .claude/crew.env" >&2; exit 2; fi
  for k in $CONFIG_KEYS; do
    if eval "[[ -n \${$k+x} ]]"; then eval "__env_$k=\"\$$k\"; __has_$k=1"; fi
  done
  # shellcheck disable=SC1090
  source "$file"
  for k in $CONFIG_KEYS; do
    if eval "[[ -n \${__has_$k+x} ]]"; then eval "$k=\"\$__env_$k\""; fi
  done
  : "${WAIT_MINUTES:=25}" "${TAIL_LINES:=40}" "${POLL_SECONDS:=15}" "${COPILOT_BIN:=copilot}"
  : "${COPILOT_WRAPPER=}" "${MAX_RUN_MINUTES:=90}" "${STALL_MINUTES:=20}" "${REPEAT_STOP:=40}"
  : "${NO_WRITE_STOP:=15}" "${LONG_RUN_MINUTES:=25}" "${HUNG_CHILD_MINUTES:=10}"
  : "${COPILOT_NO_CUSTOM_INSTRUCTIONS:=1}" "${COPILOT_REASONING_EFFORT=}" "${MAX_PARALLEL_WRITERS:=2}"
  case "$COPILOT_REASONING_EFFORT" in ""|none|minimal|low|medium|high|xhigh|max) ;;
    *) echo "COPILOT_REASONING_EFFORT must be empty or one of none|minimal|low|medium|high|xhigh|max" >&2; exit 2 ;;
  esac
}
load_config

AGENTS_DIR="$REPO_ROOT/.github/agents"
PERMISSIONS_DIR="$REPO_ROOT/.github/copilot/permissions"

# --- Roles ----------------------------------------------------------------------------------------

# Writers change product files; scout, architect and reviewer write only plans, reviews and notes.
is_writer() { case "$1" in crew-builder-data|crew-builder-app|crew-builder-watch|crew-prover|crew-docs-keeper) return 0 ;; *) return 1 ;; esac; }
# Implementers are held to the no-write check (a builder that reads for 15 minutes and writes nothing).
is_implementer() { case "$1" in crew-builder-data|crew-builder-app|crew-builder-watch) return 0 ;; *) return 1 ;; esac; }

model_for() {
  local var="CREW_MODEL_$(printf '%s' "$1" | tr '-' '_')"
  eval "printf '%s' \"\${$var:-}\""
}

# --- Permissions and scope ------------------------------------------------------------------------

# Literal leading part of a glob: everything before its first wildcard.
literal_prefix() { printf '%s' "${1%%[*?[]*}"; }

PERM_FLAGS=()   # flags for the copilot call, with the write allows replaced by the run's scope
CEILING=()      # the profile's write globs: the most the agent may ever write
EFFECTIVE=()    # the write globs this run gets
load_permissions() {
  local agent="$1" scope_csv="${2:-}" file line g lp ok c
  PERM_FLAGS=(); CEILING=(); EFFECTIVE=()
  for file in "$PERMISSIONS_DIR/common.flags" "$PERMISSIONS_DIR/$agent.flags"; do
    [[ -f $file ]] || { echo "No permission profile: ${file#"$REPO_ROOT"/} — refusing to run '$agent'." >&2; exit 2; }
    while IFS= read -r line || [[ -n $line ]]; do
      line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -z $line || $line == \#* ]] && continue
      case "$line" in
        --allow-all-tools*|--allow-all|--allow-all=*|--yolo*|--allow-all-paths*|--allow-all-urls*)
          echo "Refusing to run: ${file#"$REPO_ROOT"/} grants everything ($line)." >&2; exit 2 ;;
        --allow-tool=write)
          echo "Refusing to run: ${file#"$REPO_ROOT"/} grants unscoped write. Crew profiles list paths: --allow-tool=write(<glob>)." >&2; exit 2 ;;
        *"shell(bash"*|*"shell(sh"*|*"shell(zsh"*|*"shell(fish"*|*"shell(pwsh"*|*"shell(powershell"*|*"shell(cmd"*|\
        *"shell(python"*|*"shell(node"*|*"shell(perl"*|*"shell(ruby"*|*"shell(env"*|*"shell(xargs"*|*"shell(eval"*|*"shell(exec"*)
          case "$line" in --deny-tool=*) ;; *)
            echo "Refusing to run: ${file#"$REPO_ROOT"/} allows an interpreter ($line)." >&2; exit 2 ;;
          esac ;;
        --allow-tool=write\(*\))
          if [[ $file == "$PERMISSIONS_DIR/$agent.flags" ]]; then
            g="${line#--allow-tool=write(}"; g="${g%)}"
            CEILING+=("$g")
            continue    # re-added below, as the run's scope
          fi ;;
        --*) ;;
        *) echo "Refusing to run: ${file#"$REPO_ROOT"/} has a line that is not a flag: $line" >&2; exit 2 ;;
      esac
      PERM_FLAGS+=("$line")
    done < "$file"
  done
  if [[ -n $scope_csv ]]; then
    local parts
    IFS=',' read -r -a parts <<< "$scope_csv"
    for g in "${parts[@]}"; do
      case "$g" in
        ""|/*|~*|*..*) echo "Refusing scope '$g': it must be a repository-relative glob with no '..'." >&2; exit 2 ;;
      esac
      lp="$(literal_prefix "$g")"; ok=0
      for c in ${CEILING[@]+"${CEILING[@]}"}; do
        if [[ $lp == "$(literal_prefix "$c")"* ]]; then ok=1; fi
      done
      if [[ $ok -eq 0 ]]; then
        echo "Refusing scope '$g': outside what $agent may write (${CEILING[*]:-nothing})." >&2; exit 2
      fi
      EFFECTIVE+=("$g")
    done
  else
    for g in ${CEILING[@]+"${CEILING[@]}"}; do EFFECTIVE+=("$g"); done
  fi
  for g in ${EFFECTIVE[@]+"${EFFECTIVE[@]}"}; do PERM_FLAGS+=("--allow-tool=write($g)"); done
}

# Pathspecs (git ":(glob)" form) for the non-.work globs of a run's scope file; none for read-only runs.
SCOPE_SPECS=()
scope_specs() {
  local dir="$1" g
  SCOPE_SPECS=()
  [[ -s $dir/scope ]] || return 0
  while IFS= read -r g; do
    [[ -z $g || $g == .work/* ]] && continue
    SCOPE_SPECS+=(":(glob)$g")
  done < "$dir/scope"
}

# 0 if the two globs can touch the same file (one literal prefix starts with the other).
globs_overlap() {
  local a b
  a="$(literal_prefix "$1")"; b="$(literal_prefix "$2")"
  [[ $a == "$b"* || $b == "$a"* ]]
}

# Refuses a start that would overlap a live run's scope or exceed MAX_PARALLEL_WRITERS.
check_parallel() {
  local agent="$1" d g h writers=0
  for d in "$RUNS"/*/; do
    d="${d%/}"
    [[ -f $d/exit ]] && continue
    worker_alive "$d" || continue
    if is_writer "$(cat "$d/agent" 2>/dev/null)"; then writers=$((writers + 1)); fi
    [[ -s $d/scope ]] || continue
    for g in ${EFFECTIVE[@]+"${EFFECTIVE[@]}"}; do
      [[ $g == .work/* ]] && continue
      while IFS= read -r h; do
        [[ -z $h || $h == .work/* ]] && continue
        if globs_overlap "$g" "$h"; then
          echo "Refusing to start $agent: its scope '$g' overlaps '$h' of live run $(basename "$d") ($(cat "$d/agent")). Narrow --scope, wait for that run, or pass --allow-overlap." >&2
          return 1
        fi
      done < "$d/scope"
    done
  done
  if is_writer "$agent" && [[ $writers -ge $MAX_PARALLEL_WRITERS ]]; then
    echo "Refusing to start $agent: $writers writer run(s) are already live (MAX_PARALLEL_WRITERS=$MAX_PARALLEL_WRITERS)." >&2
    return 1
  fi
  return 0
}

# --- Prompt pieces --------------------------------------------------------------------------------

# Sections of crew-rules.md headed "## Every agent" or naming the agent in parentheses.
crew_rules() {
  local agent="$1" file="$REPO_ROOT/.github/copilot/crew-rules.md"
  [[ -f $file ]] || return 0
  awk -v a="$agent" '
    /^<!--/ { c = 1 } c { if (/-->/) c = 0; next }
    /^## / { inc = ($0 ~ /^## Every agent/)
             if (match($0, /\([^)]*\)/)) { n = split(substr($0, RSTART + 1, RLENGTH - 2), w, /[ ,]+/)
               for (i = 1; i <= n; i++) if (w[i] == a) inc = 1 }
             if (inc) print; next }
    inc { print }' "$file"
}

# AGENTS.md "Known long-running or hanging commands" (read-only use of the owner's file).
known_hangs() {
  local file="$REPO_ROOT/AGENTS.md"
  [[ -f $file ]] || return 0
  awk '/^## Known long-running or hanging commands/ { on = 1; next } on && /^## / { exit }
       on && /<!--/ { c = 1 } on && c { if (/-->/) c = 0; next } on { print }' "$file" | sed '/^[[:space:]]*$/d'
}

usage() {
  sed -n '3,8p' "$SCRIPT" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

now() { date +%s; }
mtime() { perl -e 'my @s = stat(shift); print $s[9] // 0' "$1" 2>/dev/null || echo 0; }
minutes_since() { awk -v s="$1" -v n="$(now)" 'BEGIN { printf "%.1f", (n - s) / 60 }'; }

status_lines() { git -c core.quotepath=off status --porcelain=v1 -uall; }
run_status_lines() {   # status limited to the run's scope (whole tree when it has none)
  scope_specs "$1"
  if [[ ${#SCOPE_SPECS[@]} -gt 0 ]]; then
    git -c core.quotepath=off status --porcelain=v1 -uall -- "${SCOPE_SPECS[@]}" 2>/dev/null
  fi
}

# A cheap fingerprint of the changes inside the run's scope.
diff_fingerprint() {
  local dir="$1"
  scope_specs "$dir"
  if [[ ${#SCOPE_SPECS[@]} -eq 0 ]]; then echo 0; return; fi
  { git -c core.quotepath=off diff --numstat -- "${SCOPE_SPECS[@]}" 2>/dev/null
    git -c core.quotepath=off ls-files --others --exclude-standard -- "${SCOPE_SPECS[@]}" 2>/dev/null
  } | cksum | awk '{ print $1 }'
}

run_dir_for() {
  local dir="$RUNS/$1"
  if [[ ! -d $dir ]]; then echo "Unknown run id: $1" >&2; exit 2; fi
  echo "$dir"
}

worker_alive() {
  local pid_file="$1/pid"
  [[ -f $pid_file ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null
}

descendants() {
  local p
  for p in $(pgrep -P "$1" || true); do
    echo "$p"
    descendants "$p"
  done
}

worker() {
  # Runs in the detached background process.
  local dir="$1" agent prompt_file model code rules hangs
  agent="$(cat "$dir/agent")"
  prompt_file="$(cat "$dir/prompt_file")"
  model="$(cat "$dir/model")"
  local prompt="Your task brief is in the file ${prompt_file}. Read the whole file and carry it out. You cannot ask the user questions in this run. If something is unclear, make the most reasonable choice and list each such choice under an Open questions heading at the end of your final response."
  rules="$(crew_rules "$agent")"
  if [[ -n $rules ]]; then
    prompt="${prompt}

Standing rules for every run (a brief may add to them, never relax them):

${rules}"
  fi
  hangs="$(known_hangs)"
  if [[ -n $hangs ]]; then
    prompt="${prompt}

Known long-running or hanging commands in this repository:

${hangs}"
  fi
  load_permissions "$agent" "$(cat "$dir/scope_arg" 2>/dev/null || true)"
  local args=(-p "$prompt" --agent "$agent" --no-ask-user "${PERM_FLAGS[@]}")
  if [[ $COPILOT_NO_CUSTOM_INSTRUCTIONS == 1 ]]; then args+=(--no-custom-instructions); fi
  args+=(--disable-builtin-mcps --usage-output-file "$dir/usage.json")
  if [[ -n $model ]]; then
    args+=(--model "$model")
    export COPILOT_MODEL="$model" COPILOT_PROVIDER_MODEL_ID="$model" COPILOT_PROVIDER_WIRE_MODEL="$model"
  fi
  if [[ -n $COPILOT_REASONING_EFFORT ]]; then args+=(--reasoning-effort "$COPILOT_REASONING_EFFORT"); fi
  export OPENCODE_SESSION="crew-$(basename "$dir")"
  export OPENCODE_PROXY_LOG="$dir/proxy.log"
  local cmd=()
  if [[ $MAX_RUN_MINUTES -gt 0 ]]; then
    cmd+=(bash "$SCRIPT_DIR/with-timeout.sh" "$((MAX_RUN_MINUTES * 60))")
  fi
  if [[ -n $COPILOT_WRAPPER ]]; then cmd+=(bash "$SCRIPT_DIR/$COPILOT_WRAPPER"); fi
  cmd+=("$COPILOT_BIN" "${args[@]}")
  set +e
  "${cmd[@]}" > "$dir/output.log" 2>&1 < /dev/null
  code=$?
  set -e
  if [[ -f $dir/exit ]]; then return 0; fi
  if [[ $code -eq 124 && $MAX_RUN_MINUTES -gt 0 ]]; then
    echo max_runtime > "$dir/stop_reason"
    echo stopped > "$dir/exit"
  else
    echo "$code" > "$dir/exit"
  fi
}

start_run() {
  local agent="${1:-}" prompt_file="${2:-}" scope_arg="" model="" overlap=0
  [[ $# -ge 2 ]] || usage
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scope) scope_arg="${2:-}"; shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      --allow-overlap) overlap=1; shift ;;
      *) echo "Unknown option: $1" >&2; usage ;;
    esac
  done
  case "$agent" in crew-*) ;; *) echo "The crew runner only runs crew-* agents (got '$agent'). The shared pipeline's agents run through run-agent.sh." >&2; exit 2 ;; esac
  local abs="$prompt_file"
  if [[ $abs != /* ]]; then abs="$ORIG_PWD/$abs"; fi
  if [[ ! -f $abs ]]; then echo "Prompt file not found: $prompt_file" >&2; exit 2; fi
  abs="$(cd "$(dirname "$abs")" && pwd)/$(basename "$abs")"
  local rel="${abs#"$REPO_ROOT"/}"
  if [[ ! -f $AGENTS_DIR/$agent.agent.md ]]; then echo "No agent .github/agents/$agent.agent.md" >&2; exit 2; fi
  load_permissions "$agent" "$scope_arg"   # validate now: a bad profile or scope fails before anything starts
  if [[ -z $model ]]; then model="$(model_for "$agent")"; fi
  case "$model" in
    deepseek-v4.1-flash|glm-5.3-flash) ;;
    *) echo "Model '$model' is not one of the crew's two models (deepseek-v4.1-flash, glm-5.3-flash)." >&2; exit 2 ;;
  esac
  if [[ $overlap -eq 0 ]]; then check_parallel "$agent" || exit 2; fi

  local id dir n=1
  id="$(date +%Y%m%d-%H%M%S)-$(printf '%s' "$agent" | tr -cd 'A-Za-z0-9_-')"
  while [[ -d $RUNS/$id ]]; do n=$((n + 1)); id="$(date +%Y%m%d-%H%M%S)-$(printf '%s' "$agent" | tr -cd 'A-Za-z0-9_-')-$n"; done
  dir="$RUNS/$id"
  mkdir -p "$dir"
  printf '%s' "$agent" > "$dir/agent"
  printf '%s' "$rel" > "$dir/prompt_file"
  printf '%s' "$model" > "$dir/model"
  printf '%s' "$scope_arg" > "$dir/scope_arg"
  printf '%s\n' ${EFFECTIVE[@]+"${EFFECTIVE[@]}"} > "$dir/scope"
  printf '%s' "${COPILOT_WRAPPER:-none}" > "$dir/wrapper"
  echo crew > "$dir/team"
  run_status_lines "$dir" > "$dir/before"
  now > "$dir/started_epoch"
  diff_fingerprint "$dir" > "$dir/diff_fp"
  now > "$dir/diff_changed_epoch"
  touch "$dir/started"
  echo "$id" > "$RUNS/latest.txt"

  nohup bash "$SCRIPT" __worker "$dir" > /dev/null 2>&1 &
  echo $! > "$dir/pid"
  echo "$id"
}

# --- Health ---------------------------------------------------------------------------------------

# Loop signals from the agent log (see run-agent.sh for the log format). Prints four lines:
# action <count> <key>, denied <count>, text <count> <line>, read <count> <path>.
log_stats() {
  local log="$1"
  if [[ ! -f $log ]]; then printf 'action 0 -\ndenied 0\ntext 0 -\nread 0 -\n'; return; fi
  LC_ALL=C awk '
    function sq(s) { gsub(/[[:space:]]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
    function flush() { if (key != "") { act[key]++; key = "" } }
    /^(● |✗ |\/ )/ {
      flush()
      title = $0; sub(/^(● |✗ |\/ )/, "", title); sub(/[[:space:]]+[0-9.]+m?s[[:space:]]*$/, "", title)
      t = tolower(sq(title)); gsub(/[0-9]+/, "#", t); split(t, w, " ")
      kind = (t ~ /\(shell\)$/) ? "shell" : w[1]
      key = t; stage = (kind == "edit" || kind == "create") ? 0 : 1
      next
    }
    stage == 1 && /^  │ / { c = $0; sub(/^  │ /, "", c); key = kind ": " sq(c); if (kind == "read") reads[sq(c)]++; stage = 2; next }
    stage == 2 && /^  └ L[0-9]+:[0-9]+/ { r = $0; sub(/^  └ /, "", r); sub(/ .*/, "", r); key = key " " r; stage = 0; next }
    /Permission denied and could not request permission|Permission to run this tool was denied/ { denied++ }
    /^[[:space:]]*$/ || /^  [│└]/ { next }
    { stage = 0; x = tolower(sq($0)); if (length(x) >= 8) text[x]++ }
    END {
      flush()
      ba = "-"; ma = 0; for (k in act) if (act[k] > ma) { ma = act[k]; ba = k }
      bt = "-"; mt = 0; for (k in text) if (text[k] > mt) { mt = text[k]; bt = k }
      br = "-"; mr = 0; for (k in reads) if (reads[k] > mr) { mr = reads[k]; br = k }
      printf "action %d %s\ndenied %d\ntext %d %s\nread %d %s\n", ma, substr(ba, 1, 100), denied + 0, mt, substr(bt, 1, 80), mr, substr(br, 1, 100)
    }' "$log"
}
filler_limit() { local n=$((REPEAT_STOP * 5)); [[ $n -ge 200 ]] || n=200; echo "$n"; }

hung_children() {
  local dir="$1" wpid pids
  worker_alive "$dir" || return 0
  wpid="$(cat "$dir/pid")"
  pids="$(descendants "$wpid" | tr '\n' ',' | sed 's/,$//')"
  [[ -n $pids ]] || return 0
  { ps -o pid=,etime=,pcpu=,command= -p "$pids" 2>/dev/null || true; } | awk -v lim="$HUNG_CHILD_MINUTES" '
    function mins(e,   d, a, p, n) { d = 0
      if (index(e, "-")) { split(e, a, "-"); d = a[1]; e = a[2] }
      n = split(e, p, ":")
      if (n == 3) return d * 1440 + p[1] * 60 + p[2]
      if (n == 2) return d * 1440 + p[1]
      return 0 }
    { pid = $1; et = $2; cpu = $3; $1 = $2 = $3 = ""; cmd = substr($0, 4)
      if (cmd ~ /(^|\/)(copilot|node|bash|sh|zsh|perl|nohup)( |$)/) next
      if (cmd ~ /opencode-proxy|with-opencode|crew-run|with-timeout/) next
      if (mins(et) >= lim && cpu + 0 < 1.0) printf "%s %sm %s\n", pid, mins(et), substr(cmd, 1, 120) }'
}

no_write_yet() { [[ "$(cat "$1/diff_changed_epoch" 2>/dev/null)" == "$(cat "$1/started_epoch" 2>/dev/null)" ]]; }

check_health() {
  local dir="$1" fp old
  fp="$(diff_fingerprint "$dir")"
  old="$(cat "$dir/diff_fp" 2>/dev/null || true)"
  if [[ $fp != "$old" ]]; then
    echo "$fp" > "$dir/diff_fp"
    now > "$dir/diff_changed_epoch"
  fi
  [[ -f $dir/exit ]] && return 0
  worker_alive "$dir" || return 0

  local stats repeat_count denied text_count log_idle diff_idle id
  id="$(basename "$dir")"
  stats="$(log_stats "$dir/output.log")"
  repeat_count="$(echo "$stats" | awk '$1 == "action" { print $2 }')"
  denied="$(echo "$stats" | awk '$1 == "denied" { print $2 }')"
  text_count="$(echo "$stats" | awk '$1 == "text" { print $2 }')"
  if [[ $REPEAT_STOP -gt 0 ]]; then
    if [[ $repeat_count -ge $REPEAT_STOP ]]; then stop_run "$id" loop > /dev/null; return 0; fi
    if [[ $denied -ge $REPEAT_STOP ]]; then stop_run "$id" denied > /dev/null; return 0; fi
    if [[ $text_count -ge $(filler_limit) ]]; then stop_run "$id" filler > /dev/null; return 0; fi
  fi
  if [[ $NO_WRITE_STOP -gt 0 ]] && is_implementer "$(cat "$dir/agent")" && no_write_yet "$dir"; then
    if awk -v e="$(minutes_since "$(cat "$dir/started_epoch")")" -v s="$NO_WRITE_STOP" 'BEGIN { exit !(e >= s) }'; then
      stop_run "$id" no_write > /dev/null; return 0
    fi
  fi
  if [[ $STALL_MINUTES -gt 0 && -f $dir/output.log ]]; then
    log_idle="$(minutes_since "$(mtime "$dir/output.log")")"
    diff_idle="$(minutes_since "$(cat "$dir/diff_changed_epoch")")"
    if awk -v a="$log_idle" -v b="$diff_idle" -v s="$STALL_MINUTES" 'BEGIN { exit !(a >= s && b >= s) }'; then
      stop_run "$id" stalled > /dev/null
    fi
  fi
}

print_health() {
  local dir="$1" log="$1/output.log" lines=0 log_idle="-" stats repeat text hung requests tokens agent
  agent="$(cat "$dir/agent" 2>/dev/null)"
  if [[ -f $log ]]; then
    lines="$(wc -l < "$log" | tr -d ' ')"
    log_idle="$(minutes_since "$(mtime "$log")")"
  fi
  stats="$(log_stats "$log")"
  repeat="$(echo "$stats" | sed -n 's/^action //p')"
  text="$(echo "$stats" | sed -n 's/^text //p')"
  echo "HEALTH:"
  echo "  LOG_LINES: $lines · LOG_IDLE_MIN: $log_idle"
  echo "  SCOPE: $(tr '\n' ' ' < "$dir/scope" 2>/dev/null) · SCOPE_IDLE_MIN: $(minutes_since "$(cat "$dir/diff_changed_epoch" 2>/dev/null || now)")"
  echo "  TOP_REPEAT: ${repeat%% *}× \"${repeat#* }\" (auto-stop at ${REPEAT_STOP:-0}; 0 = off)"
  echo "  DENIED: $(echo "$stats" | sed -n 's/^denied //p') · TOP_TEXT_REPEAT: ${text%% *}× (auto-stop at $(filler_limit))"
  local topread; topread="$(echo "$stats" | sed -n 's/^read //p')"
  echo "  TOP_READ: ${topread%% *}× \"${topread#* }\" (one file, any line range)"
  if is_implementer "$agent" && no_write_yet "$dir" && [[ ! -f $dir/exit ]]; then
    echo "  FIRST_WRITE: none yet after $(minutes_since "$(cat "$dir/started_epoch")") min (auto-stop at ${NO_WRITE_STOP:-0}; 0 = off)"
  fi
  local elapsed; elapsed="$(minutes_since "$(cat "$dir/started_epoch")")"
  if [[ ${LONG_RUN_MINUTES:-0} -gt 0 && ! -f $dir/exit ]] && is_writer "$agent" \
     && awk -v e="$elapsed" -v l="$LONG_RUN_MINUTES" 'BEGIN { exit !(e >= l) }'; then
    echo "  LONG_RUN: $elapsed min, past $LONG_RUN_MINUTES; split the remaining work into its own run next time"
  fi
  if [[ -f $dir/proxy.log ]]; then
    requests="$(grep -c ' -> ' "$dir/proxy.log" || true)"
    echo "  MODEL_REQUESTS: $requests (errors: $(grep -cE ' -> [45][0-9][0-9]' "$dir/proxy.log" || true))"
  fi
  tokens="$( { grep -a '^Tokens ' "$log" 2>/dev/null || true; } | tail -n 1 | sed 's/^Tokens *//')"
  if [[ -n $tokens ]]; then echo "  TOKENS: $tokens"; fi
  hung="$(hung_children "$dir")"
  if [[ -n $hung ]]; then echo "$hung" | sed 's/^/  HUNG_CHILD: /'; fi
  local load cores
  load="$(uptime 2>/dev/null | sed -E 's/.*load averages?: *//; s/[ ,].*//')"
  cores="$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  if awk -v l="${load:-0}" -v c="$cores" 'BEGIN { exit !(l + 0 > c * 2) }'; then
    echo "  HIGH_LOAD: load average $load on $cores cores; timings are unreliable (look for stray processes with ps)"
  fi
}

# --- Summary --------------------------------------------------------------------------------------

summary() {
  local id="$1" dir status code="" elapsed
  dir="$(run_dir_for "$id")"
  elapsed="$(minutes_since "$(cat "$dir/started_epoch")")"

  if [[ -f $dir/exit ]]; then
    code="$(cat "$dir/exit")"
    case "$code" in 0) status=DONE ;; stopped) status=STOPPED ;; *) status=FAILED ;; esac
  elif worker_alive "$dir"; then
    status=RUNNING
  else
    status=FAILED
    code="none (worker exited without recording an exit code)"
  fi

  echo "RUN_ID: $id"
  echo "AGENT: $(cat "$dir/agent")$( [[ -s $dir/model ]] && echo " (model: $(cat "$dir/model"))" )"
  echo "STATUS: $status"
  if [[ $status == STOPPED ]]; then echo "STOP_REASON: $(cat "$dir/stop_reason" 2>/dev/null || echo user)"; fi
  if [[ -n $code && $status != STOPPED ]]; then echo "EXIT_CODE: $code"; fi
  echo "ELAPSED_MIN: $elapsed"
  echo "LOG: .work/runs/$id/output.log"
  print_health "$dir"

  if [[ $status == RUNNING ]]; then
    echo "NEXT: still running. Call again with: wait $id"
    return 0
  fi

  echo "FILES_CHANGED_DURING_RUN (inside this run's scope):"
  local any=0 line path
  while IFS= read -r line; do
    if [[ -z $line ]]; then continue; fi
    path="${line:3}"
    if [[ $path == *" -> "* ]]; then path="${path##* -> }"; fi
    path="${path#\"}"; path="${path%\"}"
    if ! grep -qxF -- "$line" "$dir/before" || { [[ -e $path ]] && [[ $path -nt $dir/started ]]; }; then
      echo "  $line"
      any=1
    fi
  done < <(run_status_lines "$dir")
  # Notes and reports under .work/crew are git-ignored, so list them by time instead.
  if [[ -d $REPO_ROOT/.work/crew ]]; then
    while IFS= read -r path; do
      [[ -n $path ]] && { echo "  (ignored) ${path#"$REPO_ROOT"/}"; any=1; }
    done < <(find "$REPO_ROOT/.work/crew" -type f -newer "$dir/started" 2>/dev/null)
  fi
  if [[ $any -eq 0 ]]; then echo "  (none)"; fi

  echo "--- LOG TAIL (last $TAIL_LINES lines) ---"
  if [[ -f $dir/output.log ]]; then tail -n "$TAIL_LINES" "$dir/output.log"; else echo "(no log written)"; fi
}

wait_run() {
  local id="$1" dir deadline
  dir="$(run_dir_for "$id")"
  deadline=$(( $(now) + WAIT_MINUTES * 60 ))
  while [[ ! -f $dir/exit ]] && [[ $(now) -lt $deadline ]]; do
    if ! worker_alive "$dir"; then
      sleep 2
      break
    fi
    check_health "$dir"
    [[ -f $dir/exit ]] && break
    sleep "$POLL_SECONDS"
  done
  summary "$id"
}

stop_run() {
  local id="$1" reason="${2:-user}" dir wpid tree
  dir="$(run_dir_for "$id")"
  if worker_alive "$dir"; then
    wpid="$(cat "$dir/pid")"
    tree="$(descendants "$wpid")"
    echo "$reason" > "$dir/stop_reason"
    echo stopped > "$dir/exit"
    kill -TERM "$wpid" 2>/dev/null || true
    if [[ -n $tree ]]; then kill -TERM $tree 2>/dev/null || true; fi
    sleep 1
  elif [[ ! -f $dir/exit ]]; then
    echo "$reason" > "$dir/stop_reason"
    echo stopped > "$dir/exit"
  fi
  summary "$id"
}

list_runs() {
  local d id status code
  printf '%-36s %-20s %-18s %-8s %s\n' RUN_ID AGENT MODEL STATUS ELAPSED_MIN
  for d in "$RUNS"/*/; do
    [[ -d $d && -f ${d}team ]] || continue
    d="${d%/}"; id="$(basename "$d")"
    if [[ -f $d/exit ]]; then
      code="$(cat "$d/exit")"
      case "$code" in 0) status=DONE ;; stopped) status=STOPPED ;; *) status=FAILED ;; esac
    elif worker_alive "$d"; then status=RUNNING; else status=FAILED; fi
    printf '%-36s %-20s %-18s %-8s %s\n' "$id" "$(cat "$d/agent" 2>/dev/null)" "$(cat "$d/model" 2>/dev/null)" "$status" \
      "$(minutes_since "$(cat "$d/started_epoch" 2>/dev/null || now)")"
  done
}

cmd="${1:-}"
if [[ $# -gt 0 ]]; then shift; fi
case "$cmd" in
  start)    if [[ $# -lt 2 ]]; then usage; fi; id="$(start_run "$@")"
            printf 'RUN_ID: %s\nSTATUS: STARTED\nNEXT: Started. Wait for it in the background (run_in_background: true): bash %s wait %s\n' "$id" "${SCRIPT#"$REPO_ROOT"/}" "$id" ;;
  wait)     if [[ $# -ne 1 ]]; then usage; fi; wait_run "$1" ;;
  status)   if [[ $# -ne 1 ]]; then usage; fi; d="$(run_dir_for "$1")"; check_health "$d"; summary "$1" ;;
  stop)     if [[ $# -ne 1 ]]; then usage; fi; stop_run "$1" user ;;
  list)     list_runs ;;
  check)    # dry run: validate agent, scope and model, and show what a start would grant
            agent="${1:-}"; scope=""; shift || true
            while [[ $# -gt 0 ]]; do case "$1" in --scope) scope="${2:-}"; shift 2 ;; *) shift ;; esac; done
            [[ -f $AGENTS_DIR/$agent.agent.md ]] || { echo "No agent $agent" >&2; exit 2; }
            load_permissions "$agent" "$scope"
            echo "OK $agent model=$(model_for "$agent")"
            echo "ceiling: ${CEILING[*]:-none}"; echo "effective write scope: ${EFFECTIVE[*]:-none}"
            check_parallel "$agent" && echo "parallel check: clear" ;;
  __worker) worker "$1" ;;
  *)        usage ;;
esac
