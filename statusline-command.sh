#!/usr/bin/env bash
# Claude Code StatusLine — bash/Linux
# Line 1: model [effort]     │ ctx   bar pct          │ cache bar pct ↻ reset
# Line 2: ⎇ branch  $cost    │ 5h    bar pct ↻ reset  │ 7d    bar pct ↻ reset
# Requires: jq, git

input=$(cat)

# ── ANSI ─────────────────────────────────────────────────────────────────────
R=$'\e[0m'
bold=$'\e[1m'
white=$'\e[97m'
lbl_c=$'\e[38;5;245m'
sep_c=$'\e[38;5;245m'
yellow=$'\e[38;5;220m'
green=$'\e[38;5;83m'
orange=$'\e[38;5;208m'
red=$'\e[38;5;203m'
cyan=$'\e[38;5;117m'
gold=$'\e[38;5;178m'

SEP=" ${sep_c}│${R} "

BAR_W=8
LABEL_W=5

FULL='█'
EMPTY='░'

# ── Helpers ───────────────────────────────────────────────────────────────────
pct_color() {
    local p=$1
    if   (( p < 50 )); then printf '%s' "$green"
    elif (( p < 65 )); then printf '%s' "$yellow"
    elif (( p < 80 )); then printf '%s' "$orange"
    else                    printf '%s' "$red"
    fi
}

# Inverted scale: high cache hit rate is good (green), low is bad (red)
cache_color() {
    local p=$1
    if   (( p > 65 )); then printf '%s' "$green"
    elif (( p > 30 )); then printf '%s' "$orange"
    else                    printf '%s' "$red"
    fi
}

bar_plain() {
    local p=$1
    local f=$(( (BAR_W * p + 50) / 100 ))
    (( f > BAR_W )) && f=$BAR_W
    local e=$(( BAR_W - f ))
    local i
    for ((i=0; i<f; i++)); do printf '%s' "$FULL";  done
    for ((i=0; i<e; i++)); do printf '%s' "$EMPTY"; done
}

time_until() {
    local epoch=$1
    local now; now=$(date +%s)
    local diff=$(( epoch - now ))
    if (( diff <= 0 ));     then printf 'now'; return; fi
    local days=$(( diff / 86400 ))
    local hours=$(( (diff % 86400) / 3600 ))
    local mins=$(( (diff % 3600) / 60 ))
    if   (( days  >= 1 )); then printf '%dd%dh' "$days" "$hours"
    elif (( hours >= 1 )); then printf '%dh%dm'  "$hours" "$mins"
    else                        printf '%dm'     "$mins"
    fi
}

# segment LABEL PCT RESET [INVERT] [RST_W]
# RST_W = per-column reset width; 0 means no reset column rendered.
# INVERT=1 → use cache_color (high = good); omit or 0 → pct_color (high = bad)
segment() {
    local label=$1 pct=$2 reset=$3 invert=${4:-0} rst_w=${5:-0}
    local c
    if [[ "$invert" == "1" ]]; then c=$(cache_color "$pct")
    else                             c=$(pct_color   "$pct")
    fi
    local lbl; printf -v lbl "%-${LABEL_W}s" "$label"
    local bar; bar=$(bar_plain "$pct")
    local pct_str; printf -v pct_str "%3d%%" "$pct"
    local rst_str=""
    if (( rst_w > 0 )); then
        if [[ -n "$reset" ]]; then
            local r_plain; printf -v r_plain "%-${rst_w}s" "↻ $reset"
            rst_str=" ${white}${r_plain}${R}"
        else
            local r_empty; printf -v r_empty "%-${rst_w}s" ""
            rst_str=" ${r_empty}"
        fi
    fi
    printf '%s' "${lbl_c}${lbl}${R} ${c}${bar} ${pct_str}${R}${rst_str}"
}

# ── Parse JSON ────────────────────────────────────────────────────────────────
jq_get() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
jq_num() { printf '%s' "$input" | jq -r "($1) // 0"   2>/dev/null; }

model_name=$(jq_get '.model.display_name // .model.id // "Claude"')
[[ -z "$model_name" ]] && model_name="Claude"
effort_raw=$(jq_get '.effort.level')

ctx_ok=$(     jq_get '.context_window.used_percentage')
ctx_pct=$(    jq_num '.context_window.used_percentage | round' | awk '{printf "%d", $1}')

cache_read=$( jq_num '.context_window.current_usage.cache_read_input_tokens')
cache_new=$(  jq_num '.context_window.current_usage.cache_creation_input_tokens')
inp=$(        jq_num '.context_window.current_usage.input_tokens')
total_in=$(( cache_read + cache_new + inp ))

five_ok=$(    jq_get '.rate_limits.five_hour')
five_pct=$(   jq_num '.rate_limits.five_hour.used_percentage | round' | awk '{printf "%d", $1}')
five_epoch=$( jq_num '.rate_limits.five_hour.resets_at')

week_ok=$(    jq_get '.rate_limits.seven_day')
week_pct=$(   jq_num '.rate_limits.seven_day.used_percentage | round' | awk '{printf "%d", $1}')
week_epoch=$( jq_num '.rate_limits.seven_day.resets_at')

cost_raw=$(   jq_num '.cost.total_cost_usd')
cwd=$(        jq_get '.workspace.current_dir')
[[ -z "$cwd" ]] && cwd="$PWD"

# ── Model color ───────────────────────────────────────────────────────────────
model_lower="${model_name,,}"
if   [[ "$model_lower" =~ haiku|small|mini|lite ]]; then model_color="$yellow"
elif [[ "$model_lower" =~ opus|large             ]]; then model_color="$red"
else                                                      model_color="$green"
fi

