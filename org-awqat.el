;;; org-awqat.el --- Hijri dates, Salah times and Jama'ah tracking for Org -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: GLM 5.3 <glm-5.3@z.ai>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org "9.3"))
;; Keywords: calendar, islam, org, tools
;; URL: https://github.com/khaalidrafi/org-awqat

;;; Commentary:

;; An Islamic times package for Emacs (part of the Org-on-Android
;; family: works on the desktop and inside the emacshell app).

;;   * Hijri date: today's date, formatting, and conversion both ways
;;     (the built-in arithmetic Islamic civil calendar).
;;   * Hijri Org timestamps: insert, schedule and deadline Org items
;;     by typing a Hijri date; show the Hijri reading of any Org
;;     timestamp.  Habit headings can start from a Hijri date, so
;;     to-dos and habits are tracked with the Hijri calendar while
;;     Org itself keeps its portable Gregorian timestamps underneath.
;;   * Salah times: Fajr, Sunrise, Dhuhr, Asr, Maghrib and Isha
;;     computed offline (standard solar astronomy, several angle
;;     conventions), no network and no external binary.
;;   * Jama'ah (congregation) times: your own per-prayer times,
;;     stored in a plain Org file, with per-weekday overrides.
;;   * Home-screen widgets are in org-awqat-widget.el (elwidget).

;;; Code:

