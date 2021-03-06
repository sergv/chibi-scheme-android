;; app.scm -- unified option parsing and config
;; Copyright (c) 2012-2013 Alex Shinn.  All rights reserved.
;; BSD-style license: http://synthcode.com/license.txt

;;> Parses command-line options into a config object.

(define (parse-option prefix conf-spec args fail)
  (define (lookup-conf-spec conf-spec syms strs)
    (let ((sym (car syms))
          (str (car strs)))
      (cond
       ((= 1 (length syms))
        (let lp ((ls conf-spec))
          (and (pair? ls)
               (let ((x (car ls)))
                 (cond
                  ((eq? sym (car x)) x)
                  ((and (pair? (cddr x)) (member str (car (cddr x)))) x)
                  ((and (pair? (cddr x)) (member `(not ,str) (car (cddr x))))
                   `(not ,x))
                  (else (lp (cdr ls))))))))
       (else
        (let lp ((ls conf-spec))
          (and (pair? ls)
               (let ((x (car ls)))
                 (cond
                  ((or (eq? sym (car x))
                       (and (pair? (cddr x)) (member str (car (cddr x)))))
                   (let ((type (cadr x)))
                     (if (not (and (pair? type) (eq? 'conf (car type))))
                         (error "option prefix not a subconf" sym)
                         (lookup-conf-spec (cdr type) (cdr syms) (cdr strs)))))
                  (else (lp (cdr ls)))))))))))
  (define (lookup-short-option ch spec)
    (let lp ((ls spec))
      (and (pair? ls)
           (let ((x (car ls)))
             (cond
              ((and (pair? (cddr x)) (memv ch (car (cddr x))))
               x)
              ((and (pair? (cddr x)) (member `(not ,ch) (car (cddr x))))
               `(not ,x))
              (else (lp (cdr ls))))))))
  (define (parse-conf-spec str args)
    (let* ((strs (string-split str #\.))
           (syms (map string->symbol strs))
           (spec (lookup-conf-spec conf-spec syms strs)))
      (cond
       ((not spec)
        #f)
       ((and (pair? spec) (eq? 'not (car spec)))
        (cons (cons (append prefix (list (car spec))) #f) args))
       ((eq? 'boolean (cadr spec))
        (cons (cons (append prefix (list (car spec))) #t) args))
       ((null? args)
        (error "missing argument to option " str))
       (else
        (cons (cons (append prefix syms) (car args)) (cdr args))))))
  (define (parse-long-option str args)
    (let* ((str+val (string-split str #\= 2))
           (str (car str+val))
           (args (if (pair? (cdr str+val)) (cons (cadr str+val) args) args)))
      (or (parse-conf-spec str args)
          (and (string-prefix? "no-" str)
               (let ((res (parse-long-option (substring str 3) args)))
                 (cond
                  ((not res)
                   #f)
                  ((not (boolean? (cdar res)))
                   (error "'no-' prefix only valid on boolean options"))
                  (else
                   `(((,@prefix ,(caar res)) . ,(not (cdar res)))
                     ,@(cdr res)))))))))
  (define (parse-short-option str args)
    (let* ((ch (string-ref str 0))
           (x (lookup-short-option ch conf-spec)))
      (cond
       ((not x)
        #f)
       ((and (pair? x) (eq? 'not (car x)))
        (cons (cons (append prefix (list (car (cadr x)))) #f)
              (if (= 1 (string-length str))
                  args
                  (cons (string-append "-" (substring str 1)) args))))
       ((eq? 'boolean (cadr x))
        (cons (cons (append prefix (list (car x))) #t)
              (if (= 1 (string-length str))
                  args
                  (cons (string-append "-" (substring str 1)) args))))
       ((> (string-length str) 1)
        (cons (cons (append prefix (list (car x))) (substring str 1)) args))
       ((null? args)
        (error "missing argument to option " x))
       (else
        (cons (cons (append prefix (list (car x))) (car args)) (cdr args))))))
  (or (if (eqv? #\- (string-ref (car args) 1))
          (parse-long-option (substring (car args) 2) (cdr args))
          (parse-short-option (substring (car args) 1) (cdr args)))
      (fail prefix conf-spec (car args) args)))

(define (parse-options prefix conf-spec orig-args fail)
  (let lp ((args orig-args)
           (opts (make-conf '() #f (cons 'options orig-args) #f)))
    (cond
     ((null? args)
      (cons opts args))
     ((or (member (car args) '("" "-" "--"))
          (not (eqv? #\- (string-ref (car args) 0))))
      (cons opts (if (equal? (car args) "--") (cdr args) args)))
     (else
      (let ((val+args (parse-option prefix conf-spec args fail)))
        (lp (cdr val+args)
            (conf-set opts (caar val+args) (cdar val+args))))))))

(define (parse-app prefix spec opt-spec args config . o)
  (define (next-prefix prefix name)
    (append (if (null? prefix) '(command) prefix) (list name)))
  (define (prev-prefix prefix)
    (cond ((and (= 2 (length prefix))))
          ((null? prefix) '())
          (else (reverse (cdr (reverse  prefix))))))
  (let ((fail (if (pair? o)
                  (car o)
                  (lambda (prefix spec opt args)
                    ;; TODO: search for closest option
                    (error "unknown option: " opt)))))
    (cond
     ((null? spec)
      (error "no procedure in application spec"))
     ((pair? (car spec))
      (case (caar spec)
        ((@)
         (let* ((new-opt-spec (cadr (car spec)))
                (new-fail
                 (lambda (new-prefix new-spec opt args)
                   (parse-option (prev-prefix prefix) opt-spec args fail)))
                (cfg+args (parse-options prefix new-opt-spec args new-fail))
                (config (conf-append (car cfg+args) config))
                (args (cdr cfg+args)))
           (parse-app prefix (cdr spec) new-opt-spec args config new-fail)))
        ((or)
         (any (lambda (x) (parse-app prefix x opt-spec args config)) (cdar spec)))
        (else
         (if (procedure? (caar spec))
             (list (caar spec) config args) ; TODO: verify, apply defaults
             (parse-app prefix (car spec) opt-spec args config fail)))))
     ((symbol? (car spec))
      (and (pair? args)
           (eq? (car spec) (string->symbol (car args)))
           (let ((prefix (next-prefix prefix (car spec))))
             (parse-app prefix (cdr spec) opt-spec (cdr args) config fail))))
     ((procedure? (car spec))
      (list (car spec) config args))
     (else
      (if (not (string? (car spec)))
          (error "unknown application spec" (car spec)))
      (parse-app prefix (cdr spec) opt-spec args config fail)))))

(define (print-command-help command out)
  (cond
   ((and (pair? command) (symbol? (car command)))
    (display "  " out)
    (display (car command) out)
    (cond
     ((find (lambda (x) (and (pair? x) (procedure? (car x)))) command)
      => (lambda (x)
           (let lp ((args (cdr x)) (opt-depth 0))
             (cond
              ((null? args)
               (display (make-string opt-depth #\]) out))
              ((pair? (car args))
               (display " [" out)
               (display (caar args) out)
               (lp (cdr args) (+ opt-depth 1)))
              (else
               (display " " out)
               (display (car args) out)
               (lp (cdr args) opt-depth)))))))
    (cond
     ((find string? command)
      => (lambda (doc-string) (display " - " out) (display doc-string out))))
    (newline out))))

(define (print-option-help option out)
  (let* ((str (symbol->string (car option)))
         (names (if (and (pair? (cdr option)) (pair? (cddr option)))
                    (car (cddr option))
                    '()))
         (pref-str (cond ((find string? names) => values) (else str)))
         (pref-ch (find char? names))
         (doc (find string? (cdr option))))
    ;; TODO: consider aligning these
    (cond
     (pref-ch (display "  -" out) (write-char pref-ch out))
     (else (display "    " out)))
    (cond
     (pref-str
      (display (if pref-ch ", " "  ") out)
      (display "--" out) (display pref-str out)))
    (cond (doc (display " - " out) (display doc out)))
    (newline out)))

(define (print-help name docs commands options . o)
  (let ((out (if (pair? o) (car o) (current-output-port))))
    (display "Usage: " out) (display name out)
    (if (pair? options) (display " [options]" out))
    (case (length commands)
      ((0) (newline out))
      (else
       (display " <command>\nCommands:\n" out)
       (for-each (lambda (c) (print-command-help c out)) commands))
      ((1) (print-command-help (car commands) out)))
    (if (pair? options) (display "Options:\n" out))
    (for-each (lambda (o) (print-option-help o out)) options)))

(define (app-help spec args . o)
  (let ((out (if (pair? o) (car o) (current-output-port))))
    (let lp ((ls (cdr spec))
             (docs #f)
             (commands '())
             (options '()))
      (cond
       ((null? ls)
        (print-help (car spec) docs commands options out))
       ((string? (car ls))
        (lp (cdr ls) (car ls) commands options))
       ((and (pair? (car ls)) (eq? '@ (caar ls)))
        (lp (cdr ls) docs commands (append options (cadr (car ls)))))
       ((and (pair? (car ls)) (symbol? (caar ls)))
        ;; don't print nested commands
        (if (pair? commands)
            (print-help (car spec) docs commands options out)
            (if (eq? 'or (caar ls))
                (lp (cdr ls) docs (cdar ls) options)
                (lp (cdr ls) docs (list (car ls)) options))))
       (else
        (lp (cdr ls) docs commands options))))))

(define (app-help-command config spec . args)
  (app-help spec args (current-output-port)))

(define (run-application spec . o)
  (let ((args (if (pair? o) (car o) (command-line))))
    (let ((ls (parse-app '() (cdr spec) '() (cdr args) #f)))
      (if ls
          (apply (car ls) (cadr ls) spec (car (cddr ls)))
          (error "Unknown command: " args)))))