# ── Effort ────────────────────────────────────────────────────────────────────
effort_label=""; effort_color="$green"
case "$effort_raw" in
    low)    effort_label="low";   effort_color="$yellow" ;;
    medium) effort_label="med";   effort_color="$green"  ;;
    high)   effort_label="high";  effort_color="$orange" ;;
    xhigh)  effort_label="xhigh"; effort_color="$red"    ;;
    max)    effort_label="max";   effort_color="$red"     ;;
esac

# ── col1 plain widths — computed after branch/cost are known ──────────────────
# (set below, after git and cost sections)

# ── Cache hit rate ────────────────────────────────────────────────────────────
cache_hit_pct=0; cache_hit_ok=""
if (( total_in > 0 )); then
    cache_hit_pct=$(( (cache_read * 100) / total_in ))
    cache_hit_ok="yes"
fi

# Track cache creation for 5-min TTL countdown
cache_stamp="/tmp/claude-cache-stamp.txt"
cache_reset_str=""
if (( cache_new > 0 )); then
    date +%s > "$cache_stamp"
fi
if [[ -f "$cache_stamp" ]]; then
    stamp_time=$(cat "$cache_stamp")
    now_time=$(date +%s)
    age=$(( now_time - stamp_time ))
    left=$(( 300 - age ))
    if (( left > 5 )); then
        printf -v cache_reset_str '%dm%02ds' "$(( left / 60 ))" "$(( left % 60 ))"
    fi
fi

# ── Git ───────────────────────────────────────────────────────────────────────
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
dirty_count=$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# ── Cost ──────────────────────────────────────────────────────────────────────
cost_plain=""
if [[ -n "$cost_raw" && "$cost_raw" != "0" ]]; then
    cost_plain=$(printf '$%.2f' "$cost_raw")
fi

# ── Rate limit reset strings ──────────────────────────────────────────────────
five_reset_str=""; week_reset_str=""
[[ -n "$five_ok" && "$five_epoch" -gt 0 ]] && five_reset_str=$(time_until "$five_epoch")
[[ -n "$week_ok" && "$week_epoch" -gt 0 ]] && week_reset_str=$(time_until "$week_epoch")

# ── Per-column RST widths — max of reset-string visual widths in that column ──
# Column 2: ctx (no reset) vs 5h; Column 3: cache vs 7d
rst_vis() { local s="$1"; (( ${#s} > 0 )) && echo $(( 2 + ${#s} )) || echo 0; }
col2_rst=$(rst_vis "$five_reset_str")
c3a=$(rst_vis "$cache_reset_str"); c3b=$(rst_vis "$week_reset_str")
col3_rst=$(( c3a > c3b ? c3a : c3b ))

# ── col1 plain widths — now we know model, effort, branch, cost ───────────────
line1_col1_plain="$model_name"
[[ -n "$effort_label" ]] && line1_col1_plain+=" [$effort_label]"
line1_col1_w=${#line1_col1_plain}

branch_plain_len=0
[[ -n "$branch" ]] && branch_plain_len=$(( 2 + ${#branch} ))
(( dirty_count > 0 && branch_plain_len > 0 )) && (( branch_plain_len += 2 ))  # " ●" = 2 visible chars
gap_len=0
[[ -n "$branch" && -n "$cost_plain" ]] && gap_len=2
line2_col1_plain_len=$(( branch_plain_len + gap_len + ${#cost_plain} ))

# Both columns padded to the same width so │ separators align vertically
col1_w=$(( line1_col1_w > line2_col1_plain_len ? line1_col1_w : line2_col1_plain_len ))

# ══ LINE 1 ════════════════════════════════════════════════════════════════════
line1="${model_color}${bold}${model_name}${R}"
[[ -n "$effort_label" ]] && line1+=" ${effort_color}[${effort_label}]${R}"
# Pad line1 col1 to col1_w
pad1=$(( col1_w - line1_col1_w ))
for ((i=0; i<pad1; i++)); do line1+=" "; done
[[ -n "$ctx_ok"       ]] && line1+="${SEP}$(segment 'ctx'   "$ctx_pct"       ''                0 "$col2_rst")"
[[ -n "$cache_hit_ok" ]] && line1+="${SEP}$(segment 'cache' "$cache_hit_pct" "$cache_reset_str" 1 "$col3_rst")"

# ══ LINE 2 ════════════════════════════════════════════════════════════════════
line2_col1=""
if [[ -n "$branch" ]]; then
    dirty_str=""
    (( dirty_count > 0 )) && dirty_str=" ${orange}●${R}"
    line2_col1+="${cyan}⎇ ${branch}${R}${dirty_str}"
fi
[[ -n "$branch" && -n "$cost_plain" ]] && line2_col1+="  "
[[ -n "$cost_plain" ]]                 && line2_col1+="${gold}${cost_plain}${R}"

pad2=$(( col1_w - line2_col1_plain_len ))
for ((i=0; i<pad2; i++)); do line2_col1+=" "; done

line2="$line2_col1"
[[ -n "$five_ok" ]] && line2+="${SEP}$(segment '5h' "$five_pct" "$five_reset_str" 0 "$col2_rst")"
[[ -n "$week_ok" ]] && line2+="${SEP}$(segment '7d' "$week_pct" "$week_reset_str" 0 "$col3_rst")"

# ══ Emit ══════════════════════════════════════════════════════════════════════
out="$line1"
has_line2=false
[[ -n "$branch" || -n "$cost_plain" || -n "$five_ok" || -n "$week_ok" ]] && has_line2=true
$has_line2 && out+=$'\n'"$line2"

printf '%s' "$out"
