#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
validate_glsl.py — offline GLSL validation for Zephyr / Photon-style shaderpacks

Why this exists
---------------
Iris only reports GLSL errors after the game starts. This tool drives a real
OpenGL context (via moderngl + PyOpenGL) to compile every shader *entry point*
of a pack locally, resolving `#include` the same way Iris/OptiFine does and
injecting the macros Iris normally provides (MC_VERSION, IS_IRIS, ...).

Usage
-----
    <venv>\\Scripts\\python.exe tools\\validate_glsl.py
    <venv>\\Scripts\\python.exe tools\\validate_glsl.py --only composite14 final
    <venv>\\Scripts\\python.exe tools\\validate_glsl.py --stage fsh --verbose

Dependencies (installed once, in the project lab venv):
    pip install moderngl PyOpenGL

Exit code 0 = every entry point compiled. Non-zero = at least one failure;
errors are printed with file/line and the full driver log.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import moderngl
    from OpenGL import GL
except ImportError as exc:  # pragma: no cover - environment problem
    sys.exit(
        "Missing dependency: %s\nInstall with: pip install moderngl PyOpenGL" % exc
    )


# ---------------------------------------------------------------------------
#   Iris-provided macros
# ---------------------------------------------------------------------------
# Iris (and OptiFine) prepend a large set of defines/uniforms to every program.
# We only need the ones Photon/Zephyr use inside #if expressions.
IRIS_DEFINES = {
    "MC_VERSION": "12101",
    "MC_GL_VERSION": "460",
    "MC_GLSL_VERSION": "460",
    "MC_RENDER_QUALITY": "1.0",
    "MC_HANDHELD": "0",
    "MC_HAND_DEPTH": "0.125",
    "MC_ANISOTROPIC_FILTERING": "0",
    "MC_MIPMAP": "1",
    "MC_NORMAL_MAP": "0",
    "MC_SPECULAR_MAP": "0",
    "MC_SHADOW_QUALITY": "1",
    "MC_RENDER_STAGE_NONE": "0",
    "MC_RENDER_STAGE_SKY": "1",
    "MC_RENDER_STAGE_SUNSET": "2",
    "MC_RENDER_STAGE_CUSTOM_SKY": "3",
    "MC_RENDER_STAGE_SUN": "4",
    "MC_RENDER_STAGE_MOON": "5",
    "MC_RENDER_STAGE_STARS": "6",
    "MC_RENDER_STAGE_VOID": "7",
    "MC_RENDER_STAGE_TERRAIN_SOLID": "8",
    "MC_RENDER_STAGE_TERRAIN_CUTOUT": "9",
    "MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED": "10",
    "MC_RENDER_STAGE_ENTITIES": "11",
    "MC_RENDER_STAGE_BLOCK_ENTITIES": "12",
    "MC_RENDER_STAGE_DESTROY": "13",
    "MC_RENDER_STAGE_OUTLINE": "14",
    "MC_RENDER_STAGE_DEBUG": "15",
    "MC_RENDER_STAGE_HAND_SOLID": "16",
    "MC_RENDER_STAGE_TERRAIN_TRANSLUCENT": "17",
    "MC_RENDER_STAGE_TRIPWIRE": "18",
    "MC_RENDER_STAGE_PARTICLES": "19",
    "MC_RENDER_STAGE_CLOUDS": "20",
    "MC_RENDER_STAGE_RAIN_SNOW": "21",
    "MC_RENDER_STAGE_WORLD_BORDER": "22",
    "MC_RENDER_STAGE_HAND_TRANSLUCENT": "23",
    "MC_OS_WINDOWS": None,
    "MC_GL_VENDOR_NVIDIA": None,
    "MC_GL_RENDERER_NVIDIA": None,
    "IS_IRIS": None,
    "IRIS_VERSION": "1.8.8",
    "IRIS_VERSION_MAJOR": "1",
    "IRIS_VERSION_MINOR": "8",
    "IRIS_VERSION_PATCH": "8",
}

SHADER_STAGE_EXT = {
    "vsh": GL.GL_VERTEX_SHADER,
    "fsh": GL.GL_FRAGMENT_SHADER,
    "gsh": GL.GL_GEOMETRY_SHADER,
    "csh": GL.GL_COMPUTE_SHADER,
}

# Wrapper programs live in shaders/world0, shaders/world-1, shaders/world1 and
# (optionally) the shaders root. Every other .vsh/.fsh is an include fragment.
DIMENSION_DIRS = ("world0", "world-1", "world1")


