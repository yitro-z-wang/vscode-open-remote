# vscode-open-remote

Open files in the VS Code window that is connected to this machine via **Remote-SSH** — from a script, a cron job, or an AI agent. Instead of printing a path for a human to copy, push the file straight into the editor as a tab.

Works on any Linux server: no hardcoded paths, no root assumptions, nothing to configure.

## Requirements

- Linux with bash
- A VS Code window currently connected to this machine via Remote-SSH
- GNU coreutils (`stat`, `find`)
- Optional: [`fd`](https://github.com/sharkdp/fd) — used for filesystem searches when available, `find` otherwise

## Usage

```bash
./vscode-push.sh /abs/report.md [/abs/another-file ...]
```

Each file opens in its own tab. Pushing a file that is already open just re-activates its tab.

On success the script prints what was pushed and through which window socket, and exits `0`.

### Exit codes

| Code | Meaning | Output |
|------|---------|--------|
| 0 | Pushed; tabs opened in the VS Code window | stdout: pushed files + socket used |
| 1 | At least one file does not exist | stderr: missing files |
| 2 | VS Code remote-cli not found (no Remote-SSH server install) | stderr: reason · stdout: file paths |
| 3 | No active `vscode-ipc` socket (window not connected) | stderr: reason · stdout: file paths |
| 4 | Push attempt failed (e.g. socket died mid-run) | stderr: reason · stdout: file paths |

Every failure prints the absolute file paths to stdout so a caller (or agent) can fall back to just showing them. Nothing fails silently.

## How it works

VS Code Remote-SSH ships a CLI on the server side, and the connected window exposes a local IPC socket. The mechanism — `VSCODE_IPC_HOOK_CLI=<socket> remote-cli/code --goto <file>` — is a community discovery from [microsoft/vscode-remote-release#2721](https://github.com/microsoft/vscode-remote-release/issues/2721). This repo wraps it in a robust, dependency-light script. Credit for the underlying trick goes to that issue's contributors.

Everything dynamic is discovered at runtime, on every run:

**1. remote-cli** — newest (mtime) existing executable among both known layouts under `$HOME/.vscode-server`:

```
$HOME/.vscode-server/cli/servers/Stable-<hash>/server/bin/remote-cli/code   # current CLI layout
$HOME/.vscode-server/bin/<hash>/bin/code                                    # older layout
```

**2. IPC socket** — kernel view first: `/proc/net/unix` lists only *live, bound* sockets, so stale `vscode-ipc-*.sock` leftovers are naturally excluded and the lookup is path-independent. Among the `vscode-ipc-*.sock` candidates, the newest by mtime wins. If `/proc/net/unix` is unreadable (non-Linux, restricted), it falls back to scanning `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}` for `vscode-ipc-*.sock` — that is the only fallback layer.

**3. Files** are converted to absolute paths before being handed to the CLI.

Filesystem searches prefer `fd` when installed and fall back to GNU `find`.

### Test-only overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `VSCODE_UNIX_TABLE` | `/proc/net/unix` | Fake the kernel socket table |
| `VSCODE_SOCK_DIR` | `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}` | Fake the socket directory |
| `VSCODE_SERVER_DIR` | `$HOME/.vscode-server` | Fake the server install root |

## Agent integration

`SKILL.md` in this repo is a drop-in skill description for AI agents (Claude Code, OpenCode, Hermes, …) that tells the agent when and how to push reports to your window.

## Notes & limitations

- Success means the tab opened — not that the human read it.
- Relies on VS Code server internals (socket naming, CLI layout). These have been stable for years, but a major VS Code change would require updating the discovery globs. 100% portability is not a goal.
- Pushing to *which* window: with several windows connected, the newest socket (most recent connection) wins.

## License

[MIT](LICENSE)
