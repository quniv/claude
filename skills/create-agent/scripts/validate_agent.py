#!/usr/bin/env python3
"""Validate a dual-format workspace agent and its linked skills."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tomllib
from pathlib import Path


NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
REQUIRED_HEADINGS = (
    "# Identity",
    "# Mission",
    "# Responsibilities",
    "# Workflow",
    "# Guardrails and escalation",
    "# Output contract",
)
PLACEHOLDERS = (
    "TODO",
    "TBD",
    "[agent-name]",
    "[specific position",
    "[State the owned outcome",
    "[Owned responsibility",
    "[Define artifacts",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate a workspace agent package.")
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--name", required=True)
    return parser.parse_args()


def require_string(data: dict[str, object], field: str) -> str:
    value = data.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Codex adapter field {field!r} must be a non-empty string")
    return value


def main() -> int:
    args = parse_args()
    if len(args.name) > 64 or not NAME_PATTERN.fullmatch(args.name):
        raise ValueError("Invalid agent name")

    workspace = args.workspace.resolve(strict=True)
    agent_dir = workspace / "agents" / args.name
    instructions_path = agent_dir / "INSTRUCTIONS.md"
    skills_dir = agent_dir / "skills"
    adapter_path = workspace / ".codex" / "agents" / f"{args.name}.toml"
    skill_bank = (workspace / "skills").resolve(strict=True)

    instructions = instructions_path.read_text(encoding="utf-8")
    if len(instructions.strip()) < 200:
        raise ValueError(f"Canonical instructions are unexpectedly short: {instructions_path}")
    for heading in REQUIRED_HEADINGS:
        if heading not in instructions:
            raise ValueError(f"Missing required heading {heading!r} in {instructions_path}")
    for placeholder in PLACEHOLDERS:
        if placeholder.lower() in instructions.lower():
            raise ValueError(f"Unresolved placeholder {placeholder!r} in {instructions_path}")

    with adapter_path.open("rb") as handle:
        adapter = tomllib.load(handle)
    if require_string(adapter, "name") != args.name:
        raise ValueError(f"Adapter name does not match {args.name!r}")
    require_string(adapter, "description")
    developer_instructions = require_string(adapter, "developer_instructions")
    expected_reference = f"agents/{args.name}/INSTRUCTIONS.md"
    if expected_reference not in developer_instructions:
        raise ValueError(f"Adapter must reference canonical file {expected_reference}")

    if not skills_dir.is_dir():
        raise ValueError(f"Missing agent skills directory: {skills_dir}")

    links = sorted(skills_dir.iterdir())
    for link in links:
        if not link.is_symlink():
            raise ValueError(f"Agent skill entry is not a symlink: {link}")
        raw_target = os.readlink(link)
        target = (link.parent / raw_target).resolve(strict=True)
        if not target.is_relative_to(skill_bank):
            raise ValueError(f"Agent skill link resolves outside workspace/skills: {link}")
        if not (target / "SKILL.md").is_file():
            raise ValueError(f"Agent skill target has no SKILL.md: {link} -> {raw_target}")

    print(
        f"VALID agent={args.name} skill_links={len(links)} "
        f"canonical={instructions_path.relative_to(workspace)} "
        f"adapter={adapter_path.relative_to(workspace)}"
    )
    return 0


def cli() -> int:
    try:
        return main()
    except (ValueError, OSError, tomllib.TOMLDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(cli())
