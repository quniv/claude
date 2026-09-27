#!/usr/bin/env python3
"""Create safe relative links from an agent package to the workspace skill bank."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path


NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Link canonical workspace skills into an agent package."
    )
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument(
        "--agent",
        required=True,
        type=Path,
        help="Agent directory relative to the workspace, for example agents/reviewer.",
    )
    parser.add_argument(
        "--skill",
        action="append",
        default=[],
        dest="skills",
        help=(
            "Skill-bank directory name. Repeat for multiple skills; omit to "
            "create an empty agent skills directory."
        ),
    )
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def require_name(value: str, label: str) -> None:
    if len(value) > 64 or not NAME_PATTERN.fullmatch(value):
        raise ValueError(
            f"Invalid {label} {value!r}: use 1-64 lowercase letters, digits, "
            "and single hyphens."
        )


def main() -> int:
    args = parse_args()
    workspace = args.workspace.resolve(strict=True)
    agents_root = (workspace / "agents").resolve(strict=True)
    skill_bank = (workspace / "skills").resolve(strict=True)

    if args.agent.is_absolute():
        raise ValueError("--agent must be relative to the workspace")

    agent = (workspace / args.agent).resolve(strict=False)
    if agent.parent != agents_root:
        raise ValueError("--agent must name one direct child of workspace/agents")
    require_name(agent.name, "agent name")

    unique_skills = list(dict.fromkeys(args.skills))
    sources: list[tuple[str, Path]] = []
    for skill_name in unique_skills:
        require_name(skill_name, "skill name")
        source = (skill_bank / skill_name).resolve(strict=True)
        if not source.is_relative_to(skill_bank):
            raise ValueError(f"Skill {skill_name!r} resolves outside the skill bank")
        if not source.is_dir() or not (source / "SKILL.md").is_file():
            raise ValueError(f"Skill {skill_name!r} has no readable SKILL.md")
        sources.append((skill_name, source))

    skills_dir = agent / "skills"
    if not args.dry_run:
        skills_dir.mkdir(parents=True, exist_ok=True)

    if not sources:
        action = "WOULD ENSURE" if args.dry_run else "READY"
        print(f"{action} empty {skills_dir.relative_to(workspace)}")

    for skill_name, source in sources:
        link = skills_dir / skill_name
        relative_target = Path(os.path.relpath(source, start=skills_dir))

        if os.path.lexists(link):
            if not link.is_symlink():
                raise FileExistsError(f"Refusing to replace non-symlink: {link}")
            current_target = (link.parent / os.readlink(link)).resolve(strict=False)
            if current_target != source:
                raise FileExistsError(
                    f"Refusing to retarget {link}: it currently points to "
                    f"{os.readlink(link)}"
                )
            print(f"OK existing {link.relative_to(workspace)} -> {os.readlink(link)}")
            continue

        if args.dry_run:
            print(f"WOULD LINK {link.relative_to(workspace)} -> {relative_target}")
        else:
            link.symlink_to(relative_target, target_is_directory=True)
            print(f"LINKED {link.relative_to(workspace)} -> {relative_target}")

    return 0


def cli() -> int:
    try:
        return main()
    except (ValueError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(cli())
