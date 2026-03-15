---
name: 金刚罩
version: 1.0.0
description: "金刚罩 — OpenClaw 系统守护：配置安全（pre-validate + 自动备份 + 失败回滚）、健康巡检、资源优化、故障自愈。刀枪不入，百毒不侵。"
author: 主谋
emoji: 🔱
tags:
  - system
  - guardian
  - resilience
  - rollback
  - health
  - optimization
metadata:
  openclaw:
    requires:
      bins: [openclaw, python3]
---

# 🔱 金刚罩 — 刀枪不入，百毒不侵

让 OpenClaw 更强壮、更高效、不容易崩溃。

## 核心能力

### 1. 安全重启（Safe Restart）

**永远不要直接跑 `openclaw gateway restart`**，使用：

```bash
bash ~/.openclaw/skills/system-guardian/scripts/safe-restart.sh
```

流程：
```
校验配置 → 自动备份(3件套) → 重启 Gateway → 健康检查 → 失败则自动回滚
```

详细步骤：
1. `openclaw config validate` — 配置语法和字段校验
2. 备份三个关键文件到 `~/.openclaw/backups/`：
   - `openclaw.json.<timestamp>.bak` — 主配置
   - `env.<timestamp>.bak` — 环境变量
   - `ai.openclaw.gateway.plist.<timestamp>.bak` — macOS 开机自启配置
3. `openclaw gateway restart`
4. 等待 15 秒，检查 `openclaw gateway status`
5. 如果 Gateway 不在线：自动恢复全部备份 → 再次重启 → 再次检查
6. 如果仍然失败：报警并保留现场

### 2. 配置变更防护（Config Guard）

修改 `openclaw.json` 前调用：

```bash
bash ~/.openclaw/skills/system-guardian/scripts/config-guard.sh check
```

检查项目：
- JSON 语法是否合法
- 必需字段是否存在（gateway, channels, agents）
- 环境变量引用 `${VAR}` 是否在 .env 中有定义
- 端口冲突检查
- 模型 ID 格式是否合法

### 3. 健康巡检（Health Patrol）

```bash
bash ~/.openclaw/skills/system-guardian/scripts/health-patrol.sh
```

检查项目：
- Gateway 进程状态 + 内存占用
- 磁盘空间（总量、可用、session 文件大小）
- Session 文件累积（清理过期 session）
- 内存数据库大小
- /tmp 临时文件清理
- Cron 任务状态（是否有失败的）
- 备份文件管理（保留最近 10 个，清理更旧的）

### 4. 资源优化建议（Resource Advisor）

根据当前系统状态给出优化建议：
- Session transcript 过大时建议清理
- 备份文件过多时建议归档
- 磁盘空间低于 10GB 时预警
- 内存占用异常时分析原因
- 模型使用效率分析（哪些 cron 可以用更轻的模型）

## Agent 使用指南

当需要修改配置或重启 Gateway 时，按以下流程操作：

```
1. 修改 openclaw.json
2. 运行 config-guard.sh check 验证
3. 如果验证通过 → 运行 safe-restart.sh
4. 如果验证失败 → 修复问题后重试
```

**铁律：任何配置变更必须经过 safe-restart.sh，禁止直接 `openclaw gateway restart`**

## 推荐 Cron 配置

```json5
{
  "name": "system-health-patrol",
  "description": "每日凌晨 4:00 系统健康巡检 + 资源清理",
  "schedule": { "kind": "cron", "expr": "0 4 * * *", "tz": "Asia/Shanghai" },
  "sessionTarget": "isolated",
  "delivery": { "mode": "none" },
  "payload": {
    "kind": "agentTurn",
    "model": "anthropic/claude-sonnet-4-6",
    "timeoutSeconds": 120,
    "message": "运行系统健康巡检：bash ~/.openclaw/skills/system-guardian/scripts/health-patrol.sh\n读取输出，如果发现任何 WARNING 或 CRITICAL 级别的问题，通过 Telegram 通知用户（称呼：老大）。如果全部 OK 则静默。"
  }
}
```

## 演进计划

- v1.0: 安全重启 + 配置防护 + 健康巡检
- v1.1: 资源优化建议 + 自动清理策略
- v1.2: 故障模式库（常见问题 → 自动修复）
- v1.3: 性能基线记录 + 异常检测
- v2.0: 多节点健康管理