@dataclass
class IncludeError(Exception):
    path: str
    line: int


@dataclass
class Preprocessor:
    """A tiny subset of the C preprocessor: enough to resolve #include by
    evaluating the surrounding #if/#ifdef structure."""

    root: Path
    defines: dict[str, str | None] = field(default_factory=dict)
    seen_includes: set[str] = field(default_factory=set)
    warnings: list[str] = field(default_factory=list)

    # -- conditionals -----------------------------------------------------
    def is_defined(self, name: str) -> bool:
        return name in self.defines

    def _expand_macros(self, text: str, depth: int = 0) -> str:
        """Recursively substitute object-like macros (GLSL expands them too)."""
        if depth > 16:
            return text

        def repl(match: re.Match) -> str:
            name = match.group(0)
            value = self.defines.get(name)
            if value is None:
                return name
            return value

        expanded = re.sub(r"[A-Za-z_]\w*", repl, text)
        if expanded != text:
            return self._expand_macros(expanded, depth + 1)
        return expanded

    def eval_condition(self, expr: str, where: str) -> bool:
        expr = expr.strip()
        if expr in ("", "0"):
            return False
        if expr == "1":
            return True

        def defined_sub(match: re.Match) -> str:
            return "1" if self.is_defined(match.group(1)) else "0"

        text = re.sub(r"defined\s*\(\s*(\w+)\s*\)", defined_sub, expr)
        text = re.sub(r"defined\s+(\w+)", defined_sub, text)
        text = self._expand_macros(text)

        def ident_sub(match: re.Match) -> str:
            name = match.group(0)
            if name in ("and", "or", "not"):
                return name
            value = self.defines.get(name)
            if value is None:
                return "0"
            value = value.strip()
            m = re.match(r"^([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)[uUlLfF]*$", value)
            if m:
                return m.group(1)
            return "0"  # unknown object-like macro: GLSL treats it as 0

        text = re.sub(r"[A-Za-z_]\w*", ident_sub, text)
        text = text.replace("&&", " and ").replace("||", " or ")
        text = re.sub(r"!(?!=)", " not ", text)

        try:
            return bool(eval(text, {"__builtins__": {}}, {}))  # noqa: S307
        except Exception:
            self.warnings.append(f"could not evaluate condition '{expr}' at {where}")
            return False

    # -- includes ---------------------------------------------------------
    def resolve_include(self, spec: str, where: str, base_dir: Path) -> Path | None:
        spec = spec.strip().strip('"').strip("<>")
        candidates = []
        if spec.startswith("/"):
            candidates.append(self.root / spec.lstrip("/"))
        else:
            # relative to the including file first, then common Iris roots
            candidates.append(base_dir / spec)
            candidates.append(self.root / spec)
            candidates.append(self.root / "program" / spec)
            candidates.append(self.root / "include" / spec)
        for candidate in candidates:
            if candidate.is_file():
                return candidate
        self.warnings.append(f"missing include '{spec}' at {where}")
        return None

    def process(self, path: Path) -> str:
        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.split("\n")
        out: list[str] = []
        # stack of (outer_active, this_active, branch_taken)
        stack: list[list[bool]] = []
        active = True

        for number, raw in enumerate(lines, 1):
            stripped = raw.lstrip()
            if not stripped.startswith("#"):
                out.append(raw)
                continue

            directive = re.match(r"#\s*(\w+)\s*(.*)$", stripped)
            if not directive:
                out.append(raw)
                continue

            kind, rest = directive.group(1), directive.group(2).strip()
            where = f"{path.name}:{number}"

            if kind in ("if", "ifdef", "ifndef"):
                outer = active
                if outer:
                    if kind == "if":
                        active = self.eval_condition(rest, where)
                    elif kind == "ifdef":
                        active = self.is_defined(rest.split()[0]) if rest else False
                    else:
                        active = not self.is_defined(rest.split()[0]) if rest else False
                else:
                    active = False
                stack.append([outer, active, active])
                out.append(raw)
                continue

            if kind in ("elif", "else"):
                if not stack:
                    self.warnings.append(f"unbalanced #{kind} at {where}")
                    out.append(raw)
                    continue
                outer, _this, taken = stack[-1]
                if kind == "else":
                    now = outer and not taken
                else:
                    now = outer and not taken and self.eval_condition(rest, where)
                stack[-1] = [outer, now, taken or now]
                active = now
                out.append(raw)
                continue

            if kind == "endif":
                if stack:
                    outer, _this, _taken = stack.pop()
                    active = outer
                else:
                    self.warnings.append(f"unbalanced #endif at {where}")
                out.append(raw)
                continue

            if not active:
                out.append(raw)
                continue

            if kind == "include":
                target = self.resolve_include(rest, where, path.parent)
                if target is None:
                    out.append(raw)
                    continue
                text_included = self.process(target)
                out.append(f"// ---- begin {target.relative_to(self.root)} ----")
                out.append(self._apply_local_defines(target, text_included))
                out.append(f"// ---- end {target.relative_to(self.root)} ----")
                continue

            if kind == "define":
                m = re.match(r"([A-Za-z_]\w*)(\([^)]*\))?\s*(.*)$", rest)
                if m:
                    name = m.group(1)
                    value = m.group(3)
                    value = re.sub(r"//.*$", "", value).strip()
                    if m.group(2):  # function-like macro: remember it exists
                        self.defines[name] = None
                    else:
                        self.defines[name] = value if value else None
                out.append(raw)
                continue

            if kind == "undef":
                name = rest.split()[0] if rest else ""
                self.defines.pop(name, None)
                out.append(raw)
                continue

            out.append(raw)

        return "\n".join(out)

    def _apply_local_defines(self, path: Path, text: str) -> str:
        # defines inside the included file were recorded while processing it,
        # nothing extra to do here (kept for clarity / future use)
        return text


