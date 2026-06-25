"""Post-rebuild test after source_change.patch + cmake --build.

Both the Python change (greeting) and the C++ change (multiply) are now visible.
"""
import nanobind_example
from nanobind_example.example import greeting

assert greeting() == "hello changed", f"greeting() returned {greeting()!r}, expected 'hello changed'"
assert nanobind_example.add(2, 3) == 6, (
    f"add(2, 3) returned {nanobind_example.add(2, 3)!r} — C++ should now multiply after rebuild"
)
