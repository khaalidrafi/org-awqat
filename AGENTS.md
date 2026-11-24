# AGENTS.md — org-awqat

Islamic times packages (Hijri dates, Salah, Jama'ah, and the two Org
integrations: org-awqat's conversion front door + org-hijri's native
Hijri stamps).  Plain Elisp, Emacs 27.1+, org 9.3+.

## Laws

- GPL-3.0-or-later; keep headers and SPDX tags.
- Pure Elisp: no external binaries, no network, no patching other
  packages.  PKG-specific Android patches live in THAT package's repo
  (emacshell code in emacshell, elwidget host changes in elwidget).
- Widgets never reimplement engine math: they call org-awqat's own
  functions.
- elwidget stays a soft dependency of org-awqat-widget.el: byte-compile
  and tests must pass without it.
- org-hijri.el is self-contained apart from Org itself; its Maghrib
  sources are optional soft dependencies resolved in order
  (org-awqat -> awqat -> solar.el), and every one of them must be
  absent-safe (nil, never an error).
- `make compile` treats warnings as errors; `make test` is offline ERT.
- Do not quote user prompts in commits, docs or releases; describe the
  change, not the conversation.
- Commits: authored as the model identity MODEL <model@provider>
  (e.g. GLM 5.3 <glm-5.3@z.ai>) with Co-authored-by: Khalid Rafi
  <khaalidrafi@gmail.com> -- the canonical owner email, no variants
  (Owner order 2026-11-24).
- Pushes use the Khalid's Slave GitHub App credential helper (never a
  stored PAT, never the plugin).