def inject_iris_defines(source: str, defines: dict[str, str | None]) -> str:
    """Insert the Iris-provided defines after the #version directive."""
    prelude = []
    for name, value in defines.items():
        if value is None:
            prelude.append(f"#define {name}")
        else:
            prelude.append(f"#define {name} {value}")
    prelude.append("")

    lines = source.split("\n")
    for index, line in enumerate(lines):
        if line.lstrip().startswith("#version"):
            return "\n".join(lines[: index + 1] + prelude + lines[index + 1 :])
    return "\n".join(prelude + lines)


def make_source(pack: Path, wrapper: Path, defines: dict[str, str | None]) -> str:
    pre = Preprocessor(root=pack / "shaders", defines=dict(defines))
    source = pre.process(wrapper)
    # Only the macros Iris itself injects go into the source. Settings defines
    # must stay out: injecting e.g. SETTINGS_INCLUDED would disable the guard
    # in settings.glsl and make every const look undefined.
    source = inject_iris_defines(source, IRIS_DEFINES)
    return source


def compile_stage(stage: str, source: str) -> tuple[bool, str]:
    shader = GL.glCreateShader(SHADER_STAGE_EXT[stage])
    GL.glShaderSource(shader, source)
    GL.glCompileShader(shader)
    ok = bool(GL.glGetShaderiv(shader, GL.GL_COMPILE_STATUS))
    log = GL.glGetShaderInfoLog(shader)
    if isinstance(log, bytes):
        log = log.decode("utf-8", "replace")
    GL.glDeleteShader(shader)
    return ok, log or ""


def read_enabled_conditions(pack: Path) -> dict[str, str]:
    """program.<dim>/<name>.enabled = SETTING  (or !SETTING) in shaders.properties"""
    out: dict[str, str] = {}
    props = pack / "shaders" / "shaders.properties"
    if not props.is_file():
        return out
    for line in props.read_text(encoding="utf-8", errors="replace").split("\n"):
        match = re.match(r"\s*program\.(\S+)\.enabled\s*=\s*(\S+)", line)
        if match:
            out[match.group(1)] = match.group(2)
    return out


def program_is_enabled(
    wrapper: Path, pack: Path, conditions: dict[str, str], defines: dict[str, str | None]
) -> bool | None:
    """Evaluate `program.<dim>/<name>.enabled = [not_]SETTING` against defines."""
    rel = wrapper.relative_to(pack / "shaders").as_posix()  # world0/composite3.fsh
    name = rel.rsplit(".", 1)[0]
    condition = conditions.get(name)
    if condition is None:
        return None

    match = re.match(r"^(!?)([A-Za-z_]\w*)$", condition.strip())
    if not match:
        return None
    negated, setting = bool(match.group(1)), match.group(2)
    enabled = setting in defines
    return (not enabled) if negated else enabled


