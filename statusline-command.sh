#!/usr/bin/env bash
# Claude Code StatusLine — bash/Linux
# Line 1: model [effort]     │ ctx   bar pct   │ 5h    bar pct ↻ reset │ rot bar pct
# Line 2: ⎇ branch  $cost    │ cache bar pct   │ 7d    bar pct ↻ reset │ eff bar pct
# Last column on each line: token-optimizer's own composite scores -- rot =
# 100 - resource_health (line 1, irreversible/kill signal) and eff =
# session_efficiency (line 2, recoverable/compact signal) -- gated on the
# quality-cache existing.
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

# segment LABEL PCT RESET [INVERT] [RST_W] [LABEL_W]
# RST_W = per-column reset width; 0 means no reset column rendered.
# LABEL_W = pad width for THIS column's label, i.e. max label length across
# the rows that share this column (not a single global width) — default
# falls back to the global LABEL_W for any caller that doesn't pass one.
# INVERT=1 → use cache_color (high = good); omit or 0 → pct_color (high = bad)
segment() {
    local label=$1 pct=$2 reset=$3 invert=${4:-0} rst_w=${5:-0} label_w=${6:-$LABEL_W}
    local c
    if [[ "$invert" == "1" ]]; then c=$(cache_color "$pct")
    else                             c=$(pct_color   "$pct")
    fi
    local lbl; printf -v lbl "%-${label_w}s" "$label"
    local bar; bar=$(bar_plain "$pct")
    local pct_str; printf -v pct_str "%3d%%" "$pct"
    local rst_str=""
    if (( rst_w > 0 )); then
        if [[ -n "$reset" ]]; then
            # Manual char-width padding, not printf %-Ns: "↻" is multi-byte
            # UTF-8, so printf pads by byte length and silently under-pads,
            # drifting every column after this one out of alignment.
            local r_plain="↻ $reset"
            local pad=$(( rst_w - ${#r_plain} )) pad_str="" i
            (( pad < 0 )) && pad=0
            for ((i=0; i<pad; i++)); do pad_str+=" "; done
            rst_str=" ${white}${r_plain}${pad_str}${R}"
        else
            local r_empty="" i
            for ((i=0; i<rst_w; i++)); do r_empty+=" "; done
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

session_id_raw=$(jq_get '.session_id')

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
# Always render when ctx data exists, even at 0 total_in (e.g. right after
# compact) -- a missing segment there reads as "no cache stat", not "0%".
cache_hit_pct=0; cache_hit_ok=""
if (( total_in > 0 )); then
    cache_hit_pct=$(( (cache_read * 100) / total_in ))
fi
[[ -n "$ctx_ok" ]] && cache_hit_ok="yes"

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

# ── Token Optimizer quality cache (1 extra column per line) ───────────────────
# token-optimizer already collapses its 7 signals into two weighted composites
# -- resource_health (monotonic, irreversible: fill degradation 0.50 +
# compaction depth 0.30 + waste tokens 0.20) and session_efficiency (rolling,
# recoverable: stale reads 0.30 + bloated results 0.30 + decision density 0.20
# + agent efficiency 0.20). Use those directly instead of re-deriving a
# collapse from the sub-signals ourselves.
# rot = 100 - resource_health, shown plainly as rot (not health) -- default
# coloring, high rot = red, no inversion needed. eff = session_efficiency,
# inverted (high = green). Both labels 3 chars so they pad identically to
# LABEL_W=5 on both lines -- a longer label here would widen one line's
# column and misalign everything after it on the other line.
qual_seg1=""; qual_seg2=""
if [[ -n "$session_id_raw" ]]; then
    safe_sid=$(printf '%s' "$session_id_raw" | tr -cd 'A-Za-z0-9_-')
    qcache="$HOME/.claude/token-optimizer/quality-cache-${safe_sid}.json"
    if [[ -n "$safe_sid" && -f "$qcache" ]]; then
        q_res=$(jq -r '(.resource_health | round) // empty'   "$qcache" 2>/dev/null)
        q_eff=$(jq -r '(.session_efficiency | round) // empty' "$qcache" 2>/dev/null)
        [[ -n "$q_res" ]] && qual_seg1="${SEP}$(segment 'rot' "$(( 100 - q_res ))" '' 0 0 3)"
        [[ -n "$q_eff" ]] && qual_seg2="${SEP}$(segment 'eff' "$q_eff" '' 1 0 3)"
    fi
fi

# ── Per-column RST widths — max of reset-string visual widths in that column ──
# Column 2: ctx vs cache, neither ever shows a reset. Column 3: 5h vs 7d, both do.
rst_vis() { local s="$1"; (( ${#s} > 0 )) && echo $(( 2 + ${#s} )) || echo 0; }
col2_rst=0
c3a=$(rst_vis "$five_reset_str"); c3b=$(rst_vis "$week_reset_str")
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
[[ -n "$ctx_ok"  ]] && line1+="${SEP}$(segment 'ctx' "$ctx_pct"  ''                0 "$col2_rst" 5)"
[[ -n "$five_ok" ]] && line1+="${SEP}$(segment '5h'  "$five_pct" "$five_reset_str" 0 "$col3_rst" 2)"
line1+="$qual_seg1"

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
[[ -n "$cache_hit_ok" ]] && line2+="${SEP}$(segment 'cache' "$cache_hit_pct" '' 1 "$col2_rst" 5)"
[[ -n "$week_ok"      ]] && line2+="${SEP}$(segment '7d'    "$week_pct"      "$week_reset_str"  0 "$col3_rst" 2)"
line2+="$qual_seg2"

# ══ Emit ══════════════════════════════════════════════════════════════════════
out="$line1"
has_line2=false
[[ -n "$branch" || -n "$cost_plain" || -n "$cache_hit_ok" || -n "$week_ok" || -n "$qual_seg2" ]] && has_line2=true
$has_line2 && out+=$'\n'"$line2"

printf '%s' "$out"
