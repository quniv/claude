#!/usr/bin/env python3
"""Resolve where each coding agent discovers skills and agent definitions.

Standard-library only, so any coding agent on any machine can run it with a
bare `python3`. No third-party dependency, no package manager, no install step.

Path facts (verified against upstream sources, see references/targets.md):

  Claude Code   skills  <root>/.claude/skills/<name>/     ~/.claude/skills/<name>/
                agents  <root>/.claude/agents/<name>.md   ~/.claude/agents/<name>.md
  Codex CLI     skills  <root>/.codex/skills/<name>/      $CODEX_HOME/skills/<name>/
                agents  <root>/.codex/agents/<name>.toml  $CODEX_HOME/agents/<name>.toml

$CODEX_HOME defaults to ~/.codex.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
NAME_MAX = 64

TOOLS = ("claude", "codex")
SCOPES = ("project", "user")
KINDS = ("skill", "agent")

TOOL_LABELS = {"claude": "Claude Code", "codex": "Codex CLI"}


class TargetError(ValueError):
    """A target could not be resolved, or an input was invalid."""


def validate_name(value: str, label: str = "name") -> str:
    """Enforce the lowercase-hyphen-case convention both tools share."""
    if not value:
        raise TargetError(f"{label} is required")
    if len(value) > NAME_MAX:
        raise TargetError(f"{label} {value!r} exceeds {NAME_MAX} characters")
    if not NAME_PATTERN.fullmatch(value):
        raise TargetError(
            f"invalid {label} {value!r}: use lowercase letters, digits and single "
            "hyphens, with no leading or trailing hyphen"
        )
    return value


def codex_home() -> Path:
    """Honour $CODEX_HOME, which users legitimately relocate."""
    override = os.environ.get("CODEX_HOME")
    return Path(override).expanduser() if override else Path.home() / ".codex"


def _tool_root(tool: str, scope: str, project_root: Path) -> Path:
    if tool == "claude":
        return (project_root / ".claude") if scope == "project" else (Path.home() / ".claude")
    if tool == "codex":
        return (project_root / ".codex") if scope == "project" else codex_home()
    raise TargetError(f"unknown tool {tool!r}; expected one of {', '.join(TOOLS)}")


@dataclass(frozen=True)
class Target:
    """One concrete destination: a tool, a scope, and the path to write."""

    tool: str
    scope: str
    kind: str
    name: str
    path: Path

    @property
    def label(self) -> str:
        return f"{TOOL_LABELS[self.tool]} ({self.scope})"

    @property
    def is_directory(self) -> bool:
        """Skills are directories; agents are single files."""
        return self.kind == "skill"

    def exists(self) -> bool:
        return os.path.lexists(self.path)


def resolve(kind: str, tool: str, scope: str, name: str, project_root: Path) -> Target:
    """Map (kind, tool, scope, name) onto the tool's documented discovery path."""
    if kind not in KINDS:
        raise TargetError(f"unknown kind {kind!r}; expected one of {', '.join(KINDS)}")
    if scope not in SCOPES:
        raise TargetError(f"unknown scope {scope!r}; expected one of {', '.join(SCOPES)}")
    validate_name(name)

    root = _tool_root(tool, scope, project_root)
    if kind == "skill":
        path = root / "skills" / name
    elif tool == "claude":
        path = root / "agents" / f"{name}.md"
    else:
        path = root / "agents" / f"{name}.toml"
    return Target(tool=tool, scope=scope, kind=kind, name=name, path=path)


def resolve_many(
    kind: str, tools: list[str], scope: str, name: str, project_root: Path
) -> list[Target]:
    seen: list[Target] = []
    for tool in dict.fromkeys(tools):
        seen.append(resolve(kind, tool, scope, name, project_root))
    return seen


def find_project_root(start: Path | None = None) -> Path:
    """Walk up to the nearest git repository root, else use the start directory."""
    current = (start or Path.cwd()).resolve()
    for candidate in (current, *current.parents):
        if (candidate / ".git").exists():
            return candidate
    return current
