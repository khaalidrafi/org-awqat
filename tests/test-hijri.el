;;; test-hijri.el --- ERT tests for org-hijri -*- lexical-binding: t; -*-

;; Run: emacs --batch -L . -l tests/test-hijri.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-hijri)

;;; --- Marker detection (the syntax assumption everything rests on) ---------

(ert-deftest org-hijri-marked-p-accepts-hijri-innards ()
  "The marker word lands in org-ts-regexp0's weekday slot (group 5)."
  (should (org-hijri--marked-p "1446-06-15 Hijri"))
  (should (org-hijri--marked-p "1446-06-15 Hijri 10:00"))
  (should (org-hijri--marked-p "1446-06-15 Hijri +1y")))

(ert-deftest org-hijri-marked-p-rejects-gregorian ()
  (should-not (org-hijri--marked-p "2026-01-01 Thu"))
  (should-not (org-hijri--marked-p "2026-01-01"))
  (should-not (org-hijri--marked-p "")))

(ert-deftest org-hijri-marked-p-rejects-other-words ()
  "Only the configured marker counts, not any weekday-like word."
  (let ((org-hijri-marker "AH"))
    (should (org-hijri--marked-p "1446-06-15 AH"))
    (should-not (org-hijri--marked-p "1446-06-15 Hijri"))))

;;; --- Parsing and formatting ----------------------------------------------

(ert-deftest org-hijri-parse-hijri ()
  (should (equal '(6 15 1446)
                 (org-hijri--parse-hijri "1446-06-15 Hijri")))
  (should-not (org-hijri--parse-hijri "2026-01-01 Thu")))

(ert-deftest org-hijri-parse-hijri-invalid-numerals ()
  "Impossible Islamic dates are rejected, not guessed at."
  (should-not (org-hijri--parse-hijri "1446-13-01 Hijri")) ; month 13
  (should-not (org-hijri--parse-hijri "1446-06-31 Hijri")) ; day 31
  (should-not (org-hijri--parse-hijri "0000-06-15 Hijri"))) ; year 0

(ert-deftest org-hijri-stamp-string-round-trip ()
  "A stamp built by the package parses back to the same date."
  (let* ((h '(6 15 1446))
         (s (org-hijri--stamp-string h)))
    (should (string-equal "<1446-06-15 Hijri>" s))
    (should (equal h (org-hijri--parse-hijri
                      (substring s 1 -1)))))
  (should (string-equal "[1446-06-15 Hijri]"
                        (org-hijri--stamp-string '(6 15 1446) nil nil nil t))))

;;; --- Calendar conversions ---------------------------------------------------

(ert-deftest org-hijri-conversion-round-trip ()
  "Hijri -> Gregorian -> Hijri is the identity over a long window."
  (let ((start (calendar-islamic-to-absolute '(1 1 1440))))
    (dotimes (i 800)
      (let* ((h (calendar-islamic-from-absolute (+ start i)))
             (g (org-hijri-gregorian-from-hijri h))
             (h2 (org-hijri-hijri-from-gregorian g)))
        (should (equal h h2))))))

(ert-deftest org-hijri-known-conversion ()
  "1 Muharram 1447 AH falls on 2025-06-27 (Emacs' tabular civil
calendar; Umm al-Qura says 2025-06-26 -- a known one-day
difference)."
  (should (equal '(6 27 2025)
                 (org-hijri-gregorian-from-hijri '(1 1 1447)))))

;;; --- Maghrib source: org-awqat ---------------------------------------------

(ert-deftest org-hijri-maghrib-from-org-awqat ()
  "org-awqat (same repo) supplies Maghrib as decimal hours."
  (let ((org-awqat-latitude 23.8103)   ; Dhaka
        (org-awqat-longitude 90.4125)
        (org-awqat-timezone-offset 6))
    (let ((m (org-hijri--maghrib-org-awqat '(11 24 2026))))
      (should (numberp m))
      ;; Dhaka sunset is between 17:10 and 18:20 all year.
      (should (> m 17.0))
      (should (< m 18.4)))))

(ert-deftest org-hijri-maghrib-unset-location-falls-through ()
  "Without a location org-awqat errors; the wrapper must return nil."
  (let (org-awqat-latitude org-awqat-longitude)
    (should-not (org-hijri--maghrib-org-awqat '(11 24 2026)))))

;;; --- The parse advice (the heart of the integration) -----------------------

(ert-deftest org-hijri-parse-time-string-advice-converts ()
  "With the mode on, org-parse-time-string reads Hijri numerals as
the Gregorian daytime of that Islamic day; without it, plain."
  (let ((hijri-innards "<1446-06-15 Hijri>"))
    (org-hijri-mode 1)
    (unwind-protect
        (let ((decoded (org-parse-time-string hijri-innards)))
          ;; Same Gregorian day as org-hijri-gregorian-from-hijri.
          (should (equal (list (nth 3 decoded) (nth 4 decoded)
                               (nth 5 decoded))
                         (let ((g (org-hijri-gregorian-from-hijri
                                   '(6 15 1446))))
                           (list (nth 1 g) (nth 0 g) (nth 2 g))))))
      (org-hijri-mode 0))
    ;; Mode off: the numerals are read as a plain (Gregorian) date.
    (let ((decoded (org-parse-time-string hijri-innards)))
      (should (= 1446 (nth 5 decoded))))))

(ert-deftest org-hijri-parse-time-string-advice-ignores-gregorian ()
  "Gregorian stamps parse identically with the mode on and off."
  (let ((plain (org-parse-time-string "<2026-11-24 Tue 10:00>")))
    (org-hijri-mode 1)
    (unwind-protect
        (should (equal plain (org-parse-time-string "<2026-11-24 Tue 10:00>")))
      (org-hijri-mode 0))))

;;; test-hijri.el ends here
