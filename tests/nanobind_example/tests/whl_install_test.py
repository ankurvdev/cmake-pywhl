"""Functional test run in both the runtime venv (wheel install) and build venv (editable install)."""
import nanobind_example
from nanobind_example.example import greeting

assert nanobind_example.add(1, 2) == 3, f"add(1, 2) returned {nanobind_example.add(1, 2)!r}, expected 3"
assert greeting() == "hello", f"greeting() returned {greeting()!r}, expected 'hello'"
