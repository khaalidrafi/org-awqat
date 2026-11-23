;;; org-hijri.el --- Islamic (Hijri) dates in Org, with Maghrib day rollover -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Khalid Rafi

;; Author: Khalid Rafi
;; Version: 1.0
;; Package-Requires: ((emacs "27.1") (org "9.4"))
;; Keywords: calendar, org, islamic, hijri
;; URL: https://github.com/khaalidrafi

;;; Commentary:

;; Make Org natively aware of Islamic (Hijri) dates, the way it is
;; aware of Gregorian dates.

;;
;; The syntax
;;
;; Any Org timestamp may carry the marker `Hijri' in the day-name slot
;; that Org already reserves after the date:
;;
;;     <1446-06-15 Hijri>                  a Hijri date
;;     <1446-06-15 Hijri 10:00>            with time
;;     <1446-06-15 Hijri +1m>              repeating monthly in the
;;                                         Islamic calendar
;;     DEADLINE: <1447-01-01 Hijri -3d>    planning line
;;
;; Gregorian stamps are untouched: only explicitly marked dates are
;; interpreted and displayed as Hijri.  The marker sits where Org's
;; weekday name goes, so every stock reader -- `org-parse-time-string',
;; the org-element timestamp parser, font-lock, the agenda scanner --
;; already accepts the text; this package teaches them what it means.
;;
;;
;; What works
;;
;; - Parsing: the date inside a marked stamp is converted from the
;;   Islamic calendar to its Gregorian equivalent (the daytime of that
;;   Islamic day) before any Org logic sees it.  Agenda placement,
;;   deadline warnings, sorting, SPC calendar follow -- all correct.
;; - Repeaters: `+1m' / `+1y' on a Hijri stamp step through the
;;   Islamic calendar (about 354 days a year), with day clamping when
;;   the target month is shorter (`+1m' from 30 Ramadan lands on 29
;;   Shawwal).  `+Nd'/`+Nw'/`+Nh' repeat on absolute days/hours.
;; - Editing: S-<up>/<down>/<left>/<right> and C-c . on a Hijri stamp
;;   edit the Islamic date; the marker is preserved.
;; - Insertion: `org-hijri-timestamp', `org-hijri-deadline' and
;;   `org-hijri-schedule' insert Hijri stamps.
;; - Maghrib rollover: the Islamic day starts at sunset, not midnight.
;;   With `org-hijri-maghrib-rollover' (default t) the current Hijri
;;   date (`org-hijri-today') advances at Maghrib, and Hijri-dated
;;   agenda entries become due that same evening: after Maghrib
;;   tonight, an entry dated tomorrow's Hijri date is already "today".
;;   Gregorian entries keep rolling at midnight.
;;
;;
;; Maghrib times
;;
;; Maghrib times come first from org-awqat (this repository's own
;; offline Salah computation: one location setting drives both), then
;; from the standalone `awqat' package (zkry/awqat on MELPA) when
;; installed, then from Emacs' `solar.el' geometric sunset.
;; A location is needed: set org-awqat's `org-awqat-latitude'/
;; `org-awqat-longitude' (preferred), or `calendar-latitude'/
;; `calendar-longitude' for the solar fallback.  If no location is
;; set, Maghrib is unknown and the rollover silently degrades to
;; midnight (no data is invented).
;;
;;
;; Usage
;;
;;     (require 'org-hijri)
;;     (org-hijri-mode 1)
;;
;; Interactive commands:
;;
;;     M-x org-hijri-show         current Hijri date + Maghrib time
;;     M-x org-hijri-timestamp    insert a Hijri timestamp at point
;;     M-x org-hijri-deadline     DEADLINE: <... Hijri>
;;     M-x org-hijri-schedule     SCHEDULED: <... Hijri>
;;     M-x org-hijri-agenda       agenda starting at the current
;;                                Hijri day (rolls at Maghrib)
;;
;; When `org-hijri-mode' is on, the agenda day headers also show the
;; Hijri date of each day (set `org-hijri-agenda-show-hijri-date' to
;; nil to disable), and Hijri stamps get the `org-hijri-marker' face.
;;
;; Known limits: date ranges where only one end is marked are parsed
;; but not re-emitted as Hijri on edit; `org-display-custom-times'
;; overlays would show the Gregorian equivalent; diary sexps ignore
;; the marker.  Invalid Hijri numerals (e.g. day 30 of a 29-day month
;; written by hand) are left in their Gregorian reading rather than
;; guessed at.

;;; Code:

(require 'org)
(require 'org-element)
(require 'calendar)
(require 'cal-islam)

(declare-function solar-sunrise-sunset "solar" (date))
(declare-function awqat--prayer-time "awqat" (d prayer))
(declare-function org-awqat-times-decimal "org-awqat" (&optional date))
(declare-function org-agenda-redo "org-agenda" (&optional all))
(declare-function org-agenda-list "org-agenda"
                  (&optional key start-day span with-hour))
;; org-fold.el is core Org since 9.6, but the byte-compiler needs it
;; loaded to recognize the org-fold-core-ignore-modifications macro.
(require 'org-fold)

(defgroup org-hijri nil
  "Islamic (Hijri) dates in Org mode."
  :tag "Org Hijri"
  :group 'org)

(defcustom org-hijri-marker "Hijri"
  "Marker word that flags an Org timestamp as an Islamic date.
It occupies the day-name slot of the timestamp:
`<1446-06-15 Hijri>'.  Changing this variable changes the syntax
recognized everywhere (parsing, editing, agenda); use a word that
matches `[^+0-9> -]+' (no spaces, digits, brackets or plusses)."
  :group 'org-hijri
  :type 'string)

(defcustom org-hijri-maghrib-rollover t
  "When non-nil, the Islamic day rolls over at Maghrib, not midnight.
The current Hijri date (`org-hijri-today') advances when the local
time passes the Maghrib of the current Gregorian day, and Hijri-dated
agenda entries become due that evening.  Maghrib is taken from
org-awqat (this repository) when its location is set, then from the
`awqat' package when installed, falling back to `solar.el'.  If
Maghrib is unknown (no location set), rollover silently does not
happen.

This only affects Hijri-marked timestamps; Gregorian timestamps keep
rolling at midnight regardless."
  :group 'org-hijri
  :type 'boolean)

(defcustom org-hijri-agenda-show-hijri-date t
  "When non-nil, agenda day headers show the day's Hijri date.
The date shown is the Hijri date whose daytime falls on that day;
the current day additionally shows when it rolls over (Maghrib)."
  :group 'org-hijri
  :type 'boolean)

(defcustom org-hijri-announce-maghrib t
  "Announce the Maghrib rollover in the echo area.
When `org-hijri-maghrib-rollover' is enabled and the current time
passes Maghrib, message the new Hijri date and refresh the visible
agenda so entries that became due tonight appear."
  :group 'org-hijri
  :type 'boolean)

(defvar org-hijri-mode nil
  "Non-nil while `org-hijri-mode' is enabled.
Declared early so the advice functions below byte-compile without a
free-variable warning; `define-minor-mode' sets the real value.")

;; org-agenda loads lazily; these quiet the byte-compiler for the
;; agenda integration at the bottom of this file.
(defvar org-agenda-format-date)
(defvar org-agenda-buffer-name)

(defface org-hijri-marker
  '((t :slant italic))
  "Face for Hijri-marked timestamps."
  :group 'org-hijri)

;;; Core conversions ------------------------------------------------------

(defun org-hijri-gregorian-from-hijri (hijri)
  "Return the Gregorian date (MONTH DAY YEAR) of Islamic HIJRI date.
HIJRI is (MONTH DAY YEAR) in the Islamic calendar; the result is the
Gregorian date whose daytime is that Islamic day."
  (calendar-gregorian-from-absolute (calendar-islamic-to-absolute hijri)))

(defun org-hijri-hijri-from-gregorian (gregorian)
  "Return the Islamic date (MONTH DAY YEAR) of Gregorian GREGORIAN.
GREGORIAN is (MONTH DAY YEAR); the result is the Hijri date whose
daytime falls on that Gregorian day (i.e. before that day's Maghrib)."
  (calendar-islamic-from-absolute (calendar-absolute-from-gregorian gregorian)))

(defun org-hijri-valid-hijri-p (hijri)
  "Non-nil when HIJRI (MONTH DAY YEAR) is a real Islamic calendar date."
  (let ((m (nth 0 hijri)) (d (nth 1 hijri)) (y (nth 2 hijri)))
    (and (integerp m) (integerp d) (integerp y)
         (>= y 1) (>= m 1) (<= m 12) (>= d 1)
         (<= d (calendar-islamic-last-day-of-month m y)))))

(defun org-hijri--hijri-string (hijri)
  "Format Islamic HIJRI (MONTH DAY YEAR) as a readable string."
  (let ((calendar-month-name-array calendar-islamic-month-name-array))
    (calendar-date-string hijri nil t)))

(defun org-hijri--clamp-islamic (month day year)
  "Clamp Islamic (MONTH DAY YEAR) to the last real day of the month."
  (list month
        (min day (calendar-islamic-last-day-of-month month year))
        year))

;;; Stamp detection and formatting ----------------------------------------

(defun org-hijri--marked-p (s)
  "Non-nil when the first date in string S carries the Hijri marker.
S is a timestamp innards such as \"1446-06-15 Hijri\" (what
`org-ts-regexp0' sees inside <...>)."
  (and (stringp s)
       (string-match org-ts-regexp0 s)
       (match-beginning 5)
       (let ((marker (match-string 5 s)))
         (and marker
              (string-match-p
               (concat "\\` +" (regexp-quote org-hijri-marker) "\\>")
               marker)))))

(defun org-hijri--parse-hijri (s)
  "Parse the Hijri date (MONTH DAY YEAR) from stamp innards S.
Return nil when S is not Hijri-marked or the numerals are not a
valid Islamic date."
  (when (org-hijri--marked-p s)
    (save-match-data
      (string-match org-ts-regexp0 s)
      (let* ((y (string-to-number (match-string 2 s)))
             (m (string-to-number (match-string 3 s)))
             (d (string-to-number (match-string 4 s)))
             (h (list m d y)))
        (and (org-hijri-valid-hijri-p h) h)))))

(defun org-hijri--stamp-string (hijri &optional with-hm hour minute inactive extra)
  "Build the text of a Hijri timestamp.
HIJRI is (MONTH DAY YEAR).  WITH-HM, HOUR and MINUTE add \" HH:MM\"
from HOUR and MINUTE (both must be non-nil).  INACTIVE renders in
square brackets; EXTRA (already carrying its leading spaces, without
the closing bracket) is appended verbatim."
  (format (if inactive "[%s]" "<%s>")
          (concat
           (format "%04d-%02d-%02d %s"
                   (nth 2 hijri) (nth 0 hijri) (nth 1 hijri)
                   org-hijri-marker)
           (if (and with-hm hour minute)
               (format " %02d:%02d" hour minute)
             "")
           (or extra ""))))

;;; Maghrib ----------------------------------------------------------------

(defvar org-hijri--maghrib-cache nil
  "Alist ((MONTH DAY YEAR) . MAGHRIB-HOURS) of computed Maghrib times.
MAGHRIB-HOURS is a float, hours since local midnight (DST adjusted),
or :none when Maghrib cannot be computed for that day.")

(defun org-hijri--maghrib-solar (greg)
  "Sunset hours-float on Gregorian date GREG via `solar.el', or nil."
  (condition-case nil
      (progn
        (require 'solar)
        (let ((res (solar-sunrise-sunset greg)))
          (and res (cadr res) (car (cadr res)))))
    (error nil)))

(defun org-hijri--maghrib-org-awqat (greg)
  "Maghrib hours-float on Gregorian date GREG via org-awqat, or nil.
org-awqat (this repository) computes Maghrib offline from the same
solar astronomy it uses for Salah times, honouring the method preset
(`org-awqat-method'), manual angles and the timezone setting -- so
the Maghrib here is exactly the one its mode line and widgets show.
Needs `org-awqat-latitude'/`org-awqat-longitude' set; errors (e.g.
location unset) fall through to the next source."
  (condition-case nil
      (progn
        (require 'org-awqat)
        (cdr (assq 'maghrib (org-awqat-times-decimal greg))))
    (error nil)))

(defun org-hijri--maghrib-awqat (greg)
  "Maghrib hours-float on Gregorian date GREG via Awqat, or nil.
Uses Awqat's full Maghrib computation (including its safety offset
and any high-latitude adjustment), i.e. what `awqat-times-for-day'
displays as Maghrib."
  (condition-case nil
      (progn
        (require 'awqat)
        (car (awqat--prayer-time greg 4)))
    (error nil)))

(defun org-hijri--maghrib (&optional greg)
  "Maghrib on Gregorian date GREG as a float (hours since midnight).
Defaults to today.  Awqat is used when installed (its Maghrib
includes the safety offset); `solar.el' sunset is the fallback.
Return nil when Maghrib cannot be computed (no location set, polar
day/night, or neither library usable).  Results are cached per day."
  (let ((greg (or greg (calendar-current-date))))
    (let ((hit (assoc greg org-hijri--maghrib-cache)))
      (if hit
          (let ((v (cdr hit)))
            (and (not (eq v :none)) v))
        ;; Source preference: org-awqat (this repo, one location
        ;; setting drives Salah times AND the Hijri rollover), then
        ;; the standalone `awqat' package from MELPA, then solar.el.
        (let ((v (or (org-hijri--maghrib-org-awqat greg)
                     (org-hijri--maghrib-awqat greg)
                     (org-hijri--maghrib-solar greg))))
          (setq org-hijri--maghrib-cache
                (cons (cons greg (if v v :none))
                      org-hijri--maghrib-cache))
          ;; Keep the cache from growing across long sessions.
          (when (> (length org-hijri--maghrib-cache) 8)
            (setq org-hijri--maghrib-cache
                  (seq-take org-hijri--maghrib-cache 8)))
          v)))))

(defun org-hijri--now-hours ()
  "Current local time as a float, hours since midnight."
  (let ((dt (decode-time)))
    (+ (nth 2 dt) (/ (nth 1 dt) 60.0) (/ (nth 0 dt) 3600.0))))

(defun org-hijri--after-maghrib-p ()
  "Non-nil when Maghrib has passed today (and is computable)."
  (and org-hijri-maghrib-rollover
       (let ((maghrib (org-hijri--maghrib)))
         (and maghrib (>= (org-hijri--now-hours) maghrib)))))

(defun org-hijri-today ()
  "Current Islamic date (MONTH DAY YEAR), rolling over at Maghrib.
Between midnight and Maghrib this is the Hijri date whose daytime is
today; from Maghrib until midnight it is tomorrow's Hijri date, i.e.
the Islamic day has already begun."
  (calendar-islamic-from-absolute (org-hijri-today-absolute)))

(defun org-hijri-today-absolute ()
  "Absolute day number of the current Islamic day's daytime.
The Islamic day starting at today's Maghrib has its daytime
tomorrow, so after Maghrib this returns tomorrow's absolute day."
  (+ (time-to-days (current-time))
     (if (org-hijri--after-maghrib-p) 1 0)))

(defun org-hijri--gregorian-time-of-hijri-today ()
  "Internal Emacs time of the current Hijri day's daytime.
Used as the default date for Hijri reading prompts: after Maghrib
this is tomorrow, matching `org-hijri-today'."
  (let ((g (calendar-gregorian-from-absolute (org-hijri-today-absolute))))
    (org-encode-time 0 0 0 (nth 1 g) (nth 0 g) (nth 2 g))))

(defun org-hijri-maghrib-string ()
  "Maghrib time today as \"18:23\", or nil when unknown."
  (let ((m (org-hijri--maghrib)))
    (when m
      (format "%02d:%02d" (floor m)
              (floor (* 60 (- m (floor m))))))))

;;; Advice: parsing ---------------------------------------------------------

(defun org-hijri--parse-time-string-advice (orig-fun s &optional nodefault)
  "Convert Hijri-marked dates to their Gregorian equivalents.
Around-advice on `org-parse-time-string': when S carries the Hijri
marker, its numerals are read as an Islamic date and the returned
decoded time is the Gregorian daytime of that Islamic day.  Time
fields (HH:MM) pass through unchanged.  Everything in Org that
converts a timestamp string into a date -- org-element's timestamp
parser, planning lines, clocking, agenda -- funnels through this
function, so this single advice makes the whole of Org read Hijri
dates.  Gregorian stamps are returned exactly as before.

Invalid Hijri numerals (day beyond the month, month 13, year < 1)
fall back to the plain Gregorian reading rather than erroring, so
that font-lock and element parsing never break."
  (let ((std (funcall orig-fun s nodefault)))
    (if (and org-hijri-mode (org-hijri--marked-p s))
        (if-let* ((h (org-hijri--parse-hijri s))
                  (g (org-hijri-gregorian-from-hijri h)))
            (save-match-data
              (string-match org-ts-regexp0 s)
              (list 0
                    (cond ((match-beginning 8)
                           (string-to-number (match-string 8 s)))
                          (nodefault nil)
                          (t 0))
                    (cond ((match-beginning 7)
                           (string-to-number (match-string 7 s)))
                          (nodefault nil)
                          (t 0))
                    (nth 1 g) (nth 0 g) (nth 2 g)
                    nil -1 nil))
          ;; Invalid numerals: keep the Gregorian reading.
          std)
      std)))

;;; Advice: day-number conversion (agenda, deadlines, scheduled) ------------

(defun org-hijri--string-to-absolute-advice (orig-fun s &optional daynr prefer
                                                      buffer pos)
  "Apply the Maghrib rollover to Hijri-marked timestamps.
Around-advice on `org-time-string-to-absolute'.  Between Maghrib and
midnight the Islamic day has already advanced: an entry dated with
tomorrow's Hijri date is due tonight.  Shift such entries one day
earlier, but only when the query concerns the current day (DAYNR nil
or today), so past and future day views keep their historical
meaning.  Gregorian timestamps are never shifted."
  (let ((abs (funcall orig-fun s daynr prefer buffer pos)))
    (if (and org-hijri-mode
             org-hijri-maghrib-rollover
             (org-hijri--marked-p s)
             (org-hijri--after-maghrib-p)
             (or (null daynr)
                 (= daynr (time-to-days (current-time)))))
        (1- abs)
      abs)))

;;; Advice: repeaters (org-closest-date) ------------------------------------

(defun org-hijri--add-islamic-months (hijri n)
  "Add N Islamic months to HIJRI (MONTH DAY YEAR).
The day is clamped to the last day of the target month: one month
after 30 Ramadan is 29 Shawwal."
  (let* ((mi (+ (* 12 (1- (nth 2 hijri))) (1- (nth 0 hijri)) n))
         (y (1+ (floor mi 12)))
         (m (1+ (mod mi 12))))
    (org-hijri--clamp-islamic m (nth 1 hijri) y)))

(defun org-hijri--closest-date-advice (orig-fun start current prefer)
  "Step Hijri repeaters through the Islamic calendar.
Around-advice on `org-closest-date': for a Hijri-marked START with a
repeater, occurrences advance through the Islamic calendar -- `+N m'
and `+N y' by Islamic months and years (about 354 days a year) with
day clamping as in `org-hijri--add-islamic-months', `+Nd'/`+Nw' on
absolute days -- and the \"current\" day for finding the active
occurrence is the already-advanced Islamic day when Maghrib has
passed (see `org-hijri--string-to-absolute-advice', which applies the
matching one-day shift to the result).  Only void repeaters (`+0')
and hourly repeaters are left to the original implementation."
  (if (or (not org-hijri-mode)
          (not (org-hijri--marked-p start))
          (not (string-match "\\+\\([0-9]+\\)\\([hdwmy]\\)" start)))
      (funcall orig-fun start current prefer)
    (let ((value (string-to-number (match-string 1 start)))
          (type (match-string 2 start)))
      (if (or (= 0 value) (equal type "h"))
          ;; Void repeater or hourly repeater: original logic.
          (funcall orig-fun start current prefer)
        (let* ((sday (calendar-islamic-to-absolute
                      (org-hijri--parse-hijri start)))
               (cday (calendar-absolute-from-gregorian
                      (org-date-to-gregorian current)))
               ;; After Maghrib the current Islamic day is tomorrow's.
               (tiabs (+ cday (if (org-hijri--after-maghrib-p) 1 0)))
               n1 n2)
          (if (<= tiabs sday)
              sday
            (pcase type
              ((or "d" "w")
               (let ((v (if (equal type "w") (* 7 value) value)))
                 (setq n1 (+ sday (* v (/ (- tiabs sday) v)))
                       n2 (+ n1 v))))
              ("m"
               (let* ((hb (calendar-islamic-from-absolute sday))
                      (ht (calendar-islamic-from-absolute tiabs))
                      (total (+ (* 12 (- (nth 2 ht) (nth 2 hb)))
                                (- (nth 0 ht) (nth 0 hb))
                                (if (> (nth 1 ht) (nth 1 hb)) 0 -1)))
                      (months (* (/ total value) value))
                      (before (org-hijri--add-islamic-months hb months)))
                 (setq n1 (calendar-islamic-to-absolute before)
                       n2 (calendar-islamic-to-absolute
                           (org-hijri--add-islamic-months
                            (calendar-islamic-from-absolute n1) value)))))
              ("y"
               (let* ((hb (calendar-islamic-from-absolute sday))
                      (ht (calendar-islamic-from-absolute tiabs))
                      (years (* (/ (- (nth 2 ht) (nth 2 hb)
                                      (if (or (> (nth 0 ht) (nth 0 hb))
                                              (and (= (nth 0 ht) (nth 0 hb))
                                                   (> (nth 1 ht) (nth 1 hb))))
                                          0 1))
                                   value)
                                value))
                      (before (org-hijri--clamp-islamic
                               (nth 0 hb) (nth 1 hb)
                               (+ (nth 2 hb) years))))
                 (setq n1 (calendar-islamic-to-absolute before)
                       n2 (calendar-islamic-to-absolute
                           (org-hijri--clamp-islamic
                            (nth 0 before) (nth 1 before)
                            (+ (nth 2 before) value)))))))
            ;; Same PREFER handling as the original.
            (cond
             ((eq prefer 'past)   (if (= tiabs n2) n2 n1))
             ((eq prefer 'future) (if (= tiabs n1) n1 n2))
             (t (if (> (abs (- tiabs n1)) (abs (- tiabs n2))) n2 n1)))))))))

;;; Advice: insertion -------------------------------------------------------

(defvar org-hijri--insert-hijri nil
  "When dynamically bound non-nil, timestamps are inserted as Hijri.
Bound by `org-hijri-deadline' and `org-hijri-schedule' around Org's
planning commands, so DEADLINE:/SCHEDULED: lines get Hijri stamps
without reimplementing them.")

(defun org-hijri--read-date-default-advice (orig-fun &optional with-time to-time
                                                     from-string prompt
                                                     default-time default-input
                                                     inactive)
  "Default the planning prompt to the current Hijri day.
Around-advice on `org-read-date': while `org-hijri--insert-hijri' is
bound and no default was supplied by Org, offer the Hijri today's
daytime as the default date (after Maghrib that is tomorrow, in step
with `org-hijri-today').  All standard prompt features (relative
dates, calendar popup, times) keep working."
  (funcall orig-fun with-time to-time from-string prompt
           (or default-time
               (and org-hijri--insert-hijri
                    (org-hijri--gregorian-time-of-hijri-today)))
           default-input inactive))

(defun org-hijri--insert-timestamp-advice (orig-fun time &optional with-hm
                                                     inactive pre post extra)
  "Emit a Hijri timestamp when requested via `org-hijri--insert-hijri'.
Around-advice on `org-insert-timestamp'; used by the Hijri planning
commands so that `org-add-planning-info' writes <... Hijri> stamps.
TIME is the Gregorian internal time of the day to write."
  (if (not org-hijri--insert-hijri)
      (funcall orig-fun time with-hm inactive pre post extra)
    (org-fold-core-ignore-modifications
      (insert-before-markers-and-inherit (or pre ""))
      (let* ((h (calendar-islamic-from-absolute (time-to-days time)))
             (hm (and with-hm (decode-time time)))
             ;; Ranges end ("extra" as list) are not yet supported for
             ;; Hijri stamps; ignore them rather than corrupt the text.
             (extra (unless (listp extra) extra))
             (stamp (org-hijri--stamp-string
                     h with-hm
                     (and hm (nth 2 hm)) (and hm (nth 1 hm))
                     inactive extra)))
        (insert-before-markers-and-inherit stamp)
        (insert-before-markers-and-inherit (or post ""))
        (setq org-last-inserted-timestamp stamp)
        stamp))))

;;; Advice: editing a stamp at point (S-arrows, org-timestamp-change) -------

;; Same structure as `org-ts-regexp1' (groups: 1 innards, 2 year, 3
;; month, 4 day, 5 marker/weekday, 6 time, 7 hour, 8 minute) but
;; without the 16-character suffix limit of `org-ts-regexp2/3', which
;; truncates long Hijri stamps like <1446-06-15 Hijri 10:00 +1w>.
(defconst org-hijri--stamp-regexp
  (concat "[[<]" org-ts-regexp1 "[^]>\n]*[]>]")
  "Regexp matching a (possibly long) Org timestamp, with groups.")

(defun org-hijri--stamp-bounds ()
  "Return (BEG . END) of the timestamp around point, or nil.
Handles stamps whose suffix is longer than `org-ts-regexp2' admits."
  (let ((opoint (point)))
    (or (and (org-at-timestamp-p 'lax)
             (cons (match-beginning 0) (match-end 0)))
        (save-excursion
          (save-match-data
            (when (re-search-backward "[[<]" nil t)
              (let ((beg (point)))
                (when (and (looking-at org-hijri--stamp-regexp)
                           (>= opoint beg)
                           (<= opoint (match-end 0)))
                  (cons beg (match-end 0))))))))))

(defun org-hijri--category-at (pos beg end ts)
  "Classify cursor position POS within stamp [BEG,END) whose text is TS.
Returns the same values as `org-at-timestamp-p' -- symbols `bracket',
`after', `year', `month', `day', `hour', `minute', or an integer
offset from the end of the last known part (used for repeater
editing).  Mirrors `org-at-timestamp-p' over `org-hijri--stamp-regexp'
match data; the Hijri marker occupies the weekday slot (group 5), so
the cursor on the marker counts as `day', as on a weekday name."
  (save-match-data
    (string-match org-hijri--stamp-regexp ts)
    (let ((rel (- pos beg)))
      (cond
       ((= rel 0)                          'bracket)
       ((= rel (1- (- end beg)))           'bracket)
       ((= rel (- end beg))                'after)
       ((org-pos-in-match-range rel 2)     'year)
       ((org-pos-in-match-range rel 3)     'month)
       ((org-pos-in-match-range rel 7)     'hour)
       ((org-pos-in-match-range rel 8)     'minute)
       ((or (org-pos-in-match-range rel 4)
            (org-pos-in-match-range rel 5)) 'day)
       ((and (or (match-end 8) (match-end 5))
             (> rel (or (match-end 8) (match-end 5)))
             (< rel (- end beg)))
        (- rel (or (match-end 8) (match-end 5))))
       (t                                  'day)))))

(defun org-hijri--change-timestamp (orig-fun n what updown &optional suppress-tmp-delay)
  "Change the Hijri timestamp at point by N WHAT, preserving the marker.
WHAT is one of `year', `month', `day', `hour', `minute', `calendar',
nil (cursor-derived), `bracket' or `after'.  Date arithmetic happens
in the Islamic calendar; repeaters, warnings and time ranges are
preserved.  With SUPPRESS-TMP-DELAY, deadline delays like \"--2d\" are
dropped.  ORIG-FUN is the unadvised `org-timestamp-change', used for
the calendar-agnostic bracket toggle."
  (let* ((bounds (org-hijri--stamp-bounds))
         (beg (car bounds))
         (end (cdr bounds))
         (origin (point))
         (ts (buffer-substring-no-properties beg end))
         (inactive (= (char-after beg) ?\[))
         (origin-cat (org-hijri--category-at origin beg end ts)))
    (setq what (or what origin-cat))
    (cond
     ;; Cursor on the brackets: toggle the stamp type (calendar
     ;; agnostic) with the original implementation.
     ((eq what 'bracket)
      (funcall orig-fun n nil updown))
     ;; Cursor after the stamp: nothing to change, but Org would
     ;; rewrite the text in Gregorian; rewrite it in Hijri instead.
     ((eq what 'after)
      (goto-char beg)
      (delete-region beg end)
      (insert-before-markers-and-inherit
       (org-hijri--rewrite-hijri ts)))
     (t
      (let ((h (org-hijri--parse-hijri ts)))
        (if (not h)
            ;; Invalid numerals (should not happen -- the dispatcher
            ;; checked): fall back to the original behavior.
            (funcall orig-fun n what updown)
          (let* (;; The extra text (repeater, warning cookie, range end)
                 ;; is everything after the last standard part -- the
                 ;; minute, or, without a time, the marker/weekday --
                 ;; up to the closing bracket.  Captured structurally
                 ;; instead of with the stock end-anchored regex.
                 (hms-end (save-match-data
                            (and (string-match org-hijri--stamp-regexp ts)
                                 (max (or (match-end 5) 0)
                                      (or (match-end 8) 0)))))
                 (extra (and hms-end
                             (> (length ts) (1+ hms-end))
                             (substring ts hms-end -1)))
                 (with-hm (string-match "^.\\{10\\}.*?[0-9]+:[0-9][0-9]" ts))
                 (dm (max (nth 1 org-time-stamp-rounding-minutes) 1))
                 (t0 (org-parse-time-string ts t))
                 (hour (nth 2 t0))
                 (minute (nth 1 t0))
                 new-h new-hour new-minute)
            ;; SUPPRESS-TMP-DELAY drops deadline delay cookies.
            (when (and extra suppress-tmp-delay)
              (setq extra (replace-regexp-in-string
                           " --[0-9]+[hdwmy]" "" extra)))
            (setq new-hour hour new-minute minute)
            (pcase what
              ((or `year `month `day)
               (setq new-h
                     (calendar-islamic-from-absolute
                      (pcase what
                        (`year
                         (calendar-islamic-to-absolute
                          (org-hijri--clamp-islamic
                           (nth 0 h) (nth 1 h) (+ (nth 2 h) n))))
                        (`month
                         (calendar-islamic-to-absolute
                          (org-hijri--add-islamic-months h n)))
                        (`day
                         (+ (calendar-islamic-to-absolute h) n))))))
              (`hour
               (let* ((g (org-hijri-gregorian-from-hijri h))
                      (time (org-encode-time
                             0 minute (+ hour n)
                             (nth 1 g) (nth 0 g) (nth 2 g)))
                      (dt (decode-time time)))
                 (setq new-minute (nth 1 dt)
                       new-hour (nth 2 dt)
                       new-h (calendar-islamic-from-absolute
                              (time-to-days time)))))
              (`minute
               (let* ((increment (if (and updown
                                          (eq origin-cat 'minute)
                                          (not current-prefix-arg))
                                     (* dm (cond ((> n 0) 1)
                                                 ((< n 0) -1)
                                                 (t 0)))
                                   n))
                      (g (org-hijri-gregorian-from-hijri h))
                      (time (org-encode-time
                             0 (+ minute increment) hour
                             (nth 1 g) (nth 0 g) (nth 2 g)))
                      (dt (decode-time time)))
                 (setq new-minute (nth 1 dt)
                       new-hour (nth 2 dt)
                       new-h (calendar-islamic-from-absolute
                              (time-to-days time)))))
              (`calendar
               (let ((cal-date (org-get-date-from-calendar)))
                 (setq new-h (org-hijri-hijri-from-gregorian
                              (list (nth 0 cal-date) (nth 1 cal-date)
                                    (nth 2 cal-date))))))
              ;; Repeater position (integer) or anything else: date
              ;; and time unchanged, extra text edited below.
              (_ (setq new-h h)))
            (when (integerp what)
              (setq extra (org-modify-ts-extra extra what n dm)))
            (when (and (memq what '(hour minute))
                       extra
                       (string-match "-\\([012][0-9]\\):\\([0-5][0-9]\\)"
                                     extra))
              (setq extra (org-modify-ts-extra
                           extra (if (eq what 'hour) 2 5) n dm)))
            ;; Rewrite the stamp, keeping point in the same part.
            (let ((text (org-hijri--stamp-string
                         new-h with-hm new-hour new-minute inactive extra)))
              (goto-char beg)
              (delete-region beg end)
              (insert-before-markers-and-inherit text)
              (setq org-last-changed-timestamp
                    (buffer-substring-no-properties
                     beg (+ beg (length text))))
              (save-match-data
                (looking-at org-hijri--stamp-regexp)
                (let ((pos (pcase origin-cat
                             (`day (min (cond ((match-end 5)
                                               (1- (match-end 5)))
                                              ((match-beginning 7))
                                              (t (1- (match-end 1))))
                                        origin))
                             (`hour (min (match-end 7) origin))
                             (`minute (min (1- (match-end 8)) origin))
                             ((pred integerp) (min (1- (match-end 0)) origin))
                             (`after (match-end 0))
                             (_ origin))))
                  (goto-char (min (max pos (point-min)) (point-max)))))
              (org-clock-update-time-maybe)
              (when (and org-calendar-follow-timestamp-change
                         (get-buffer-window calendar-buffer t)
                         (memq what '(day month year)))
                (org-recenter-calendar
                 (calendar-islamic-to-absolute new-h))))))))))))

(defun org-hijri--rewrite-hijri (ts)
  "Return TS's text rebuilt as a Hijri stamp, date and time unchanged.
Used for edits that do not move the date (e.g. cursor after the
stamp) so that the marker survives Org's rewrite."
  (let* ((inactive (= (string-to-char ts) ?\[)))
         (h (org-hijri--parse-hijri ts))
         (hms-end (save-match-data
                    (and (string-match org-hijri--stamp-regexp ts)
                         (max (or (match-end 5) 0)
                              (or (match-end 8) 0)))))
         (extra (and hms-end (> (length ts) (1+ hms-end))
                     (substring ts hms-end -1)))
         (with-hm (string-match "^.\\{10\\}.*?[0-9]+:[0-9][0-9]" ts))
         (t0 (and h (org-parse-time-string ts t))))
    (if h
        (org-hijri--stamp-string h with-hm
                                 (nth 2 t0) (nth 1 t0)
                                 inactive extra)
      ;; Not parseable: leave the text alone.
      ts)))

(defun org-hijri--timestamp-change-advice (orig-fun n &optional what updown
                                                   suppress-tmp-delay)
  "Dispatch to the Hijri implementation for marked stamps.
Around-advice on `org-timestamp-change'.  Unmarked timestamps are
handled entirely by the original."
  (if (not org-hijri-mode)
      (funcall orig-fun n what updown suppress-tmp-delay)
    (let* ((bounds (org-hijri--stamp-bounds))
           (ts (and bounds
                    (buffer-substring-no-properties
                     (car bounds) (cdr bounds)))))
      (if (not (and ts (org-hijri--marked-p ts)))
          (funcall orig-fun n what updown suppress-tmp-delay)
        (org-hijri--change-timestamp orig-fun n what updown suppress-tmp-delay)))))

;;; Reading and inserting Hijri dates ---------------------------------------

(defun org-hijri-read-date (&optional prompt default with-time)
  "Read a date for a Hijri timestamp, Hijri-aware.
PROMPT defaults to \"Date (Hijri)\".  DEFAULT is the default internal
time (defaults to the current Hijri day, see `org-hijri-today').  The
calendar popup shows Gregorian days, so the prompt also tells you the
current Hijri date and its Maghrib rollover time.  WITH-TIME asks for
a time of day.  Returns (TIME TIME-WAS-GIVEN)."
  (let* ((default (or default (org-hijri--gregorian-time-of-hijri-today)))
         (prompt (or prompt "Date (Hijri)"))
         (org-time-was-given nil))
    (list (org-read-date with-time 'to-time
                         nil
                         (format "%s [Hijri today: %s%s]"
                                 prompt
                                 (org-hijri--hijri-string (org-hijri-today))
                                 (if (org-hijri-maghrib-string)
                                     (format ", rollover %s"
                                             (org-hijri-maghrib-string))
                                   ""))
                         default)
          org-time-was-given)))

(defun org-hijri-timestamp (&optional with-time inactive)
  "Insert a Hijri timestamp at point.
With one prefix argument (WITH-TIME), include a time of day; with
two, insert an inactive timestamp [.. Hijri].  You are prompted for
the date (see `org-hijri-read-date'); the Hijri date written is the
one whose daytime is the chosen Gregorian day."
  (interactive "P")
  (let* ((inactive (equal with-time '(16)))
         (with-time (and with-time (not inactive)))
         (res (org-hijri-read-date nil nil with-time))
         (time (car res))
         (with-hm (and with-time (cadr res)))
         (h (calendar-islamic-from-absolute (time-to-days time)))
         (hm (and with-hm (decode-time time)))
         (stamp (org-hijri--stamp-string
                 h (and hm)
                 (and hm (nth 2 hm)) (and hm (nth 1 hm))
                 inactive)))
    (insert stamp)
    (setq org-last-inserted-timestamp stamp)
    stamp))

(defun org-hijri-deadline (&optional arg)
  "Insert or change a DEADLINE with a Hijri timestamp.
Like `org-deadline' -- same prompt, same prefix-arg behavior, and
relative dates like \"+3d\" all work -- but the timestamp is written
in the Islamic calendar: `DEADLINE: <1447-01-01 Hijri>'.  The default
date offered is the current Hijri day."
  (interactive "P")
  (let ((org-hijri--insert-hijri t))
    (org-deadline arg)))

(defun org-hijri-schedule (&optional arg)
  "Insert or change a SCHEDULED timestamp in the Islamic calendar.
Like `org-schedule', with the same prompt, but the timestamp is
written as Hijri.  The default date offered is the current Hijri
day."
  (interactive "P")
  (let ((org-hijri--insert-hijri t))
    (org-schedule arg)))

(defun org-hijri-show ()
  "Message the current Hijri date and when it rolls over."
  (interactive)
  (message "Hijri date: %s (day starts at Maghrib%s)"
           (org-hijri--hijri-string (org-hijri-today))
           (or (and (org-hijri-maghrib-string)
                    (concat " " (org-hijri-maghrib-string)))
               " -- unknown, set calendar-latitude/longitude")))

(defun org-hijri-agenda (&optional span)
  "Show the agenda starting at the current Hijri day.
Like `org-agenda-list', but the first day is the current Islamic day
(which, with `org-hijri-maghrib-rollover', is already tomorrow's
Gregorian day after Maghrib).  SPAN has the same meaning as in
`org-agenda-list'."
  (interactive "P")
  (require 'org-agenda)
  (org-agenda-list span (org-hijri-today-absolute)))

;;; Agenda day headers ------------------------------------------------------

(defvar org-hijri--saved-agenda-format-date nil
  "The value `org-agenda-format-date' had before `org-hijri-mode'.")

(declare-function org-agenda-format-date-aligned "org-agenda" (date))

(defun org-hijri--agenda-format-date (date)
  "Agenda day-header formatter with the Hijri date appended.
DATE is (MONTH DAY YEAR).  Calls the previously configured formatter
and appends the Hijri date of the day; the current day also shows its
Maghrib rollover time."
  (let* ((base (cond ((functionp org-hijri--saved-agenda-format-date)
                      (funcall org-hijri--saved-agenda-format-date date))
                     ((stringp org-hijri--saved-agenda-format-date)
                      (format-time-string
                       org-hijri--saved-agenda-format-date
                       (org-time-from-absolute
                        (calendar-absolute-from-gregorian date))))
                     (t (org-agenda-format-date-aligned date))))
         (h (org-hijri-hijri-from-gregorian date))
         (today-g (calendar-gregorian-from-absolute
                   (time-to-days (current-time))))
         (suffix (format "%s%s"
                         (org-hijri--hijri-string h)
                         (if (and org-hijri-maghrib-rollover
                                  (calendar-date-equal date today-g)
                                  (org-hijri-maghrib-string))
                             (format " (day rolls over %s)"
                                     (org-hijri-maghrib-string))
                           ""))))
    (concat base
            (if (string-suffix-p "\n" base) "   " "  ")
            suffix)))

(defun org-hijri--agenda-setup ()
  "Install or remove the agenda day-header formatter."
  (if org-hijri-mode
      (unless (eq org-agenda-format-date 'org-hijri--agenda-format-date)
        (setq org-hijri--saved-agenda-format-date org-agenda-format-date
              org-agenda-format-date 'org-hijri--agenda-format-date))
    (when (eq org-agenda-format-date 'org-hijri--agenda-format-date)
      (setq org-agenda-format-date
            (or org-hijri--saved-agenda-format-date
                'org-agenda-format-date-aligned)
            org-hijri--saved-agenda-format-date nil))))

;;; Font lock ---------------------------------------------------------------

(defun org-hijri--font-lock-matcher (limit)
  "Font-lock matcher for Hijri-marked timestamps up to LIMIT.
The marker test must not disturb the buffer match data (it matches
against a string internally), so it runs under `save-match-data' --
font-lock reads the match data after this returns."
  (catch 'found
    (while (re-search-forward org-hijri--stamp-regexp limit t)
      (save-match-data
        (when (org-hijri--marked-p (match-string 1))
          (throw 'found t))))
    nil))

(defun org-hijri--font-lock-setup ()
  "Add the Hijri timestamp keyword in an Org buffer."
  (when org-hijri-mode
    (font-lock-add-keywords
     'org-mode
     '((org-hijri--font-lock-matcher (0 'org-hijri-marker-face t)))
     'append)))

(defun org-hijri--refontify-all (&optional add)
  "Refontify every Org buffer after a mode change.
With ADD non-nil (mode enabled), add the Hijri keyword; otherwise
remove it."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'org-mode)
        (font-lock-remove-keywords
         'org-mode
         '((org-hijri--font-lock-matcher (0 'org-hijri-marker-face t))))
        (when add
          (font-lock-add-keywords
           'org-mode
           '((org-hijri--font-lock-matcher (0 'org-hijri-marker-face t)))
           'append))
        (when font-lock-mode
          (font-lock-flush))))))

;;; Maghrib announcement timer ----------------------------------------------

(defvar org-hijri--maghrib-timer nil
  "Timer that fires at Maghrib to announce the Hijri rollover.")

(defun org-hijri--schedule-maghrib ()
  "Schedule the next Maghrib announcement."
  (when org-hijri--maghrib-timer
    (cancel-timer org-hijri--maghrib-timer)
    (setq org-hijri--maghrib-timer nil))
  (when (and org-hijri-mode org-hijri-announce-maghrib
             org-hijri-maghrib-rollover)
    (let ((m (org-hijri--maghrib))
          (dt (decode-time)))
      ;; Fire at Maghrib today; re-check after an hour when Maghrib is
      ;; unknown or already past (the next day's value is computed by
      ;; the next round).
      (setq org-hijri--maghrib-timer
            (run-at-time
             (or (and m
                      (< (+ (nth 2 dt) (/ (nth 1 dt) 60.0)
                            (/ (nth 0 dt) 3600.0))
                         m)
                      (max 1 (- (* m 3600)
                                (* 3600 (nth 2 dt))
                                (* 60 (nth 1 dt))
                                (nth 0 dt))))
                 3600)
             nil #'org-hijri--maghrib-fired)))))

(defun org-hijri--maghrib-fired ()
  "Announce the rollover, refresh the agenda, reschedule."
  (when org-hijri-mode
    (when org-hijri-announce-maghrib
      (message "Maghrib -- Hijri date is now %s"
               (org-hijri--hijri-string (org-hijri-today))))
    ;; Refresh a visible agenda so entries that became due tonight
    ;; appear with their new classification.
    (when (and (boundp 'org-agenda-buffer-name)
               (get-buffer org-agenda-buffer-name)
               (get-buffer-window org-agenda-buffer-name t))
      (with-current-buffer org-agenda-buffer-name
        (ignore-errors (org-agenda-redo t))))
    (org-hijri--schedule-maghrib)))

;;; Mode --------------------------------------------------------------------

(defun org-hijri--enable ()
  "Activate the advices, hooks and agenda integration."
  (advice-add 'org-parse-time-string :around
              #'org-hijri--parse-time-string-advice)
  (advice-add 'org-time-string-to-absolute :around
              #'org-hijri--string-to-absolute-advice)
  (advice-add 'org-closest-date :around
              #'org-hijri--closest-date-advice)
  (advice-add 'org-insert-timestamp :around
              #'org-hijri--insert-timestamp-advice)
  (advice-add 'org-read-date :around
              #'org-hijri--read-date-default-advice)
  (advice-add 'org-timestamp-change :around
              #'org-hijri--timestamp-change-advice)
  (add-hook 'org-mode-hook #'org-hijri--font-lock-setup)
  ;; org-agenda may not be loaded yet (it is autoloaded on first use);
  ;; install the day-header formatter now if possible, otherwise when
  ;; org-agenda loads.
  (if (boundp 'org-agenda-format-date)
      (org-hijri--agenda-setup)
    (with-eval-after-load 'org-agenda (org-hijri--agenda-setup)))
  (org-hijri--schedule-maghrib)
  (org-hijri--refontify-all 'add))

(defun org-hijri--disable ()
  "Deactivate everything `org-hijri--enable' installed."
  (advice-remove 'org-parse-time-string #'org-hijri--parse-time-string-advice)
  (advice-remove 'org-time-string-to-absolute
                 #'org-hijri--string-to-absolute-advice)
  (advice-remove 'org-closest-date #'org-hijri--closest-date-advice)
  (advice-remove 'org-insert-timestamp #'org-hijri--insert-timestamp-advice)
  (advice-remove 'org-read-date #'org-hijri--read-date-default-advice)
  (advice-remove 'org-timestamp-change #'org-hijri--timestamp-change-advice)
  (remove-hook 'org-mode-hook #'org-hijri--font-lock-setup)
  (when (boundp 'org-agenda-format-date)
    (org-hijri--agenda-setup))
  (when org-hijri--maghrib-timer
    (cancel-timer org-hijri--maghrib-timer)
    (setq org-hijri--maghrib-timer nil))
  (org-hijri--refontify-all nil))

;;;###autoload
(define-minor-mode org-hijri-mode
  "Org natively reads and writes Islamic (Hijri) dates.

Stamps marked with `org-hijri-marker' (<1446-06-15 Hijri>) are
parsed, displayed, repeated and edited in the Islamic calendar;
every other date stays Gregorian.  The current Hijri date
(`org-hijri-today') rolls over at Maghrib (from org-awqat, then the
`awqat' package, falling back to `solar.el'), and Hijri-dated agenda
entries become due that evening.  See the Commentary of this file
for the full description."
  :global t
  :group 'org-hijri
  :init-value nil
  (if org-hijri-mode
      (org-hijri--enable)
    (org-hijri--disable)))

(provide 'org-hijri)

;;; org-hijri.el ends here
