---
name: vscode-report-push
description: 把报告文件推送到已连接的 VS Code Remote-SSH 窗口打开。
---

# VS Code Report Push

## What

把 agent 生成的报告文件（文本/markdown）直接推送到用户当前已连接的 VS Code（Remote-SSH）窗口里打开，而不是只报一个路径。多文件各开一个 tab；同文件重复推送只激活已有 tab，不重复开。

socket 发现优先读 `/proc/net/unix` 内核活跃 socket 列表（天然排除 stale socket 文件、路径无关），不可用时回退到 runtime dir 目录扫描（`${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`）；涉及文件系统搜索一律 fd 优先、fd 不可用回退 GNU find。

## When to Use

- agent 刚生成了报告/结果文件，希望用户立即看到。
- 前提：检测到 `$HOME/.vscode-server` 存在（说明用户 VS Code Remote-SSH 连着本机）。
- VS Code 未连接时脚本会报错并把文件绝对路径打印到 stdout——此时 agent 应把路径直接告诉用户，让用户自己打开。
- 脚本通过 `$HOME` / `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}` 定位 server 与 socket，无机器本地硬编码，换用户/换机器不用改。

## How to Run

通过 terminal 工具执行（`<repo>` 为本仓库检出路径）：

```
bash <repo>/vscode-push.sh /abs/report.md [/abs/another.md ...]
```

- 传绝对路径最稳（脚本内部也会转绝对路径）。
- exit=0 即送达；stdout 会打印推送了哪些文件、用的哪个窗口 socket。

## Pitfalls

- socket 与 remote-cli 的路径含动态部分（commit-hash、socket uuid），每次 VS Code 升级/重连都会变，必须每次运行现查，不能缓存上次结果。
- 已打开的文件重复推送只是激活已有 tab，不会再开新 tab。
- 推送成功 ≠ 用户已读，只是窗口里出现了 tab。
- 任一文件不存在时脚本退出码 1 并在 stderr 列出缺失项，不会静默跳过。

## Verification

- 推送后 exit=0。
- 用户 VS Code 窗口出现对应文件的新 tab（或已开 tab 被激活）。
