;; Sayid nREPL middleware client

(require 'sayid-mode)
(require 'sayid-traced-mode)

(defvar sayid-trace-ns-dir nil)
(defvar sayid-meta)

(defvar sayid-buf-spec '("*sayid*" . sayid-mode))
(defvar sayid-traced-buf-spec '("*sayid-traced*" . sayid-traced-mode))
(defvar sayid-selected-buf sayid-buf-spec)

(defvar sayid-ring)
(setq sayid-ring '())

(defun sayid-select-default-buf ()
  (setq sayid-selected-buf sayid-buf-spec))

(defun sayid-select-traced-buf ()
    (setq sayid-selected-buf sayid-traced-buf-spec))

(defun sayid-buf-point ()
  (set-buffer (car sayid-selected-buf))
  (point))

(defun expanded-buffer-file-name ()
  (expand-file-name (buffer-file-name)))
(expanded-buffer-file-name)

(defun sayid-get-trace-ns-dir ()
  (interactive)
  (or sayid-trace-ns-dir
      (let* ((default-dir (file-name-directory (buffer-file-name)))
             (input (expand-file-name
                     (read-directory-name "Scan dir for namespaces : "
                                          default-dir))))
        (setq sayid-trace-ns-dir input)
        input)))

(defun sayid-set-trace-ns-dir ()
  (interactive)
  (let* ((default-dir (file-name-directory (buffer-file-name)))
         (input (expand-file-name
                 (read-directory-name "Scan dir for namespaces : "
                                      (or sayid-trace-ns-dir
                                          default-dir)))))
    (setq sayid-trace-ns-dir input)
    input))

(defun sayid-init-buf ()
  (let ((buf-name- (car sayid-selected-buf)))
    (pop-to-buffer buf-name-)
    (update-buf-pos-to-ring)
    (read-only-mode 0)
    (erase-buffer)
    (get-buffer buf-name-)))

(defun sayid-send-and-message (req)
  (let* ((resp (nrepl-send-sync-request req))
         (x (nrepl-dict-get resp "value")))
    (message x)))

(defun sayid-query-form-at-point ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-query-form-at-point"
                                    "file" (buffer-file-name)
                                    "line" (line-number-at-pos))))

(defun sayid-get-meta-at-point ()
  (interactive)
  (sayid-send-and-message (list "op" "sayid-get-meta-at-point"
                                "source" (buffer-string)
                                "file" (buffer-file-name)
                                "line" (line-number-at-pos))))

(defun sayid-trace-fn-enable ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-"
                                    "file" (buffer-file-name)
                                    "line" (line-number-at-pos))))

(defun sayid-replay-workspace-query-point ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-replay-workspace"))
  (sayid-query-form-at-point))

(defun sayid-replay-with-inner-trace ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-replay-with-inner-trace-at-point"
                                    "source" (buffer-string)
                                    "file" (buffer-file-name)
                                    "line" (line-number-at-pos))))

(defun sayid-buf-replay-with-inner-trace ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-replay-with-inner-trace"
                                    "func" (get-text-property (point) 'fn-name))))

(defun sayid-replay-at-point ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-replay-at-point"
                                    "source" (buffer-string)
                                    "file" (buffer-file-name)
                                    "line" (line-number-at-pos))))

;; DEPRECATE
(defun insert-w-props (s p buf)
  (set-buffer buf)
  (let ((start (point))
        (xxx (insert (or s "")))
        (end (- (point) 1)))
    (set-text-properties start end p buf)))

;; make-symbol is a liar
(defun str-to-sym (s) (car (read-from-string s)))

(defun if-str-to-sym (s)
  (if (stringp s)
      (str-to-sym s)
    s))

(defun first-to-sym (p)
  (list (str-to-sym (first p))
        (second p)))

(defun str-alist-to-sym-alist (sal)
  (apply 'append
         (mapcar 'first-to-sym
                 sal)))

(defun ansi-fg-str->face (s)
  (or (cdr (assoc s '((30 . "black")
                      (31 . "red")
                      (32 . "green")
                      (33 . "yellow")
                      (34 . "#6699FF")
                      (35 . "purple")
                      (36 . "cyan")
                      (37 . "white")
                      (39 . "white"))))
      "white"))

(defun ansi-bg-str->face (s)
  (or (cdr (assoc s '(("40" . "red")
                      ("41" . "orange")
                      ("42" . "yellow")
                      ("43" . "green")
                      ("44" . "blue")
                      ("45" . "purple")
                      ("46" . "red")
                      ("47" . "orange"))))
      "black"))

