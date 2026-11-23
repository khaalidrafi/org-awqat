;;; org-awqat-widget.el --- org-awqat home-screen widgets for elwidget -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: GLM 5.3 <glm-5.3@z.ai>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1") (org-awqat "0.1.0") (elwidget "0.3"))
;; Keywords: islam, widgets, android
;; URL: https://github.com/khaalidrafi/org-awqat

;;; Commentary:

;; Home-screen widgets for org-awqat, rendered through the elwidget
;; widget maker (Emacs on Android, emacshell app):

;;   awqat-hijri   -- 2x1: the Hijri date (plus the Gregorian day)
;;   awqat-salah   -- 4x2: next prayer with countdown + all six times
;;   awqat-jamaah  -- 4x1: today's Jama'ah (congregation) times

;; Everything is computed OFFLINE by org-awqat's own engine (the
;; widget never reimplements a formula).  elwidget is a SOFT
;; dependency: this module byte-compiles and tests green without it;
;; only `org-awqat-widget-register' needs elwidget to be loadable.

;; Enable after elwidget:

;;   (with-eval-after-load 'elwidget
;;     (org-awqat-widget-register))

;;; Code:

(require 'org-awqat)

(declare-function elwidget-define "elwidget" (name &rest props))

(defgroup org-awqat-widget nil
  "elwidget home-screen widgets for org-awqat."
  :group 'org-awqat)

(defcustom org-awqat-widget-accent "#a6e3a1"
  "Accent color for the next prayer and the Hijri day."
  :type 'string)

(defcustom org-awqat-widget-dim "#6c7086"
  "Dimmed color for secondary lines."
  :type 'string)

;;; --- Countdown --------------------------------------------------------------

(defun org-awqat-widget--countdown (from to)
  "Human \"1h 23m\" (or \"3d 4h\") from time FROM to TO."
  (let* ((secs (max 0 (- (time-to-seconds to) (time-to-seconds from))))
         (d (floor secs 86400))
         (h (floor (mod secs 86400) 3600))
         (m (floor (mod secs 3600) 60)))
    (cond ((> d 0) (format "%dd %dh" d h))
          ((> h 0) (format "%dh %dm" h m))
          (t (format "%dm" m)))))

(defun org-awqat-widget--next-line ()
  "Widget line for the next prayer (or tomorrow's Fajr)."
  (if-let* ((next (org-awqat-next-prayer))
            (time-val (car next))
            (prayer (cdr next))
            (hhmm (cdr (assq prayer (org-awqat-times)))))
      `(:row (:text ,(format "Next: %s %s"
                             (cdr (assq prayer org-awqat-prayer-labels)) hhmm)
                    :size 22 :bold t :color ,org-awqat-widget-accent)
             (:text ,(concat "in "
                             (org-awqat-widget--countdown
                              (current-time) time-val))
                    :size 14 :color ,org-awqat-widget-dim))
    ;; All of today's prayers are past: tomorrow's Fajr.
    (let* ((tomorrow (calendar-gregorian-from-absolute
                      (1+ (calendar-absolute-from-gregorian
                           (calendar-current-date)))))
           (fajr (cdr (assq 'fajr (org-awqat-times-decimal tomorrow))))
           (fajr-str (or (org-awqat-format-time fajr) "--:--")))
      `(:row (:text ,(format "Next: Fajr %s" fajr-str)
                    :size 22 :bold t :color ,org-awqat-widget-accent)
             (:text "tomorrow" :size 14 :color ,org-awqat-widget-dim)))))

;;; --- Trees -------------------------------------------------------------------

(defun org-awqat-widget--hijri-tree ()
  "The awqat-hijri node tree."
  `(:column (:text ,(org-awqat-format-hijri (org-awqat-today-hijri))
                   :size 22 :bold t :color ,org-awqat-widget-accent
                   :align center)
            (:text ,(format-time-string "%A, %-d %B %Y")
                   :size 13 :color ,org-awqat-widget-dim :align center)))

(defun org-awqat-widget--salah-tree ()
  "The awqat-salah node tree."
  (let* ((times (org-awqat-times))
         (cell (lambda (p)
                 (let ((v (cdr (assq p times))))
                   `(:column (:text ,(cdr (assq p org-awqat-prayer-labels))
                                    :size 12 :color ,org-awqat-widget-dim
                                    :align center)
                             (:text ,v :size 17 :bold t :align center))))))
    `(:column ,(org-awqat-widget--next-line)
              (:bar :height 1 :color ,org-awqat-widget-dim)
              (:row ,@(funcall cell 'fajr) ,@(funcall cell 'sunrise)
                    ,@(funcall cell 'dhuhr))
              (:row ,@(funcall cell 'asr) ,@(funcall cell 'maghrib)
                    ,@(funcall cell 'isha)))))

(defun org-awqat-widget--jamaah-tree ()
  "The awqat-jamaah node tree (today's congregation times)."
  (let ((j (org-awqat-jamaah-get)))
    (if (null j)
        `(:column (:text "Jama'ah today" :size 12
                         :color ,org-awqat-widget-dim)
                  (:text "none set (M-x org-awqat-jamaah-set-at-point)"
                         :size 13))
      `(:column (:text "Jama'ah today" :size 12
                       :color ,org-awqat-widget-dim)
                (:row ,@(mapcar
                         (lambda (cell)
                           `(:column (:text
                                      ,(substring
                                        (cdr (assq (car cell)
                                                   org-awqat-prayer-labels))
                                        0 2)
                                      :size 10 :color ,org-awqat-widget-dim
                                      :align center)
                                     (:text ,(cdr cell) :size 16 :bold t)))
                         j))))))

;;; --- Registration ------------------------------------------------------------

;;;###autoload
(defun org-awqat-widget-register ()
  "Define the org-awqat elwidget specs."
  (interactive)
  (unless (require 'elwidget nil t)
    (error "org-awqat-widget: elwidget is not loadable"))
  (elwidget-define "awqat-hijri"
    :size [2 1] :title "Hijri date"
    :render #'org-awqat-widget--hijri-tree)
  (elwidget-define "awqat-salah"
    :size [4 2] :title "Salah times"
    :render #'org-awqat-widget--salah-tree)
  (elwidget-define "awqat-jamaah"
    :size [4 1] :title "Jama'ah times"
    :render #'org-awqat-widget--jamaah-tree)
  (message "org-awqat-widget: registered awqat-hijri, awqat-salah, awqat-jamaah"))

(provide 'org-awqat-widget)
;;; org-awqat-widget.el ends here
