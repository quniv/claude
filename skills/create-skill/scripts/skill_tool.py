#!/usr/bin/env python3
"""Scaffold and validate an Agent Skill in any supported coding agent's own layout.

Standard library only. Run it with a bare `python3`; there is nothing to install.

  python3 skill_tool.py paths    --name NAME [--tool ...] [--scope ...]
  python3 skill_tool.py scaffold --name NAME --description TEXT --body-file FILE [...]
  python3 skill_tool.py validate --name NAME [--tool ...] | --path DIR

`scaffold` renders one authored body into a complete, self-contained skill in
every selected target. The targets do not reference each other and no target
depends on this repository staying where it is.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from agent_targets import (  # noqa: E402
    SCOPES,
    TOOLS,
    Target,
    TargetError,
    find_project_root,
    resolve_many,
    validate_name,
)

RESOURCE_DIRS = ("scripts", "references", "assets")
DESCRIPTION_SOFT_MAX = 1024
PLACEHOLDER_MARKERS = ("[agent-name]", "[skill-name]", "TODO:", "<placeholder>", "XXX:")
# Build artefacts and VCS noise must never be copied into an installed skill.
COPY_EXCLUDE = ("__pycache__", "*.py[cod]", ".git", ".DS_Store")

# Characters that force a plain YAML scalar to be quoted.
def _yaml_scalar(value: str) -> str:
    needs_quotes = (
        not value
        or value != value.strip()
        or ": " in value
        or " #" in value
        or value[0] in "&*!|>%@`{}[],\"'#-?:"
        or value.endswith(":")
    )
    if not needs_quotes:
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """Extract simple `key: value` frontmatter without a YAML dependency.

    Returns (fields, body). Raises TargetError when the block is missing or unterminated.
    """
    if not text.startswith("---"):
        raise TargetError("missing YAML frontmatter: file must start with '---'")
    lines = text.splitlines()
    closing = next((i for i, line in enumerate(lines[1:], start=1) if line.strip() == "---"), None)
    if closing is None:
        raise TargetError("unterminated YAML frontmatter: no closing '---'")

    fields: dict[str, str] = {}
    key: str | None = None
    for line in lines[1:closing]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[:1].isspace() and key:  # continuation of a folded value
            fields[key] = f"{fields[key]} {line.strip()}".strip()
            continue
        if ":" not in line:
            raise TargetError(f"malformed frontmatter line: {line!r}")
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        fields[key] = value
    return fields, "\n".join(lines[closing + 1 :]).strip()


def render_skill_md(name: str, description: str, body: str, extra: dict[str, str]) -> str:
    lines = ["---", f"name: {_yaml_scalar(name)}", f"description: {_yaml_scalar(description)}"]
    for key, value in extra.items():
        lines.append(f"{key}: {_yaml_scalar(value)}")
    lines += ["---", "", body.strip(), ""]
    return "\n".join(lines)


def render_openai_yaml(display_name: str, short_description: str, default_prompt: str) -> str:
    """Codex-only UI metadata. Claude Code has no equivalent and needs no file."""
    return (
        "interface:\n"
        f'  display_name: "{display_name}"\n'
        f'  short_description: "{short_description}"\n'
        f'  default_prompt: "{default_prompt}"\n'
    )


def guard_destination(target: Target, force: bool) -> None:
    if not target.exists():
        return
    if not force:
        raise TargetError(
            f"{target.path} already exists; pass --force to update it in place, "
            "or choose a different name"
        )
    if target.path.is_symlink():
        raise TargetError(
            f"refusing to write through the symlink at {target.path} "
            f"(-> {target.path.readlink()}); remove or retarget it deliberately"
        )


def cmd_paths(args: argparse.Namespace) -> int:
    targets = resolve_many("skill", args.tools, args.scope, args.name, args.root)
    for target in targets:
        state = "EXISTS" if target.exists() else "free"
        print(f"{state:6}  {target.label:24}  {target.path}")
    return 0


def cmd_scaffold(args: argparse.Namespace) -> int:
    validate_name(args.name)
    description = args.description.strip()
    if not description:
        raise TargetError("--description must not be empty; it is the only trigger signal")
    if len(description) > DESCRIPTION_SOFT_MAX:
        print(
            f"WARNING: description is {len(description)} characters "
            f"(soft limit {DESCRIPTION_SOFT_MAX}); consider trimming",
            file=sys.stderr,
        )

    body = Path(args.body_file).read_text(encoding="utf-8")
    if not body.strip():
        raise TargetError(f"--body-file {args.body_file} is empty")

    extra = {}
    if args.allowed_tools:
        extra["allowed-tools"] = args.allowed_tools

    targets = resolve_many("skill", args.tools, args.scope, args.name, args.root)
    for target in targets:
        guard_destination(target, args.force)

    resources = [r for r in (args.resources or "").split(",") if r]
    for resource in resources:
        if resource not in RESOURCE_DIRS:
            raise TargetError(
                f"unknown resource {resource!r}; expected any of {', '.join(RESOURCE_DIRS)}"
            )

    written: list[str] = []
    for target in targets:
        target.path.mkdir(parents=True, exist_ok=True)
        skill_md = target.path / "SKILL.md"
        skill_md.write_text(render_skill_md(args.name, description, body, extra), encoding="utf-8")
        written.append(str(skill_md))

        for resource in resources:
            (target.path / resource).mkdir(exist_ok=True)

        # Codex reads agents/openai.yaml for its skill picker; Claude Code ignores it.
        if target.tool == "codex" and args.display_name:
            meta_dir = target.path / "agents"
            meta_dir.mkdir(exist_ok=True)
            meta = meta_dir / "openai.yaml"
            meta.write_text(
                render_openai_yaml(
                    args.display_name,
                    args.short_description or description[:64],
                    args.default_prompt or f"Use ${args.name} to ...",
                ),
                encoding="utf-8",
            )
            written.append(str(meta))

        if args.copy_from:
            source = Path(args.copy_from)
            for resource in resources:
                candidate = source / resource
                if candidate.is_dir():
                    shutil.copytree(
                        candidate,
                        target.path / resource,
                        dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns(*COPY_EXCLUDE),
                    )

    for path in written:
        print(f"WROTE {path}")
    return 0


def _validate_one(path: Path, expected_name: str | None) -> list[str]:
    problems: list[str] = []
    skill_md = path / "SKILL.md"
    if not skill_md.is_file():
        return [f"{path}: no SKILL.md"]

    text = skill_md.read_text(encoding="utf-8")
    try:
        fields, body = parse_frontmatter(text)
    except TargetError as error:
        return [f"{skill_md}: {error}"]

    name = fields.get("name", "")
    if not name:
        problems.append(f"{skill_md}: frontmatter has no 'name'")
    else:
        try:
            validate_name(name)
        except TargetError as error:
            problems.append(f"{skill_md}: {error}")
        if name != path.name:
            problems.append(
                f"{skill_md}: frontmatter name {name!r} != directory name {path.name!r}"
            )
        if expected_name and name != expected_name:
            problems.append(f"{skill_md}: frontmatter name {name!r} != expected {expected_name!r}")

    description = fields.get("description", "")
    if not description:
        problems.append(f"{skill_md}: frontmatter has no 'description' (nothing can trigger it)")
    elif len(description) > DESCRIPTION_SOFT_MAX:
        problems.append(
            f"{skill_md}: description is {len(description)} chars (> {DESCRIPTION_SOFT_MAX})"
        )

    if not body:
        problems.append(f"{skill_md}: body is empty")

    for marker in PLACEHOLDER_MARKERS:
        if marker in text:
            problems.append(f"{skill_md}: unreplaced placeholder {marker!r}")

    for resource in RESOURCE_DIRS:
        directory = path / resource
        if directory.is_dir() and not any(directory.iterdir()):
            problems.append(f"{directory}: empty resource directory; remove it or fill it")

    return problems


def cmd_validate(args: argparse.Namespace) -> int:
    if args.path:
        candidates = [Path(args.path).resolve()]
        expected = None
    else:
        if not args.name:
            raise TargetError("validate needs --path or --name")
        targets = resolve_many("skill", args.tools, args.scope, args.name, args.root)
        candidates = [t.path for t in targets if t.exists()]
        expected = args.name
        if not candidates:
            raise TargetError(f"no installed skill named {args.name!r} in the selected targets")

    problems: list[str] = []
    for candidate in candidates:
        found = _validate_one(candidate, expected)
        problems.extend(found)
        print(f"{'FAIL' if found else 'OK  '}  {candidate}")

    for problem in problems:
        print(f"  - {problem}", file=sys.stderr)
    return 1 if problems else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    def add_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--tool", action="append", dest="tools", choices=TOOLS,
                       help="Repeat per target agent. Default: every supported agent.")
        p.add_argument("--scope", choices=SCOPES, default="project",
                       help="project = this repository, user = your home directory.")
        p.add_argument("--root", type=Path, default=None,
                       help="Project root. Default: nearest git root above the cwd.")

    p_paths = sub.add_parser("paths", help="Show where the skill would be written.")
    p_paths.add_argument("--name", required=True)
    add_common(p_paths)
    p_paths.set_defaults(func=cmd_paths)

    p_new = sub.add_parser("scaffold", help="Write the skill into every selected target.")
    p_new.add_argument("--name", required=True)
    p_new.add_argument("--description", required=True)
    p_new.add_argument("--body-file", required=True, help="Markdown body, without frontmatter.")
    p_new.add_argument("--resources", default="", help="Comma-separated: scripts,references,assets")
    p_new.add_argument("--copy-from", default="", help="Directory to copy resource contents from.")
    p_new.add_argument("--allowed-tools", default="", help="Optional allowed-tools frontmatter.")
    p_new.add_argument("--display-name", default="", help="Codex picker title.")
    p_new.add_argument("--short-description", default="", help="Codex picker subtitle.")
    p_new.add_argument("--default-prompt", default="", help="Codex picker example prompt.")
    p_new.add_argument("--force", action="store_true", help="Update an existing skill in place.")
    add_common(p_new)
    p_new.set_defaults(func=cmd_scaffold)

    p_val = sub.add_parser("validate", help="Check structure, frontmatter and placeholders.")
    p_val.add_argument("--name", default="")
    p_val.add_argument("--path", default="", help="Validate one skill directory directly.")
    add_common(p_val)
    p_val.set_defaults(func=cmd_validate)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    args.tools = args.tools or list(TOOLS)
    args.root = (args.root or find_project_root()).resolve()
    return args.func(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except TargetError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
