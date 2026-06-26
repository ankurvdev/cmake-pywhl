"""Run after patches/file_add.patch; verifies the new module is importable via the editable install."""
from nanobind_example.example_added import new_greeting

assert new_greeting() == "hello new", f"new_greeting() returned {new_greeting()!r}, expected 'hello new'"
