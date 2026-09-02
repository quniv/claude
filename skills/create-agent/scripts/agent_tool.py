#!/usr/bin/env python3
"""Scaffold and validate a subagent in any supported coding agent's own format.

Standard library only. Run it with a bare `python3`; there is nothing to install.

  python3 agent_tool.py paths    --name NAME [--tool ...] [--scope ...]
  python3 agent_tool.py scaffold --name NAME --description TEXT --body-file FILE [...]
  python3 agent_tool.py validate --name NAME [--tool ...] | --path FILE

One authored role body is rendered natively into each target:

  Claude Code  .claude/agents/<name>.md    YAML frontmatter + Markdown system prompt
  Codex CLI    .codex/agents/<name>.toml   TOML with developer_instructions

Each file is complete on its own. Neither points at the other, and neither
depends on a shared canonical file staying where it is -- a Claude Code subagent
has no mechanism to follow such a pointer, so an adapter would silently do nothing.
"""

from __future__ import annotations

import argparse
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

DESCRIPTION_SOFT_MAX = 1024
PLACEHOLDER_MARKERS = ("[agent-name]", "[role]", "TODO:", "<placeholder>", "XXX:")
CLAUDE_MODELS = ("sonnet", "opus", "haiku", "inherit")


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
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _toml_basic(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _toml_multiline(value: str) -> str:
    """Prefer a literal string so Markdown backslashes survive untouched."""
    body = value.strip("\n")
    if "'''" not in body and not body.endswith("'"):
        return f"'''\n{body}\n'''"
    escaped = body.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    return f'"""\n{escaped}\n"""'


def render_claude_agent(
    name: str, description: str, body: str, model: str, tools: str
) -> str:
    lines = ["---", f"name: {_yaml_scalar(name)}", f"description: {_yaml_scalar(description)}"]
    if tools:
        lines.append(f"tools: {_yaml_scalar(tools)}")
    if model:
        lines.append(f"model: {_yaml_scalar(model)}")
    lines += ["---", "", body.strip(), ""]
    return "\n".join(lines)


def render_codex_agent(
    name: str, description: str, body: str, model: str, effort: str
) -> str:
    lines = [f"name = {_toml_basic(name)}", f"description = {_toml_basic(description)}"]
    if model:
        lines.append(f"model = {_toml_basic(model)}")
    if effort:
        lines.append(f"model_reasoning_effort = {_toml_basic(effort)}")
    lines.append(f"developer_instructions = {_toml_multiline(body)}")
    return "\n".join(lines) + "\n"


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
    for target in resolve_many("agent", args.tools, args.scope, args.name, args.root):
        state = "EXISTS" if target.exists() else "free"
        print(f"{state:6}  {target.label:24}  {target.path}")
    return 0


def cmd_scaffold(args: argparse.Namespace) -> int:
    validate_name(args.name)
    description = args.description.strip()
    if not description:
        raise TargetError(
            "--description must not be empty; it is what a parent agent reads to "
            "decide whether to delegate"
        )
    if len(description) > DESCRIPTION_SOFT_MAX:
        print(
            f"WARNING: description is {len(description)} characters "
            f"(soft limit {DESCRIPTION_SOFT_MAX}); consider trimming",
            file=sys.stderr,
        )

    body = Path(args.body_file).read_text(encoding="utf-8").strip()
    if not body:
        raise TargetError(f"--body-file {args.body_file} is empty")

    if args.claude_model and args.claude_model not in CLAUDE_MODELS:
        raise TargetError(
            f"--claude-model {args.claude_model!r} is not one of {', '.join(CLAUDE_MODELS)}"
        )

    targets = resolve_many("agent", args.tools, args.scope, args.name, args.root)
    for target in targets:
        guard_destination(target, args.force)

    for target in targets:
        target.path.parent.mkdir(parents=True, exist_ok=True)
        if target.tool == "claude":
            content = render_claude_agent(
                args.name, description, body, args.claude_model, args.claude_tools
            )
        else:
            content = render_codex_agent(
                args.name, description, body, args.codex_model, args.codex_effort
            )
        target.path.write_text(content, encoding="utf-8")
        print(f"WROTE {target.path}")
    return 0


def _parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
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
        if line[:1].isspace() and key:
            fields[key] = f"{fields[key]} {line.strip()}".strip()
            continue
        if ":" not in line:
            raise TargetError(f"malformed frontmatter line: {line!r}")
        key, _, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        fields[key] = value
    return fields, "\n".join(lines[closing + 1 :]).strip()


def _validate_claude(path: Path, expected: str | None) -> list[str]:
    problems: list[str] = []
    text = path.read_text(encoding="utf-8")
    try:
        fields, body = _parse_frontmatter(text)
    except TargetError as error:
        return [f"{path}: {error}"]

    name = fields.get("name", "")
    if not name:
        problems.append(f"{path}: frontmatter has no 'name'")
    else:
        try:
            validate_name(name)
        except TargetError as error:
            problems.append(f"{path}: {error}")
        if name != path.stem:
            problems.append(f"{path}: frontmatter name {name!r} != filename {path.stem!r}")
        if expected and name != expected:
            problems.append(f"{path}: frontmatter name {name!r} != expected {expected!r}")

    if not fields.get("description"):
        problems.append(f"{path}: no 'description'; nothing will ever delegate to this agent")
    model = fields.get("model", "")
    if model and model not in CLAUDE_MODELS:
        problems.append(f"{path}: model {model!r} not in {', '.join(CLAUDE_MODELS)}")
    if not body:
        problems.append(f"{path}: body is empty; the agent would have no system prompt")
    return problems


def _validate_codex(path: Path, expected: str | None) -> list[str]:
    problems: list[str] = []
    text = path.read_text(encoding="utf-8")
    try:
        import tomllib
    except ModuleNotFoundError:  # Python < 3.11
        print(f"NOTE  {path}: tomllib unavailable, doing a text-only check", file=sys.stderr)
        for key in ("name", "description", "developer_instructions"):
            if f"{key} =" not in text:
                problems.append(f"{path}: missing '{key}'")
        return problems

    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        return [f"{path}: invalid TOML: {error}"]

    name = data.get("name", "")
    if not name:
        problems.append(f"{path}: no 'name'")
    else:
        try:
            validate_name(str(name))
        except TargetError as error:
            problems.append(f"{path}: {error}")
        if name != path.stem:
            problems.append(f"{path}: name {name!r} != filename {path.stem!r}")
        if expected and name != expected:
            problems.append(f"{path}: name {name!r} != expected {expected!r}")

    if not data.get("description"):
        problems.append(f"{path}: no 'description'; Codex needs it for spawn guidance")
    instructions = str(data.get("developer_instructions", "")).strip()
    if not instructions:
        problems.append(
            f"{path}: no 'developer_instructions'; Codex warns at startup and the role is empty"
        )
    elif len(instructions) < 40:
        problems.append(
            f"{path}: developer_instructions is {len(instructions)} chars -- too thin to be a role"
        )
    return problems


def _validate_one(path: Path, expected: str | None) -> list[str]:
    if not path.is_file():
        return [f"{path}: not a file"]
    problems = (_validate_claude if path.suffix == ".md" else _validate_codex)(path, expected)
    text = path.read_text(encoding="utf-8")
    for marker in PLACEHOLDER_MARKERS:
        if marker in text:
            problems.append(f"{path}: unreplaced placeholder {marker!r}")
    return problems


def cmd_validate(args: argparse.Namespace) -> int:
    if args.path:
        candidates = [Path(args.path).resolve()]
        expected = None
    else:
        if not args.name:
            raise TargetError("validate needs --path or --name")
        targets = resolve_many("agent", args.tools, args.scope, args.name, args.root)
        candidates = [t.path for t in targets if t.exists()]
        expected = args.name
        if not candidates:
            raise TargetError(f"no installed agent named {args.name!r} in the selected targets")

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

    p_paths = sub.add_parser("paths", help="Show where the agent would be written.")
    p_paths.add_argument("--name", required=True)
    add_common(p_paths)
    p_paths.set_defaults(func=cmd_paths)

    p_new = sub.add_parser("scaffold", help="Render the role into every selected target.")
    p_new.add_argument("--name", required=True)
    p_new.add_argument("--description", required=True,
                       help="What the agent owns and when to delegate to it.")
    p_new.add_argument("--body-file", required=True, help="The role instructions, as Markdown.")
    p_new.add_argument("--claude-tools", default="",
                       help="Comma-separated tool allowlist. Omit to inherit every tool.")
    p_new.add_argument("--claude-model", default="",
                       help=f"One of {', '.join(CLAUDE_MODELS)}. Omit to inherit.")
    p_new.add_argument("--codex-model", default="", help="Codex model override. Omit to inherit.")
    p_new.add_argument("--codex-effort", default="", help="Codex model_reasoning_effort override.")
    p_new.add_argument("--force", action="store_true", help="Update an existing agent in place.")
    add_common(p_new)
    p_new.set_defaults(func=cmd_scaffold)

    p_val = sub.add_parser("validate", help="Check format, required fields and placeholders.")
    p_val.add_argument("--name", default="")
    p_val.add_argument("--path", default="", help="Validate one agent file directly.")
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
