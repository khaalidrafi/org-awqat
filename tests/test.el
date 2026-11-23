;;; test.el --- ERT tests for org-awqat -*- lexical-binding: t; -*-

;; Run: emacs --batch -L . -l tests/test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-awqat)

;;; --- Fixtures ---------------------------------------------------------------

;; Dhaka: 23.8103 N, 90.4125 E, UTC+6.
(defconst org-awqat-test-lat 23.8103)
(defconst org-awqat-test-lng 90.4125)
(defconst org-awqat-test-tz 6)

(defun org-awqat-test--times (date &optional method)
  "Decimal Salah times for DATE with the test location."
  (let ((org-awqat-latitude org-awqat-test-lat)
        (org-awqat-longitude org-awqat-test-lng)
        (org-awqat-timezone-offset org-awqat-test-tz)
        (org-awqat-method (or method 'mwl)))
    (org-awqat-times-decimal date)))

;;; --- Hijri calendar ---------------------------------------------------------

(ert-deftest org-awqat-hijri-round-trip ()
  "Every Gregorian date in a 400-day window survives Greg->Hijri->Greg."
  (let ((start (calendar-absolute-from-gregorian '(1 1 2024))))
    (dotimes (i 400)
      (let* ((g (calendar-gregorian-from-absolute (+ start i)))
             (h (org-awqat-gregorian-to-hijri g))
             (g2 (org-awqat-hijri-to-gregorian h)))
        (should (equal g g2))))))

(ert-deftest org-awqat-hijri-year-length-sane ()
  "A Hijri year is 354-355 days on the arithmetic calendar."
  (let ((days (- (calendar-absolute-from-islamic '(1 1 1448))
                 (calendar-absolute-from-islamic '(1 1 1447)))))
    (should (memq days '(354 355)))))

(ert-deftest org-awqat-hijri-month-names ()
  "12 month names, every one non-empty."
  (should (= 12 (length org-awqat-hijri-month-names)))
  (dotimes (i 12)
    (should (cl-plusp (length (aref org-awqat-hijri-month-names i))))))

(ert-deftest org-awqat-format-hijri ()
  (should (equal "1 Muharram 1447 AH"
                 (org-awqat-format-hijri '(1 1 1447))))
  (should (equal "1447-01-01" (org-awqat-format-hijri-iso '(1 1 1447))))
  (should (equal "12 Jumada al-Ula 1447 AH"
                 (org-awqat-format-hijri '(5 12 1447)))))

(ert-deftest org-awqat-parse-hijri ()
  (should (equal '(6 12 1447) (org-awqat-parse-hijri "1447-06-12")))
  (should (equal '(6 12 1447) (org-awqat-parse-hijri "1447/6/12")))
  (should-error (org-awqat-parse-hijri "not a date"))
  (should-error (org-awqat-parse-hijri "1447-13-01")))

;;; --- Salah computation ------------------------------------------------------

(ert-deftest org-awqat-times-ordered ()
  "Fajr < Sunrise < Dhuhr < Asr < Maghrib < Isha (decimal hours)."
  (dolist (date '((1 1 2026) (4 15 2026) (7 1 2026) (10 10 2026)))
    (let* ((tm (org-awqat-test--times date))
           (v (lambda (p) (cdr (assq p tm)))))
      ;; Dhuhr is the anchor and always exists.
      (should (< 11 (funcall v 'dhuhr) 14))
      (should (< (funcall v 'fajr) (funcall v 'sunrise)))
      (should (< (funcall v 'sunrise) (funcall v 'dhuhr)))
      (should (< (funcall v 'dhuhr) (funcall v 'asr)))
      (should (< (funcall v 'asr) (funcall v 'maghrib)))
      (should (< (funcall v 'maghrib) (funcall v 'isha))))))

(ert-deftest org-awqat-sunrise-maghrib-symmetric ()
  "Sunrise and Maghrib sit symmetrically around Dhuhr (same angle)."
  (let* ((tm (org-awqat-test--times '(6 21 2026)))
         (d (cdr (assq 'dhuhr tm)))
         (a (- (cdr (assq 'maghrib tm)) d))
         (b (- d (cdr (assq 'sunrise tm)))))
    (should (< (abs (- a b)) 0.02))))

(ert-deftest org-awqat-daylight-sanity ()
  "Daylight length in Dhaka stays within 10.5-13.5 hours year-round."
  (dotimes (i 12)
    (let* ((date (list (1+ i) 15 2026))
           (tm (org-awqat-test--times date))
           (daylight (- (cdr (assq 'maghrib tm))
                        (cdr (assq 'sunrise tm)))))
      (should (< 10.5 daylight 13.5)))))

(ert-deftest org-awqat-makkah-isha-is-90min-after-maghrib ()
  "Under the Umm al-Qura method Isha = Maghrib + 1.5h."
  (let* ((tm (org-awqat-test--times '(3 1 2026) 'makkah))
         (m (cdr (assq 'maghrib tm)))
         (i (cdr (assq 'isha tm))))
    (should (< (abs (- i (+ m 1.5))) 0.01))))

(ert-deftest org-awqat-hanafi-asr-is-later ()
  "Factor 2 (Hanafi) gives a later Asr than factor 1."
  (let ((org-awqat-latitude org-awqat-test-lat)
        (org-awqat-longitude org-awqat-test-lng)
        (org-awqat-timezone-offset org-awqat-test-tz)
        (asr nil))
    (let ((org-awqat-asr-factor 1))
      (setq asr (cdr (assq 'asr (org-awqat-times-decimal '(6 1 2026))))))
    (let ((org-awqat-asr-factor 2))
      (should (> (cdr (assq 'asr (org-awqat-times-decimal '(6 1 2026)))) asr)))))

(ert-deftest org-awqat-format-time ()
  (should (equal "05:30" (org-awqat-format-time 5.5)))
  (should (equal "12:00" (org-awqat-format-time 12.0)))
  (should (equal "13:00" (org-awqat-format-time 12.999999)))
  (should (equal "00:05" (org-awqat-format-time 0.083333333)))
  (should (equal "23:59" (org-awqat-format-time 23.983333333)))
  (should (null (org-awqat-format-time nil))))

(ert-deftest org-awqat-times-hhmm-strings ()
  "The formatted alist carries all six prayers as HH:MM."
  (let ((org-awqat-latitude org-awqat-test-lat)
        (org-awqat-longitude org-awqat-test-lng)
        (org-awqat-timezone-offset org-awqat-test-tz))
    (let ((times (org-awqat-times '(2 1 2026))))
      (should (equal org-awqat-prayer-names (mapcar #'car times)))
      (dolist (cell times)
        (should (string-match-p "^[0-9]\\{2\\}:[0-9]\\{2\\}$" (cdr cell)))))))

(ert-deftest org-awqat-needs-location ()
  "Without coordinates the engine fails loudly, not silently."
  (let ((org-awqat-latitude nil) (org-awqat-longitude nil))
    (should-error (org-awqat-times-decimal))))

(ert-deftest org-awqat-next-prayer-finds-a-later-one ()
  "With `now' at 03:00, the next prayer is Fajr."
  (let ((org-awqat-latitude org-awqat-test-lat)
        (org-awqat-longitude org-awqat-test-lng)
        (org-awqat-timezone-offset org-awqat-test-tz))
    (let* ((now (encode-time 0 0 3 23 11 2026))
           (next (org-awqat-next-prayer now)))
      (should next)
      (should (eq 'fajr (cdr next)))
      ;; Fajr in Dhaka on 2026-11-23 is after 03:00 and before sunrise.
      (should (< 3 (nth 2 (decode-time (car next))) 7)))))

;;; --- Jama'ah ------------------------------------------------------------------

(ert-deftest org-awqat-jamaah-round-trip ()
  "Set + get, with weekday override beating Default."
  (let* ((org-awqat-jamaah-file
          (make-temp-file "org-awqat-jamaah-" nil ".org"))
         (date '(11 27 2026))            ; some weekday, computed below
         (day (org-awqat--day-name date)))
    (unwind-protect
        (progn
          (org-awqat-jamaah-set 'fajr "05:30")
          (org-awqat-jamaah-set 'dhuhr "13:15")
          (org-awqat-jamaah-set 'asr "16:40")
          (org-awqat-jamaah-set 'maghrib "17:55" day)
          ;; Default values are visible for that day...
          (let ((j (org-awqat-jamaah-get date)))
            (should (equal "05:30" (cdr (assq 'fajr j))))
            (should (equal "13:15" (cdr (assq 'dhuhr j))))
            ;; ...unless the day overrides them.
            (should (equal "17:55" (cdr (assq 'maghrib j))))
            (should (null (assq 'isha j))))
          ;; Another day sees only Default.
          (let* ((other '(3 3 2027))
                 (j (org-awqat-jamaah-get other)))
            (should (equal "05:30" (cdr (assq 'fajr j))))
            (should (null (assq 'maghrib j)))))
      (delete-file org-awqat-jamaah-file))))

(ert-deftest org-awqat-jamaah-rejects-bad-time ()
  (let ((org-awqat-jamaah-file
         (make-temp-file "org-awqat-jamaah-" nil ".org")))
    (unwind-protect
        (progn
          (should-error (org-awqat-jamaah-set 'fajr "5 oclock"))
          (should-error (org-awqat-jamaah-set 'jumuah "13:00")))
      (delete-file org-awqat-jamaah-file))))

(ert-deftest org-awqat-jamaah-day-name ()
  (should (equal "sun" (org-awqat--day-name '(11 22 2026))))
  (should (equal "mon" (org-awqat--day-name '(11 23 2026))))
  (should (equal "fri" (org-awqat--day-name '(11 27 2026)))))

;;; --- Hijri Org timestamps ------------------------------------------------------

(ert-deftest org-awqat-insert-timestamp-converts ()
  "A Hijri date inserts as a Gregorian Org timestamp, and reads back."
  (with-temp-buffer
    (org-mode)
    (let* ((hij '(6 12 1447))
           (g (org-awqat-hijri-to-gregorian hij))
           (raw (org-awqat-insert-timestamp hij)))
      ;; The inserted timestamp is the Gregorian equivalent.
      (should (string-prefix-p
               (format "%04d-%02d-%02d" (nth 2 g) (nth 0 g) (nth 1 g))
               raw))
      ;; And the at-point reader returns the same Hijri date.
      (goto-char (point-min))
      (when (search-forward "<" nil t) (backward-char 1))
      (should (equal hij (org-awqat-timestamp-hijri-at-point))))))

(ert-deftest org-awqat-schedule-hijri-sets-scheduled ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO pray\n")
    (goto-char (point-min))
    (org-awqat-schedule-hijri '(1 10 1448))
    (should (string-match-p
             "SCHEDULED: <"
             (buffer-string)))))

(ert-deftest org-awqat-new-habit-makes-a-habit ()
  (with-temp-buffer
    (org-mode)
    (insert "* Habits\n")
    (org-awqat-new-habit '(7 1 1447) "Read Qur'an" 2)
    (let ((body (buffer-substring (point-min) (point-max))))
      (should (string-match-p "TODO Read Qur'an" body))
      (should (string-match-p ":STYLE:[ \t]*habit" body))
      (should (string-match-p "SCHEDULED: <[^>]+> \\.\\+2d" body)))))

;;; --- Widgets -------------------------------------------------------------------

;; The tree builders run without elwidget (it is a soft dependency);
;; only their shape is tested here.

(ert-deftest org-awqat-widget-jamaah-tree-filled ()
  "With a Jama'ah time set, the tree carries it in a row."
  (let ((org-awqat-jamaah-file
         (make-temp-file "org-awqat-jamaah-" nil ".org")))
    (unwind-protect
        (progn
          (org-awqat-jamaah-set 'fajr "05:35")
          (let ((tree (org-awqat-widget--jamaah-tree)))
            (should (cl-find-if (lambda (n) (eq :row (car n))) tree))
            (should (string-match-p "05:35" (prin1-to-string tree)))))
      (delete-file org-awqat-jamaah-file))))

(ert-deftest org-awqat-widget-hijri-tree-shape ()
  (let ((tree (org-awqat-widget--hijri-tree)))
    (should (eq :column (car tree)))
    (should (string-match-p "AH" (prin1-to-string tree)))))

(ert-deftest org-awqat-widget-salah-tree-shape ()
  (let ((org-awqat-latitude org-awqat-test-lat)
        (org-awqat-longitude org-awqat-test-lng)
        (org-awqat-timezone-offset org-awqat-test-tz))
    (let ((tree (org-awqat-widget--salah-tree)))
      (should (eq :column (car tree)))
      ;; First child is the next-prayer row; the last two are the rows
      ;; of times (:column NEXT, :bar, :row, :row).
      (should (eq :row (car (nth 1 tree))))
      (should (eq :bar (car (nth 2 tree))))
      (should (eq :row (car (nth 3 tree))))
      (should (eq :row (car (nth 4 tree)))))))

(ert-deftest org-awqat-widget-jamaah-tree-shape ()
  (let ((org-awqat-jamaah-file
         (make-temp-file "org-awqat-jamaah-" nil ".org")))
    (unwind-protect
        (let ((tree (org-awqat-widget--jamaah-tree)))
          ;; No times set: the hint line, no row.
          (should (eq :column (car tree)))
          (should (null (cl-find-if (lambda (n) (eq :row (car n))) tree))))
      (delete-file org-awqat-jamaah-file))))

(ert-deftest org-awqat-widget-countdown ()
  (should (equal "1h 0m" (org-awqat-widget--countdown
                           0 (* 1 3600))))
  (should (equal "5m" (org-awqat-widget--countdown 0 300)))
  (should (equal "1d 2h" (org-awqat-widget--countdown 0 93600))))

(provide 'test)
;;; test.el ends here
