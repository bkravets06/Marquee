#!/usr/bin/env python3
"""Syntax-check every Swift file in the repository with tree-sitter.

Sessions that run on Linux (or any machine without a Swift toolchain) cannot
compile Marquee, but they can still catch unbalanced braces, stray tokens and
other parse errors before pushing. This script parses each `.swift` file with
the tree-sitter Swift grammar and reports any ERROR or MISSING nodes.

It cannot catch type errors, unresolved identifiers or wrong argument labels;
those still need a real `swift build` / `xcodebuild` on macOS (see CI).

Installation (once):

    python3 -m pip install tree-sitter tree-sitter-swift

Usage:

    python3 scripts/check_syntax.py                 # whole repository
    python3 scripts/check_syntax.py Marquee MarqueeKit/Sources
    python3 scripts/check_syntax.py path/to/File.swift

Exit status is 1 when any file fails to parse, 0 otherwise.
"""

import os
import sys

try:
    from tree_sitter import Language, Parser
    import tree_sitter_swift
except ImportError:
    sys.stderr.write(
        "tree-sitter is not installed. Run:\n"
        "    python3 -m pip install tree-sitter tree-sitter-swift\n"
    )
    sys.exit(2)

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIPPED_DIRS = ("/.build", "/.git", "/DerivedData", "/.swiftpm")

parser = Parser(Language(tree_sitter_swift.language()))
roots = sys.argv[1:] or [REPO_ROOT]

files = []
for root in roots:
    if os.path.isfile(root) and root.endswith(".swift"):
        files.append(root)
        continue
    for directory, _, names in os.walk(root):
        if any(skip in directory for skip in SKIPPED_DIRS):
            continue
        files.extend(os.path.join(directory, name) for name in names if name.endswith(".swift"))


def collect_errors(node, source, out):
    """Depth-first walk collecting ERROR and MISSING nodes with a line snippet."""
    if node.type == "ERROR" or node.is_missing:
        line = node.start_point[0] + 1
        lines = source.splitlines()
        snippet = lines[line - 1].decode(errors="replace").strip()[:100] if line - 1 < len(lines) else ""
        kind = "MISSING " + node.type if node.is_missing else "ERROR"
        out.append((line, kind, snippet))
        return
    for child in node.children:
        collect_errors(child, source, out)


bad = 0
for path in sorted(set(files)):
    with open(path, "rb") as handle:
        source = handle.read()
    tree = parser.parse(source)
    if tree.root_node.has_error:
        problems = []
        collect_errors(tree.root_node, source, problems)
        bad += 1
        print(f"SYNTAX ERROR: {path}")
        for line, kind, snippet in problems[:5]:
            print(f"    line {line}: {kind}: {snippet}")

print(f"checked {len(set(files))} files, {bad} with syntax errors")
sys.exit(1 if bad else 0)