(require 'calendar)
;; Upstream ships lisp/calendar/cal-islamic.el; Debian renames the
;; compiled file (and the provided feature) to cal-islam.  Accept both.
(cond ((require 'cal-islamic nil t))
      ((require 'cal-islam nil t))
      (t (error "org-awqat: no Islamic calendar (cal-islamic/cal-islam)")))
(declare-function calendar-islamic-from-absolute "cal-islamic" (date))
(declare-function calendar-absolute-from-islamic "cal-islamic" (date))
(require 'cl-lib)
(require 'org)
(require 'org-element)

(defgroup org-awqat nil
  "Hijri dates, Salah times and Jama'ah tracking for Org."
  :group 'org
  :prefix "org-awqat-")

;;; --- Hijri calendar --------------------------------------------------------

(defconst org-awqat-hijri-month-names
  ["Muharram" "Safar" "Rabi' al-Awwal" "Rabi' al-Thani"
   "Jumada al-Ula" "Jumada al-Akhira" "Rajab" "Sha'ban"
   "Ramadan" "Shawwal" "Dhu al-Qi'da" "Dhu al-Hijja"]
  "Hijri month names, index 1 = Muharram.")

(defun org-awqat-gregorian-to-hijri (date)
  "Convert Gregorian DATE (MONTH DAY YEAR) to Hijri (MONTH DAY YEAR).
Uses Emacs' built-in arithmetic Islamic (civil) calendar."
  (calendar-islamic-from-absolute (calendar-absolute-from-gregorian date)))

(defun org-awqat-hijri-to-gregorian (date)
  "Convert Hijri DATE (MONTH DAY YEAR) to Gregorian (MONTH DAY YEAR)."
  (calendar-gregorian-from-absolute (calendar-absolute-from-islamic date)))

(defun org-awqat-today-hijri ()
  "Today's Hijri date as (MONTH DAY YEAR)."
  (org-awqat-gregorian-to-hijri (calendar-current-date)))

(defun org-awqat-format-hijri (hij)
  "Format Hijri date HIJ (MONTH DAY YEAR) as \"12 Jumada al-Ula 1447 AH\"."
  (let ((m (nth 0 hij)) (d (nth 1 hij)) (y (nth 2 hij)))
    (format "%d %s %d AH" d (aref org-awqat-hijri-month-names (1- m)) y)))

(defun org-awqat-format-hijri-iso (hij)
  "Format Hijri date HIJ (MONTH DAY YEAR) as \"1447-06-12\"."
  (format "%04d-%02d-%02d" (nth 2 hij) (nth 0 hij) (nth 1 hij)))

(defun org-awqat-read-hijri (&optional prompt)
  "Prompt for a Hijri date, return it as (MONTH DAY YEAR).
Empty input means today.  Accepts \"1447-06-12\" or
\"1447/6/12\"."
  (let* ((default (org-awqat-format-hijri-iso (org-awqat-today-hijri)))
         (s (read-string (format "%s (Hijri YYYY-MM-DD, empty = %s): "
                                 (or prompt "Hijri date") default))))
    (org-awqat-parse-hijri (if (string-empty-p s) default s))))

(defun org-awqat-parse-hijri (s)
  "Parse S (\"1447-06-12\" or \"1447/6/12\") to Hijri (MONTH DAY YEAR)."
  (unless (string-match
           "^\\s-*\\([0-9]\\{1,4\\}\\)[-/.]\\([0-9]\\{1,2\\}\\)[-/.]\\([0-9]\\{1,2\\}\\)\\s-*$"
           s)
    (error "org-awqat: cannot parse Hijri date %S" s))
  (let ((y (string-to-number (match-string 1 s)))
        (m (string-to-number (match-string 2 s)))
        (d (string-to-number (match-string 3 s))))
    (unless (and (<= 1 m 12) (<= 1 d 30))
      (error "org-awqat: Hijri date out of range %S" s))
    (list m d y)))

(defun org-awqat-display-today ()
  "Show today's date in both calendars."
  (interactive)
  (message "Hijri: %s (%s)"
           (org-awqat-format-hijri (org-awqat-today-hijri))
           (format-time-string "%A, %e %B %Y")))

;;; --- Hijri Org timestamps --------------------------------------------------

(defun org-awqat--gregorian-org-string (g)
  "Gregorian date G (MONTH DAY YEAR) as \"YYYY-MM-DD\" for Org commands."
  (format "%04d-%02d-%02d" (nth 2 g) (nth 1 g) (nth 0 g)))

(defun org-awqat-insert-timestamp (hij &optional inactive)
  "Insert an Org timestamp for Hijri date HIJ (MONTH DAY YEAR) at point.
The timestamp is Gregorian underneath (portable Org); INACTIVE
non-nil inserts an inactive [..] timestamp.  Returns the inserted
timestamp's raw string."
  (let* ((g (org-awqat-hijri-to-gregorian hij))
         (time (encode-time 0 0 0 (nth 1 g) (nth 0 g) (nth 2 g))))
    (org-insert-time-stamp time nil inactive)
    (org-element-property :raw-value (org-element-context))))

(defun org-awqat-insert-timestamp-at-point (&optional inactive)
  "Insert an Org timestamp for a Hijri date you type, at point.
With prefix arg, insert an inactive [..] timestamp."
  (interactive "P")
  (org-awqat-insert-timestamp (org-awqat-read-hijri) inactive))

(defun org-awqat-schedule-hijri (hij)
  "Schedule the entry at point to Hijri date HIJ (MONTH DAY YEAR)."
  (org-schedule nil (org-awqat--gregorian-org-string
                     (org-awqat-hijri-to-gregorian hij))))

(defun org-awqat-schedule-at-point ()
  "Schedule the Org entry at point to a Hijri date you type."
  (interactive)
  (org-awqat-schedule-hijri (org-awqat-read-hijri "Schedule to Hijri")))

(defun org-awqat-deadline-hijri (hij)
  "Set the deadline of the entry at point to Hijri date HIJ."
  (org-deadline nil (org-awqat--gregorian-org-string
                     (org-awqat-hijri-to-gregorian hij))))

(defun org-awqat-deadline-at-point ()
  "Set the deadline of the Org entry at point to a Hijri date you type."
  (interactive)
  (org-awqat-deadline-hijri (org-awqat-read-hijri "Deadline Hijri")))

(defun org-awqat-timestamp-hijri-at-point ()
  "Show the Hijri reading of the Org timestamp at point."
  (interactive)
  (let* ((elem (org-element-context))
         (raw (when (eq (org-element-type elem) 'timestamp)
                (org-element-property :raw-value elem))))
    (unless raw (error "org-awqat: no Org timestamp at point"))
    (unless (string-match "\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)" raw)
      (error "org-awqat: cannot read date from %S" raw))
    (let* ((g (list (string-to-number (match-string 2 raw))
                    (string-to-number (match-string 3 raw))
                    (string-to-number (match-string 1 raw))))
           (hij (org-awqat-gregorian-to-hijri g)))
      (message "%s = %s" raw (org-awqat-format-hijri hij))
      hij)))

(defun org-awqat-new-habit (hij name repeat-days)
  "Insert a new habit NAME scheduled from Hijri date HIJ.
REPEAT-DAYS is the habit's daily repeat (Org \".+Nd\" style, so
missed days do not pile up -- same style loophabits expects).
The heading carries SCHEDULED (Gregorian underneath, set from the
Hijri date you gave) and STYLE=habit, ready for org-habit and
loophabits tracking."
  (unless (and (numberp repeat-days) (> repeat-days 0))
    (error "org-awqat: repeat-days must be a positive number"))
  (goto-char (point-max))
  (org-insert-heading)
  ;; Stay ON the heading line: the schedule/property commands below
  ;; act on the entry at point.
  (insert "TODO " name)
  (org-set-property "STYLE" "habit")
  (org-awqat-schedule-hijri hij)
  ;; Append the repeater to the SCHEDULED timestamp we just wrote,
  ;; searching only inside THIS entry (the buffer may hold others).
  (save-excursion
    (let ((limit (or (save-excursion (outline-next-heading))
                     (point-max))))
      (when (re-search-forward
             "SCHEDULED: <\\([^>\n]+\\)>" limit t)
        (goto-char (match-end 1))
        (insert (format " .+%dd" repeat-days)))))
  (point))

(defun org-awqat-new-habit-at-point ()
  "Insert a new habit heading with a Hijri start date (prompts)."
  (interactive)
  (let* ((hij (org-awqat-read-hijri "Habit starts (Hijri)"))
         (name (read-string "Habit name: "))
         (repeat (read-number "Repeat every N days: " 1)))
    (org-awqat-new-habit hij name repeat)))

;;; --- Salah times -----------------------------------------------------------

(defcustom org-awqat-latitude nil
  "Your latitude in decimal degrees, north positive.
Required for Salah computation."
  :type '(choice (const :tag "Unset" nil) number))

(defcustom org-awqat-longitude nil
  "Your longitude in decimal degrees, east positive.
Required for Salah computation."
  :type '(choice (const :tag "Unset" nil) number))

(defcustom org-awqat-timezone-offset nil
  "Hours offset from UTC, e.g. 6 for Dhaka.
Nil means derive it from `current-time-zone'."
  :type '(choice (const :tag "Auto" nil) number))

(defcustom org-awqat-method 'mwl
  "The angle convention for Fajr and Isha."
  :type '(choice (const :tag "Muslim World League (18/17)" mwl)
                 (const :tag "ISNA (15/15)" isna)
                 (const :tag "Egyptian General Authority (19.5/17.5)" egypt)
                 (const :tag "University of Karachi (18/18)" karachi)
                 (const :tag "Umm al-Qura, Makkah (18.5 / 90min after Maghrib)" makkah)
                 (const :tag "Manual angles" manual)))

(defcustom org-awqat-fajr-angle 18.0
  "Manual Fajr depression angle (degrees), used when method is `manual'."
  :type 'number)

(defcustom org-awqat-isha-angle 17.0
  "Manual Isha depression angle (degrees), used when method is `manual'."
  :type 'number)

(defcustom org-awqat-asr-factor 1
  "Asr shadow factor: 1 for Shafi'i/Maliki/Hanbali, 2 for Hanafi."
  :type '(choice (const :tag "Standard (1)" 1) (const :tag "Hanafi (2)" 2)))

(defconst org-awqat--method-angles
  '((mwl . (18.0 . 17.0))
    (isna . (15.0 . 15.0))
    (egypt . (19.5 . 17.5))
    (karachi . (18.0 . 18.0))
    (makkah . (18.5 . makkah-isha))
    (manual . nil))
  "Cons cells (FAJR-ANGLE . ISHA-ANGLE) per method.")

(defconst org-awqat-prayer-names
  '(fajr sunrise dhuhr asr maghrib isha)
  "The computed times, in day order.")

(defconst org-awqat-prayer-labels
  '((fajr . "Fajr") (sunrise . "Sunrise") (dhuhr . "Dhuhr")
    (asr . "Asr") (maghrib . "Maghrib") (isha . "Isha"))
  "Display names for the prayers.")

(defun org-awqat--deg->rad (d) (* float-pi (/ d 180.0)))
(defun org-awqat--rad->deg (r) (* 180.0 (/ r float-pi)))
(defmacro org-awqat--dsin (d) `(sin (org-awqat--deg->rad ,d)))
(defmacro org-awqat--dcos (d) `(cos (org-awqat--deg->rad ,d)))
(defmacro org-awqat--dtan (d) `(tan (org-awqat--deg->rad ,d)))

(defun org-awqat--fix-angle (a)
  "Fold angle A (degrees) into [0, 360)."
  (mod a 360.0))

(defun org-awqat--fix-hour (h)
  "Fold time H (hours) into [0, 24)."
  (mod h 24.0))

(defun org-awqat--julian-day (m d y)
  "Julian Day at 00:00 UT of Gregorian M/D/Y (standard float formula)."
  (when (<= m 2)
    (setq m (+ m 12) y (1- y)))
  (let* ((a (floor y 100.0))
         (b (- 2 a (floor a 4.0))))
    (+ (floor (* 365.25 (+ y 4716.0)))
       (floor (* 30.6001 (1+ m)))
       d b -1524.5)))

(defun org-awqat--sun-position (jd)
  "Sun position for Julian Day JD: (DECLINATION . EQUATION-OF-TIME).
Declination in degrees, equation of time in hours.  Low-precision
solar formulas (NOAA-style), accurate to well under a minute for
prayer-time purposes."
  (let* ((d (- jd 2451545.0))
         (g (org-awqat--fix-angle (+ 357.529 (* 0.98560028 d))))
         (q (org-awqat--fix-angle (+ 280.459 (* 0.98564736 d))))
         (l (org-awqat--fix-angle (+ q (* 1.915 (org-awqat--dsin g))
                                     (* 0.020 (org-awqat--dsin (* 2 g))))))
         (e (- 23.439 (* 0.00000036 d)))
         (ra (org-awqat--fix-hour
              (/ (org-awqat--rad->deg
                  (atan (* (org-awqat--dcos e) (org-awqat--dsin l))
                        (org-awqat--dcos l)))
                 15.0))))
    (cons (org-awqat--rad->deg
           (asin (* (org-awqat--dsin e) (org-awqat--dsin l))))
          (org-awqat--fix-hour (- (/ q 15.0) ra)))))

(defun org-awqat--hour-angle (angle lat decl)
  "Hours from solar noon for the sun at depression ANGLE (degrees).
ANGLE positive means below the horizon (Fajr, sunrise, Isha...);
negative means above it (Asr).  NIL when the sun never gets there."
  (let* ((arg (/ (- (- (org-awqat--dsin angle))
                    (* (org-awqat--dsin lat) (org-awqat--dsin decl)))
                 (* (org-awqat--dcos lat) (org-awqat--dcos decl)))))
    (cond ((> arg 1.0) nil)             ; never reaches that angle
          ((< arg -1.0) 0.0)            ; always there (polar day/night)
          (t (/ (org-awqat--rad->deg (acos arg)) 15.0)))))

(defun org-awqat--asr-altitude (lat decl)
  "Sun altitude (degrees) at Asr time for LAT and solar DECL."
  (org-awqat--rad->deg
   (atan 1.0 (+ org-awqat-asr-factor
                (org-awqat--dtan (abs (- lat decl)))))))

(defun org-awqat--tz-offset ()
  "Timezone offset in hours."
  (or org-awqat-timezone-offset
      (/ (or (car (current-time-zone)) 0) 3600.0)))

(defun org-awqat-times-decimal (&optional date)
  "Salah times for Gregorian DATE (default today), in decimal hours.
Returns an alist ((PRAYER . HOURS)...), PRAYER from
`org-awqat-prayer-names'; HOURS is nil when the sun never
reaches the angle (polar latitudes)."
  (unless (and org-awqat-latitude org-awqat-longitude)
    (error "org-awqat: set `org-awqat-latitude' and `org-awqat-longitude' first"))
  (let* ((date (or date (calendar-current-date)))
         (lat org-awqat-latitude)
         (lng org-awqat-longitude)
         (tz (org-awqat--tz-offset))
         ;; Evaluate the sun at local noon: JD of the date shifted by
         ;; the longitude (east = earlier solar noon) and the zone.
         (jd (- (+ (org-awqat--julian-day (nth 0 date) (nth 1 date) (nth 2 date))
                   0.5)
                (/ (+ lng (* tz 15.0)) 360.0)))
         (pos (org-awqat--sun-position jd))
         (decl (car pos))
         (eqt (cdr pos))
         (dhuhr (org-awqat--fix-hour (+ 12 tz (- (/ lng 15.0)) (- eqt))))
         (angles (cdr (assq org-awqat-method org-awqat--method-angles)))
         (fajr-a (if angles (car angles) org-awqat-fajr-angle))
         (isha-a (if angles
                     (let ((ia (cdr angles)))
                       (if (eq ia 'makkah-isha) nil ia))
                   org-awqat-isha-angle))
         (sunrise-t (org-awqat--hour-angle 0.833 lat decl))
         (asr-t (org-awqat--hour-angle
                 (- (org-awqat--asr-altitude lat decl)) lat decl))
         (fajr-t (org-awqat--hour-angle fajr-a lat decl))
         (maghrib-t sunrise-t)
         (isha-t (if isha-a (org-awqat--hour-angle isha-a lat decl)
                   ;; Umm al-Qura: 90 minutes after Maghrib.
                   (when maghrib-t 1.5))))
    `((fajr . ,(when fajr-t (- dhuhr fajr-t)))
      (sunrise . ,(when sunrise-t (- dhuhr sunrise-t)))
      (dhuhr . ,dhuhr)
      (asr . ,(when asr-t (+ dhuhr asr-t)))
      (maghrib . ,(when maghrib-t (+ dhuhr maghrib-t)))
      (isha . ,(when isha-t (+ dhuhr isha-t))))))

(defun org-awqat-format-time (hours)
  "Decimal HOURS as \"HH:MM\" (nil stays nil)."
  (when hours
    (let* ((h (mod (floor (+ hours 1e-9)) 24))
           (m (floor (+ (* 60 (- hours (floor hours))) 1e-9))))
      ;; rounding edge: 60 minutes rolls into the next hour
      (if (= m 60) (format "%02d:00" (mod (1+ h) 24))
        (format "%02d:%02d" h m)))))

(defun org-awqat-times (&optional date)
  "Salah times for DATE (default today) as ((PRAYER . \"HH:MM\")...).
Prayers without a time today (polar latitudes) read \"--:--\"."
  (mapcar (lambda (cell)
            (cons (car cell)
                  (or (org-awqat-format-time (cdr cell)) "--:--")))
          (org-awqat-times-decimal date)))

(defun org-awqat-next-prayer (&optional now)
  "The next prayer after NOW (time value; default `current-time').
Returns (PRAYER-TIME-VALUE . PRAYER-SYMBOL) or nil when all of
today's prayers are past (the widget then shows tomorrow's Fajr)."
  (let* ((now (or now (current-time)))
         (dt (decode-time now))
         (now-h (+ (nth 2 dt) (/ (nth 1 dt) 60.0))))
    (cl-loop for (p . h) in (org-awqat-times-decimal)
             when (and h (> h now-h))
             return (cons (encode-time 0
                                       (floor (mod (* 60 h) 60))
                                       (mod (floor h) 24)
                                       (nth 3 dt) (nth 4 dt) (nth 5 dt))
                          p))))

(defun org-awqat-display-times ()
  "Show today's Salah times in the echo area."
  (interactive)
  (message "%s  %s"
           (org-awqat-format-hijri (org-awqat-today-hijri))
           (mapconcat (lambda (cell)
                        (format "%s %s"
                                (cdr (assq (car cell) org-awqat-prayer-labels))
                                (cdr cell)))
                      (org-awqat-times) "  ")))

;;; --- Jama'ah (congregation) times ------------------------------------------

(defcustom org-awqat-jamaah-file
  (expand-file-name "awqat.org"
                    (or (bound-and-true-p org-directory)
                        "~/org"))
  "Org file holding your Jama'ah times.
First-level headings name a day (sun mon tue wed thu fri sat) or
\"Default\"; each heading's FAJR/SUNRISE/DHUHR/ASR/MAGHRIB/ISHA
properties hold that day's congregation times.  The day's own
heading wins over Default."
  :type 'file)

(defconst org-awqat--jamaah-props
  '((fajr . "FAJR") (sunrise . "SUNRISE") (dhuhr . "DHUHR")
    (asr . "ASR") (maghrib . "MAGHRIB") (isha . "ISHA"))
  "Prayer symbol to the Org property name used for Jama'ah.")

(defun org-awqat--day-name (date)
  "Lowercase weekday abbreviation of Gregorian DATE (sun mon ...)."
  (downcase (substring (calendar-day-name date) 0 3)))

(defun org-awqat--jamaah-buffer ()
  "The visiting buffer of `org-awqat-jamaah-file', in org-mode."
  (let ((dir (file-name-directory org-awqat-jamaah-file)))
    (when dir (make-directory dir t)))
  (let ((buf (find-file-noselect org-awqat-jamaah-file)))
    (with-current-buffer buf
      (unless (derived-mode-p 'org-mode) (org-mode)))
    buf))

(defun org-awqat--jamaah-find-heading (buf day)
  "In BUF, move to DAY's first-level Jama'ah heading, or nil."
  (with-current-buffer buf
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (when (re-search-forward
             (concat "^\\* \\(" (regexp-quote day) "\\|Default\\)[ \t]*$") nil t)
        (goto-char (match-beginning 0))
        (point)))))

(defun org-awqat--jamaah-ensure-heading (buf day)
  "In BUF, move to DAY's heading, creating it at the end if absent."
  (or (org-awqat--jamaah-find-heading buf day)
      (with-current-buffer buf
        (goto-char (point-max))
        (unless (bobp) (insert "\n"))
        (insert "* " (capitalize day) "\n")
        (goto-char (point-max))
        (point))))

(defun org-awqat-jamaah-set (prayer time &optional day)
  "Set the Jama'ah time of PRAYER (symbol) to TIME (\"HH:MM\").
DAY is \"Default\" or a weekday abbreviation (default \"Default\").
Writes `org-awqat-jamaah-file'."
  (let ((prop (cdr (assq prayer org-awqat--jamaah-props))))
    (unless prop (error "org-awqat: unknown prayer %S" prayer))
    (unless (string-match-p "^[0-9]\\{1,2\\}:[0-9]\\{2\\}$" time)
      (error "org-awqat: time must look like HH:MM, got %S" time))
    (let ((buf (org-awqat--jamaah-buffer)))
      (with-current-buffer buf
        (save-excursion
          (org-awqat--jamaah-ensure-heading buf (or day "Default"))
          (org-entry-put (point) prop time))
        (save-buffer)))))

(defun org-awqat-jamaah-set-at-point ()
  "Set one Jama'ah time (prompts for prayer, time and day)."
  (interactive)
  (let* ((day (completing-read
               "Day (Default or sun mon tue wed thu fri sat): "
               '("Default" "sun" "mon" "tue" "wed" "thu" "fri" "sat") nil t))
         (prayer (intern
                  (downcase
                   (completing-read "Prayer: "
                                    '("Fajr" "Sunrise" "Dhuhr" "Asr"
                                      "Maghrib" "Isha") nil t))))
         (time (read-string "Jama'ah time (HH:MM): ")))
    (org-awqat-jamaah-set prayer time day)
    (message "org-awqat: %s %s -> %s (%s)"
             (capitalize (symbol-name prayer)) time
             (capitalize day) org-awqat-jamaah-file)))

(defun org-awqat-jamaah-get (&optional date)
  "Today's (or DATE's) Jama'ah times as ((PRAYER . \"HH:MM\")...).
The day's own heading wins over Default; unset prayers are absent."
  (let* ((date (or date (calendar-current-date)))
         (buf (org-awqat--jamaah-buffer))
         (read-props
          (lambda (day)
            (when (org-awqat--jamaah-find-heading buf day)
              (delq nil
                    (mapcar (lambda (cell)
                              (let ((v (org-entry-get (point) (cdr cell))))
                                (when v (cons (car cell) v))))
                            org-awqat--jamaah-props))))))
    (append (funcall read-props (org-awqat--day-name date))
            (funcall read-props "Default"))))

(defun org-awqat-jamaah-open ()
  "Visit `org-awqat-jamaah-file' for manual editing."
  (interactive)
  (find-file (expand-file-name org-awqat-jamaah-file)))

(provide 'org-awqat)
;;; org-awqat.el ends here
