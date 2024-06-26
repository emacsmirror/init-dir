;;; init-dir.el ---  Init directory instead of just a single file -*- lexical-binding: t; -*-

;; Copyright 2005-2023 Jared Finder
;; Author:              Jared Finder <jared@finder.org>
;; Created:             Feb 22, 2005
;; Version:             0.1-beta
;; Keywords:            extensions, internal
;; URL:                 http://github.com/chaosemer/init-dir
;; Package-Requires:    ((emacs "27.1"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Keep all Emacs configuration in a separate directory that can be
;; under version control with very short init.el change.  Using
;; init-dir is as simple as putting the following single line in the
;; actual init.el file:
;;
;; (load-init-dir)
;;
;; This also comes with a very lightweight init profiler to warn you
;; if your Emacs startup is slow.

;;; Todo:
;;
;; At a high level, this package is intended to provide a smoother
;; init configuration experience.  There are a handful of improvements
;; that would be good to make to that end:
;;
;; Capture runtime and garbage performance info, for display after
;; load.  Display would also have an easy way to reload that file and
;; get new perf data.
;;
;; Improve error messages during load -- Add a link to the location of
;; the read error or the form being evaluated.
;;
;; Improve package debugging -- if selected packages were unable to be
;; activated (indicating they're not installed) display a helpful
;; warning message.
;;
;; If any packages are able to be upgraded, display a helpful message
;; (after loading init in case the user wants to disable this
;; feature).
;;
;; Add unit tests.

;;; Code:

(defun init-dir--file-init-loadable-p (file)
  "Test if FILE should be loaded at Emacs initialization.

FILE: File path to test."
  (and (file-regular-p file)
       (member (file-name-extension file t) load-suffixes)))

(defun init-dir--directory-files-filter
    (directory predicate &optional full match nosort)
  "Return a list of files in DIRECTORY, excluding some files.
Files that don't match PREDICATE will not be included.

DIRECTORY: File path to a directory to list files in.
PREDICATE: Function to call on each file name.  Takes a single
  parameter, the filename, and returns if the file should be
  included in the results.
FULL: If non-nil, return absolute file names.  Otherwise,
  return names relative to the specified directory.
MATCH: A regexp or nil.  If non-nil, return only file names whose
  non-directory part matches this regexp.
NOSORT: If non-nil, the list is returned unsorted.  Otherwise,
  the list is returned sorted with `string-lessp'.

FULL, MATCH, NOSORT have the same meaning as in `directory-files'."
  (let ((files '()))
    (dolist (file (directory-files directory full match nosort))
      (when (funcall predicate file)
        (push file files)))
    (nreverse files)))

(defvar init-dir--long-load-time-warning 0.05
  "Controls if a file gets a warning if it takes too long to load.

Best practice is to increment this using `cl-incf' next to known
slow operations.  This can also be set to nil to completely
disable the long load warning.

Also see `init-dir-load'.")

(defvar init-dir--error-and-warning-list '()
  "Errors and warnings that came up while running `init-dir-load'.")

;;; The core functionality.
;;;###autoload
(defun init-dir-load (&optional dir)
  "Load files from DIR for initialization.

DIR: File path to a directory.  If unset or nil, DIR defaults
  to \"init\" in `user-emacs-directory'.  See info node `Find
  Init'.

The common use here is to have your init file be very short and
keep all configuration in a separate directory.  To use this
behavior, move your configuration to files inside one of these
directories and put just this single line in your init file:

\(init-dir-load)

Files will be loaded (via `load') in alphabetical order.  This is
intended to be used in your init file to load configuration that
is organized across multiple files.  A common pattern is to put
configuration for each mode in its own file.

This will display warnings whenever loading a single file from
the takes longer than `init-dir--long-load-time-warning'.  See
its documentation to see how to handle files known to take a long
time to load."
  (setq dir (or dir (expand-file-name "init" user-emacs-directory))
        init-dir--error-and-warning-list '())

  (mapc #'init-dir--load-single-file
        (delete-dups
         (mapcar #'file-name-sans-extension
                 (init-dir--directory-files-filter
                  dir
                  #'init-dir--file-init-loadable-p
                  t))))

  ;; Display any warnings.
  (when init-dir--error-and-warning-list
    (dolist (message (nreverse init-dir--error-and-warning-list))
      (display-warning 'init message))))

(defun init-dir--load-single-file (file)
  "Load a single file, with additional structure around it.

FILE: File path to a file to load.

FILE has the same meaning as in `load'."
  (let ((prev-time (time-convert nil 'list))
        (debug-ignored-errors '())
        (debug-on-error t)
        (debugger #'init-dir--debugger)
        ;; Dynamic binding intended to be modified by clients.
        (init-dir--long-load-time-warning init-dir--long-load-time-warning))

    (let* (;; This line actually loads the file as a side effect.
           (load-error (catch 'init-dir--load-error (load file) nil))

           (cur-time (time-convert nil 'list))
           (delta-time (float-time (time-subtract cur-time prev-time))))
      (when load-error
        (push (format "Loading `%s' had an error: %S"
                      file (error-message-string load-error))
	      init-dir--error-and-warning-list))
      (when (and init-dir--long-load-time-warning
                 (> delta-time init-dir--long-load-time-warning))
        (push (format "Loading `%s' took %f seconds."
                      file delta-time)
              init-dir--error-and-warning-list)))))

(defun init-dir--debugger (&rest args)
  "Replacement debugger function while running `init-dir--load-single-file'.

ARGS: See `debugger' for the meaning of ARGS."
  (if (eq (car-safe args) 'error)
      ;; This entered the debugger due to an error -- the exact case
      ;; we want to handle specially.
      (throw 'init-dir--load-error (car-safe (cdr-safe args)))
    (apply #'debug args)))

(provide 'init-dir)

;;; init-dir.el ends here
