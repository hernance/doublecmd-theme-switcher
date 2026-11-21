# CLAUDE.md

Instructions for coding agents working in this repository.

- All repository artifacts are written in English: code, comments, docstrings, docs,
  UI strings, log/error messages and commit messages. This holds regardless of the
  language used in the conversation.
- Never run the tool against the live Double Commander configuration during development
  (`dc_theme_phoenix.sh`, `dc_theme_apply.py --apply`, the picker UI, quitting or opening
  Double Commander, writing to `~/Library/Preferences/doublecmd`) unless the owner asks for it.
- Verify changes statically (`python3 -m py_compile`, `bash -n`, `swiftc -typecheck -parse-as-library`).