(defun mk-font-face (p)
  (let ((x (second p)))
    (list (list ':foreground (ansi-fg-str->face (cadr (assoc "fg" x))))
          (list ':background (ansi-bg-str->face (cadr (assoc "bg" x)))))))

(put-text-property 5 15 'face '(:foreground "red") (get-buffer "*sayid*"))

(defun put-all-text-props (props start end buf)
  (dolist (p props)
    (let ((name-sym (if-str-to-sym (car p))))
      (if (eq name-sym 'text-color)
          (progn
            (print (list start end (mk-font-face p)))
            (put-text-property start
                               end
                               'font-lock-face
                               (mk-font-face p)))
        (put-text-property start
                           end
                           (if-str-to-sym (car p))
                           (cadr p)
                           buf)))))

(defun put-text-props-series (series buf)
  (dolist (s series)
    (put-all-text-props (caddr s)
                        (car s)
                        (cadr s)
                        buf)))

(defun write-resp-val-to-buf (val buf)
  (set-buffer buf)
  (insert (car val))
  (put-text-props-series (cadr val) buf))

(put-text-props-series '((1 3 ((a "a13") ( b "b13")))
                         (2 5 ((c "c25") ( d "d25"))))
                       (get-buffer "*scratch*"))

(cadr (assoc 'a '( (a 1))))

;; DEPRECATE
(defun insert-text-prop-alist (pairs buf)
  (dolist (p pairs)
    (insert-w-props (second p)
                    (str-alist-to-sym-list (first p))
                    buf)))



;; DEPRECATE
(defun insert-text-prop-ring (pairs buf)
  (push-buf-state-to-ring pairs)
  (insert-text-prop-alist pairs buf))

;; UNUSED?
(defun insert-traced-name (buf s)
  (insert-w-props (concat "  " s "\n")
                  (list :name s)
                  buf))

;; I have no idea why I seem to need this
(defun read-if-string (v)
  (print v)
  (if (stringp v)
      (read v)
    v))

(defun list-take (n l)
  (butlast l (- (length l) n)))

(defun push-to-ring (v)
  (setq sayid-ring (list-take 5 (cons v sayid-ring))))

(defun peek-first-in-ring ()
  (first sayid-ring))

(defun swap-first-in-ring (v)
  (setq sayid-ring (cons v (cdr sayid-ring))))

(defun cycle-ring ()
  (setq sayid-ring
        (append (cdr sayid-ring)
                (list (first sayid-ring))))
  (first sayid-ring))

(defun cycle-ring-back ()
  (setq sayid-ring
        (append (last sayid-ring)
                (butlast sayid-ring)))
  (first sayid-ring))

(defun update-buf-pos-to-ring ()
  (if (eq sayid-selected-buf sayid-buf-spec)
      (let ((current (peek-first-in-ring)))
        (if current
            (swap-first-in-ring (list (car current)
                                      (sayid-buf-point)))))))

(defun push-buf-state-to-ring (meta-ansi)
  (if (eq sayid-selected-buf sayid-buf-spec)
      (push-to-ring (list meta-ansi (sayid-buf-point)))))

(defun sayid-setup-buf (meta-ansi save-to-ring &optional pos)
  (let ((orig-buf (current-buffer))
        (sayid-buf (sayid-init-buf)))
    (if save-to-ring
        (push-buf-state-to-ring meta-ansi))
    (write-resp-val-to-buf meta-ansi sayid-buf)
    (funcall (cdr sayid-selected-buf))
    (if pos
        (goto-char pos))
    (pop-to-buffer orig-buf)))

(defun colorize ()
  (interactive)
  (mapcar (lambda (x)
            (put-text-property x (+ x 1) 'font-lock-face '(:foreground "red")))
          (number-sequence (point-min) (- (point-max) 1))))

(defun sayid-req-insert-meta-ansi (req)
  (let* ((resp (nrepl-send-sync-request req))
         (x (read-if-string (nrepl-dict-get resp "value")))) ;; WTF
    (sayid-setup-buf x t 1)))

(defun sayid-get-workspace ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-get-workspace")))

(defun sayid-show-traced (&optional ns)
  (interactive)
  (sayid-select-traced-buf)
  (sayid-req-insert-meta-ansi (list "op" "sayid-show-traced"
                                    "ns" ns))
  (sayid-select-default-buf))

(defun sayid-traced-buf-enter ()
  (interactive)
  (sayid-select-traced-buf)
  (let ((name (get-text-property (point) 'name ))
        (ns (get-text-property (point) 'ns)))
    (cond
     ((stringp name) 1) ;; goto func
     ((stringp ns) (sayid-req-insert-meta-ansi (list "op" "sayid-show-traced"
                                                     "ns" ns)))
     (t 0)))
  (sayid-select-default-buf))

(defun sayid-trace-all-ns-in-dir ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-trace-all-ns-in-dir"
                                 "dir" (sayid-set-trace-ns-dir)))
  (sayid-show-traced))

(defun sayid-trace-ns-in-file ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-trace-ns-in-file"
                                 "file" (buffer-file-name)))
  (sayid-show-traced))

(defun sayid-trace-enable-all ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-enable-all-traces"
                                 "file" (buffer-file-name)))
  (sayid-show-traced))


(defun sayid-trace-disable-all ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-disable-all-traces"
                                 "file" (buffer-file-name)))
  (sayid-show-traced))

(defun sayid-traced-buf-inner-trace-fn ()
  (interactive)
  (setq pos (point))
  (setq ns (get-text-property 1 'ns))
  (sayid-select-traced-buf)
  (nrepl-send-sync-request (list "op" "sayid-trace-fn"
                                 "fn-name" (get-text-property (point) 'name)
                                 "fn-ns" (get-text-property (point) 'ns)
                                 "type" "inner"))
  (sayid-show-traced ns)
  (goto-char pos)
  (sayid-select-default-buf))

(defun sayid-traced-buf-outer-trace-fn ()
  (interactive)
  (setq pos (point))
  (setq ns (get-text-property 1 'ns))
  (sayid-select-traced-buf)
  (nrepl-send-sync-request (list "op" "sayid-trace-fn"
                                 "fn-name" (get-text-property (point) 'name)
                                 "fn-ns" (get-text-property (point) 'ns)
                                 "type" "outer"))
  (sayid-show-traced ns)

  (goto-char pos))

(defun sayid-traced-buf-enable ()
  (interactive)
  (setq pos (point))
  (setq ns (get-text-property 1 'ns))
  (sayid-select-traced-buf)
  (nrepl-send-sync-request (list "op" "sayid-trace-fn-enable"
                                 "fn-name" (get-text-property (point) 'name)
                                 "fn-ns" (get-text-property (point) 'ns)))
  (sayid-show-traced ns)
  (goto-char pos)
  (sayid-select-default-buf))

(defun sayid-traced-buf-disable ()
  (interactive)
  (setq pos (point))
  (setq ns (get-text-property 1 'ns))
  (sayid-select-traced-buf)
  (nrepl-send-sync-request (list "op" "sayid-trace-fn-disable"
                                 "fn-name" (get-text-property (point) 'name)
                                 "fn-ns" (get-text-property (point) 'ns)))
  (sayid-show-traced ns)
  (goto-char pos)
  (sayid-select-default-buf))

(defun sayid-traced-buf-remove-trace-fn ()
  (interactive)
  (setq pos (point))
  (setq ns (get-text-property 1 'ns))
  (sayid-select-traced-buf)
  (nrepl-send-sync-request (list "op" "sayid-trace-fn-remove"
                                 "fn-name" (get-text-property (point) 'name)
                                 "fn-ns" (get-text-property (point) 'ns)))
  (sayid-show-traced ns)
  (goto-char pos)
  (sayid-select-default-buf))

(defun sayid-kill-all-traces ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-remove-all-traces"))
  (message "Killed all traces."))

(defun sayid-clear-log ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-clear-log"))
  (message "Cleared log."))

(defun sayid-reset-workspace ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-reset-workspace"))
  (message "Removed traces. Cleared log."))

(defun sayid-eval-last-sexp ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-clear-log"))
  (nrepl-send-sync-request (list "op" "sayid-enable-all-traces"))
  (cider-eval-last-sexp)
  (nrepl-send-sync-request (list "op" "sayid-disable-all-traces"))
  (sayid-get-workspace))

;; REMOVE
(defun sayid-search-line-meta (m n f)
  (let ((head (first m))
        (tail (rest m)))
    (cond ((eq nil head) nil)
          ((funcall f n head)
           head)
          (t (sayid-search-line-meta tail n f)))))

(defun sayid-get-line-meta (m n)
  (let ((head (first m))
        (tail (rest m)))
    (cond ((eq nil head) nil)
          ((>= n (first head))
           (second head))
          (t (sayid-get-line-meta tail n)))))

(defun sayid-buffer-nav-from-point ()
  (interactive)
  (let* ((file (get-text-property (point) 'file))
         (line (get-text-property (point) 'line)))
    (pop-to-buffer (find-file-noselect file))
    (goto-line line)))

(defun sayid-buffer-nav-to-prev ()
  (interactive)
  (forward-line -1)
  (while (and (> (point) (point-min))
              (eq nil (get-text-property (point) 'header)))
    (forward-line -1)))

(defun sayid-buffer-nav-to-next ()
  (interactive)
  (forward-line)
  (while (and (< (point) (point-max))
              (not (eq 1 (get-text-property (point) 'header))))
    (forward-line)))

(defun sayid-query-id-w-mod ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-buf-query-id-w-mod"
                                    "trace-id" (get-text-property (point) 'id)
                                    "mod" (read-string "query modifier: "))))

(defun sayid-query-id ()
  (interactive)
    (sayid-req-insert-meta-ansi (list "op" "sayid-buf-query-id-w-mod"
                                    "trace-id" (get-text-property (point) 'id)
                                    "mod" "")))

(defun sayid-query-fn-w-mod ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-buf-query-fn-w-mod"
                               "fn-name" (get-text-property (point) 'fn-name)
                               "mod" (read-string "query modifier: "))))


(defun sayid-query-fn ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-buf-query-fn-w-mod"
                               "fn-name" (get-text-property (point) 'fn-name)
                               "mod" "")))

(defun sayid-buf-def-at-point ()
  (interactive)
  (sayid-send-and-message (list "op" "sayid-buf-def-at-point"
                                "trace-id" (get-text-property (point) 'id)
                                "path" (get-text-property (point) 'path))))

(defun sayid-buf-inspect-at-point ()
  (interactive)
  (sayid-send-and-message (list "op" "sayid-buf-def-at-point"
                                "trace-id" (get-text-property (point) 'id)
                                "path" (get-text-property (point) 'path)))
  (cider-inspect "$s/*"))

(defun sayid-buf-pprint-at-point ()
  (interactive)
  (sayid-req-insert-meta-ansi (list "op" "sayid-buf-pprint-at-point"
                                    "trace-id" (get-text-property (point) 'id)
                                    "path" (get-text-property (point) 'path))))

(defun sayid-set-printer ()
  (interactive)
  (nrepl-send-sync-request (list "op" "sayid-set-printer"
                                 "printer" (concat (read-string "printer: ")
                                                   " :children")))
  (message "Printer set."))

(defun sayid-buf-back ()
  (interactive)
  (update-buf-pos-to-ring)
  (let ((buf-state (cycle-ring)))
    (sayid-setup-buf (first buf-state)
                     nil
                     (second buf-state))))

(defun sayid-buf-forward ()
  (interactive)
  (update-buf-pos-to-ring)
  (let ((buf-state (cycle-ring-back)))
    (sayid-setup-buf (first buf-state)
                     nil
                     (second buf-state))))

(defun sayid-set-clj-mode-keys ()
  (define-key clojure-mode-map (kbd "C-c s e") 'sayid-eval-last-sexp)
  (define-key clojure-mode-map (kbd "C-c s f") 'sayid-query-form-at-point)
  (define-key clojure-mode-map (kbd "C-c s n") 'sayid-replay-with-inner-trace)
  (define-key clojure-mode-map (kbd "C-c s r") 'sayid-replay-workspace-query-point)
  (define-key clojure-mode-map (kbd "C-c s w") 'sayid-get-workspace)
  (define-key clojure-mode-map (kbd "C-c s t y") 'sayid-trace-all-ns-in-dir)
  (define-key clojure-mode-map (kbd "C-c s t b") 'sayid-trace-ns-in-file) ;; b = buffer
  (define-key clojure-mode-map (kbd "C-c s t e") 'sayid-trace-fn-enable)   ;;TODO
  (define-key clojure-mode-map (kbd "C-c s t E") 'sayid-trace-enable-all)
  (define-key clojure-mode-map (kbd "C-c s t d") 'sayid-trace-fn-disable)   ;;TODO
  (define-key clojure-mode-map (kbd "C-c s t D") 'sayid-trace-disable-all)
  (define-key clojure-mode-map (kbd "C-c s t n") 'sayid-inner-trace-fn)   ;;TODO
  (define-key clojure-mode-map (kbd "C-c s t o") 'sayid-outer-trace-fn)   ;;TODO
  (define-key clojure-mode-map (kbd "C-c s t k") 'sayid-kill-all-traces)
  (define-key clojure-mode-map (kbd "C-c s c") 'sayid-clear-log)
  (define-key clojure-mode-map (kbd "C-c s x") 'sayid-reset-workspace)
  (define-key clojure-mode-map (kbd "C-c s s") 'sayid-show-traced)
  (define-key clojure-mode-map (kbd "C-c s S") 'sayid-show-traced-ns) ;;TODO
  (define-key clojure-mode-map (kbd "C-c s p s") 'sayid-set-printer))

(add-hook 'clojure-mode-hook 'sayid-set-clj-mode-keys)