def find_wrappers(pack: Path) -> list[Path]:
    shaders = pack / "shaders"
    wrappers: list[Path] = []
    for directory in DIMENSION_DIRS:
        base = shaders / directory
        if base.is_dir():
            wrappers.extend(sorted(base.glob("*.vsh")))
            wrappers.extend(sorted(base.glob("*.fsh")))
            wrappers.extend(sorted(base.glob("*.csh")))
    # packs without dimension folders (root-level programs)
    if not wrappers:
        wrappers.extend(sorted(shaders.glob("*.vsh")))
        wrappers.extend(sorted(shaders.glob("*.fsh")))
    return wrappers


def main(argv: list[str]) -> int:
    default_pack = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description="Compile shaderpack entry points offline")
    parser.add_argument("--pack", type=Path, default=default_pack, help="shaderpack root (contains shaders/)")
    parser.add_argument("--only", nargs="*", default=None, help="substring filter for program names")
    parser.add_argument("--verbose", action="store_true", help="print the preprocessed source of failures")
    parser.add_argument("--force-core", action="store_true", help="rewrite '#version 400 compatibility' to core")
    parser.add_argument("--list", action="store_true", help="list entry points and exit")
    args = parser.parse_args(argv)

    pack: Path = args.pack
    if not (pack / "shaders").is_dir():
        return f"not a shaderpack: {pack}"

    wrappers = find_wrappers(pack)
    conditions = read_enabled_conditions(pack)
    if args.only:
        wrappers = [w for w in wrappers if any(token in w.name for token in args.only)]
    if args.list:
        for wrapper in wrappers:
            print(wrapper.relative_to(pack))
        return 0
    if not wrappers:
        return "no shader entry points found"

    # Build the base define set once (settings.glsl is parsed by the
    # preprocessor as part of every program, but condition evaluation inside
    # the first include needs it available up front).
    defines = dict(IRIS_DEFINES)

    # Parse settings.glsl once so pass-enable conditions and #if expressions
    # can be evaluated before the per-program preprocessing starts.
    boot = Preprocessor(root=pack / "shaders", defines=dict(defines))
    boot.process(pack / "shaders" / "settings.glsl")
    defines = boot.defines

    moderngl.create_standalone_context(require=430)
    print(f"GL: {GL.glGetString(GL.GL_VERSION).decode()} / {GL.glGetString(GL.GL_RENDERER).decode()}")
    print(f"pack: {pack}")

    failures = 0
    skipped = 0
    total = 0
    stage_cache: dict[Path, tuple[bool, str, str]] = {}

    for wrapper in wrappers:
        stage = wrapper.suffix.lstrip(".")
        if stage not in SHADER_STAGE_EXT:
            continue

        # Programs for mods that are not installed cannot be validated here
        # (Distant Horizons injects its own GLSL API).
        if wrapper.name.startswith("dh_") and "DISTANT_HORIZONS" not in defines:
            print(f"[skip] {wrapper.relative_to(pack)} (Distant Horizons not installed)")
            skipped += 1
            continue

        # Passes the pack disables through shaders.properties are not compiled
        # by Iris either.
        if program_is_enabled(wrapper, pack, conditions, defines) is False:
            print(f"[skip] {wrapper.relative_to(pack)} (disabled in shaders.properties)")
            skipped += 1
            continue

        total += 1
        try:
            source = make_source(pack, wrapper, defines)
        except IncludeError as exc:
            print(f"[FAIL] {wrapper.relative_to(pack)}: include error {exc}")
            failures += 1
            continue

        if args.force_core:
            source = source.replace("#version 400 compatibility", "#version 400 core")

        ok, log = compile_stage(stage, source)
        if ok:
            print(f"[ ok ] {wrapper.relative_to(pack)}")
        elif "#error" in log:
            # The pack disables this program via its own #error guard
            # (e.g. DOF pass when DOF is off). Iris never compiles it either.
            print(f"[skip] {wrapper.relative_to(pack)}")
            skipped += 1
        else:
            failures += 1
            print(f"[FAIL] {wrapper.relative_to(pack)}")
            for line in log.rstrip().split("\n")[:40]:
                print("       " + line)
            if args.verbose:
                debug_path = pack / f"__preprocessed_{wrapper.name}.txt"
                debug_path.write_text(source, encoding="utf-8")
                print(f"       preprocessed source: {debug_path.name}")

    print(f"\n{total - failures - skipped}/{total - skipped} compiled, {skipped} skipped (disabled by pack), {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
