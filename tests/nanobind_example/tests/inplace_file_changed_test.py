"""Pre-rebuild test after source_change.patch.

Python change is immediately visible via the editable install.
C++ has been patched but not yet recompiled, so add() still returns a+b.
"""
import nanobind_example
from nanobind_example.example import greeting

assert greeting() == "hello changed", f"greeting() returned {greeting()!r}, expected 'hello changed'"
assert nanobind_example.add(1, 2) == 3, (
    f"add(1, 2) returned {nanobind_example.add(1, 2)!r} — C++ not yet recompiled, should still add"
)
