#!/bin/bash
# 金刚罩 — Health Patrol
# 系统健康巡检：进程 + 磁盘 + Session + 内存DB + 备份 + Cron + 临时文件
set -uo pipefail

OPENCLAW_DIR="${HOME}/.openclaw"
SESSIONS_DIR="${OPENCLAW_DIR}/agents/main/sessions"
MEMORY_DIR="${OPENCLAW_DIR}/memory"
BACKUP_DIR="${OPENCLAW_DIR}/backups"
DATA_DIR="${OPENCLAW_DIR}/data"
TMP_LEDGER="/tmp/token-ledger-*.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()      { echo -e "${GREEN}[   OK   ]${NC} $1"; }
warn()    { echo -e "${YELLOW}[ WARNING]${NC} $1"; }
critical(){ echo -e "${RED}[CRITICAL]${NC} $1"; }
info()    { echo -e "${CYAN}[  INFO  ]${NC} $1"; }

WARNINGS=0
CRITICALS=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔱  金刚罩 — Health Patrol"
echo "   $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── 1. Gateway Process ───
info "1/8 Gateway 进程状态"
GW_STATUS=$(openclaw gateway status 2>&1)
if echo "$GW_STATUS" | grep -q "running"; then
    GW_PID=$(echo "$GW_STATUS" | grep -oE "pid [0-9]+" | grep -oE "[0-9]+")
    # Memory usage
    if [ -n "$GW_PID" ]; then
        MEM_MB=$(ps -o rss= -p "$GW_PID" 2>/dev/null | awk '{printf "%.0f", $1/1024}')
        if [ -n "$MEM_MB" ]; then
            if [ "$MEM_MB" -gt 1024 ]; then
                warn "Gateway 内存占用 ${MEM_MB}MB (>1GB)"
                WARNINGS=$((WARNINGS + 1))
            elif [ "$MEM_MB" -gt 512 ]; then
                warn "Gateway 内存占用 ${MEM_MB}MB (>512MB)"
                WARNINGS=$((WARNINGS + 1))
            else
                ok "Gateway 运行中 (pid ${GW_PID}, ${MEM_MB}MB)"
            fi
        else
            ok "Gateway 运行中 (pid ${GW_PID})"
        fi
    fi
else
    critical "Gateway 未运行！"
    CRITICALS=$((CRITICALS + 1))
fi

