EMACS ?= emacs

# Pure elisp: the solar and calendar math is self-contained, org is a
# built-in, and the widget tests never need a device.  No -Q here, so
# a distribution's site-lisp is still found (same law as the other
# packages in the family).
LOAD = -L .

SRCS = org-awqat.el org-awqat-widget.el org-hijri.el

all: compile

compile:
	$(EMACS) --batch $(LOAD) --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile $(SRCS)

test: compile
	$(EMACS) --batch $(LOAD) -l tests/test.el -l tests/test-hijri.el \
  -f ert-run-tests-batch-and-exit

clean:
	rm -f $(SRCS:.el=.elc) tests/*.elc

.PHONY: all compile test clean