# ─── 2. Disk Space ───
info "2/8 磁盘空间"
AVAIL_GB=$(df -g "$HOME" 2>/dev/null | tail -1 | awk '{print $4}')
USED_PCT=$(df -g "$HOME" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
if [ -n "$AVAIL_GB" ]; then
    if [ "$AVAIL_GB" -lt 5 ]; then
        critical "磁盘可用空间仅 ${AVAIL_GB}GB！(使用率 ${USED_PCT}%)"
        CRITICALS=$((CRITICALS + 1))
    elif [ "$AVAIL_GB" -lt 10 ]; then
        warn "磁盘可用空间 ${AVAIL_GB}GB (使用率 ${USED_PCT}%)"
        WARNINGS=$((WARNINGS + 1))
    else
        ok "磁盘空间 ${AVAIL_GB}GB 可用 (使用率 ${USED_PCT}%)"
    fi
fi

# ─── 3. OpenClaw Directory Size ───
info "3/8 OpenClaw 目录空间"
OC_SIZE=$(du -sh "$OPENCLAW_DIR" 2>/dev/null | awk '{print $1}')
ok "OpenClaw 总占用: ${OC_SIZE}"

# Sub-directory breakdown
for subdir in agents/main/sessions memory plugins workspace data backups; do
    D="${OPENCLAW_DIR}/${subdir}"
    if [ -d "$D" ]; then
        SIZE=$(du -sh "$D" 2>/dev/null | awk '{print $1}')
        echo "     └─ ${subdir}: ${SIZE}"
    fi
done

# ─── 4. Session Files ───
info "4/8 Session 文件"
if [ -d "$SESSIONS_DIR" ]; then
    SESSION_COUNT=$(ls -1 "$SESSIONS_DIR"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
    SESSIONS_SIZE=$(du -sh "$SESSIONS_DIR" 2>/dev/null | awk '{print $1}')
    
    if [ "$SESSION_COUNT" -gt 50 ]; then
        warn "Session 文件 ${SESSION_COUNT} 个 (${SESSIONS_SIZE})，建议清理旧 session"
        WARNINGS=$((WARNINGS + 1))
    else
        ok "Session 文件 ${SESSION_COUNT} 个 (${SESSIONS_SIZE})"
    fi
    
    # Find sessions older than 7 days
    OLD_SESSIONS=$(find "$SESSIONS_DIR" -name "*.jsonl" -mtime +7 2>/dev/null | wc -l | tr -d ' ')
    if [ "$OLD_SESSIONS" -gt 0 ]; then
        info "  └─ 超过 7 天的旧 session: ${OLD_SESSIONS} 个"
    fi
else
    ok "暂无 session 文件"
fi

# ─── 5. Memory Database ───
info "5/8 记忆数据库"
if [ -d "$MEMORY_DIR" ]; then
    MEM_SIZE=$(du -sh "$MEMORY_DIR" 2>/dev/null | awk '{print $1}')
    ok "记忆数据库: ${MEM_SIZE}"
else
    ok "记忆数据库未创建"
fi

# ─── 6. Backup Management ───
info "6/8 备份文件"
if [ -d "$BACKUP_DIR" ]; then
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.bak 2>/dev/null | wc -l | tr -d ' ')
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
    
    if [ "$BACKUP_COUNT" -gt 20 ]; then
        warn "备份文件 ${BACKUP_COUNT} 个 (${BACKUP_SIZE})，建议清理"
        WARNINGS=$((WARNINGS + 1))
    else
        ok "备份文件 ${BACKUP_COUNT} 个 (${BACKUP_SIZE})"
    fi
    
    # Show latest backup
    LATEST=$(ls -1t "$BACKUP_DIR"/*.bak 2>/dev/null | head -1)
    if [ -n "$LATEST" ]; then
        info "  └─ 最新备份: $(basename "$LATEST")"
    fi
else
    warn "备份目录不存在"
    WARNINGS=$((WARNINGS + 1))
fi

# ─── 7. Cron Jobs ───
info "7/8 Cron 任务状态"
CRON_OUTPUT=$(openclaw cron list 2>&1)
CRON_COUNT=$(echo "$CRON_OUTPUT" | grep -c "enabled" 2>/dev/null) || CRON_COUNT=0
ok "活跃 Cron 任务: ${CRON_COUNT} 个"
echo "$CRON_OUTPUT" | { grep -E "name|enabled|next" 2>/dev/null || true; } | head -20

# ─── 8. Temp Files Cleanup ───
info "8/8 临时文件"
TMP_COUNT=$(find /tmp -name "token-ledger-*" -o -name "morning-ledger*" -o -name "openclaw-*" 2>/dev/null | wc -l | tr -d ' ')
if [ "$TMP_COUNT" -gt 10 ]; then
    warn "临时文件 ${TMP_COUNT} 个，清理中..."
    find /tmp -name "token-ledger-*" -mtime +1 -delete 2>/dev/null || true
    find /tmp -name "morning-ledger*" -mtime +1 -delete 2>/dev/null || true
    ok "已清理过期临时文件"
else
    ok "临时文件 ${TMP_COUNT} 个"
fi

# ─── Summary ───
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$CRITICALS" -gt 0 ]; then
    critical "巡检完成: $CRITICALS 严重问题, $WARNINGS 警告"
    echo "EXIT_CODE=CRITICAL"
    exit 2
elif [ "$WARNINGS" -gt 0 ]; then
    warn "巡检完成: $WARNINGS 警告"
    echo "EXIT_CODE=WARNING"
    exit 1
else
    ok "巡检完成: 系统健康 ✅"
    echo "EXIT_CODE=OK"
    exit 0
fi
