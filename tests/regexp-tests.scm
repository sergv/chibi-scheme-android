
(import (chibi) (chibi regexp) (chibi regexp pcre)
        (chibi string) (chibi io) (chibi match) (chibi test))

(define (regexp-match->sexp rx str . o)
  (let ((res (apply regexp-match rx str o)))
    (and res (rx-match->sexp res str))))

(define-syntax test-re
  (syntax-rules ()
    ((test-re res rx str start end)
     (test res (regexp-match->sexp rx str start end)))
    ((test-re res rx str start)
     (test-re res rx str start (string-cursor-end str)))
    ((test-re res rx str)
     (test-re res rx str (string-cursor-start str)))))

(define (regexp-search->sexp rx str . o)
  (let ((res (apply regexp-search rx str o)))
    (and res (rx-match->sexp res str))))

(define-syntax test-re-search
  (syntax-rules ()
    ((test-re-search res rx str start end)
     (test res (regexp-search->sexp rx str start end)))
    ((test-re-search res rx str start)
     (test-re-search res rx str start (string-cursor-end str)))
    ((test-re-search res rx str)
     (test-re-search res rx str (string-cursor-start str)))))

(test-begin "regexp")

(test-re '("ababc" "abab")
         '(: ($ (* "ab")) "c")
         "ababc")

(test-re '("ababc" "abab")
         '(: ($ (* "ab")) "c")
         "xababc"
         1)

(test-re-search '("y") '(: "y") "xy")

(test-re-search '("ababc" "abab")
                '(: ($ (* "ab")) "c")
                "xababc")

(test-re #f
         '(: (* any) ($ "foo" (* any)) ($ "bar" (* any)))
         "fooxbafba")

(test-re '("fooxbarfbar" "fooxbarf" "bar")
         '(: (* any) ($ "foo" (* any)) ($ "bar" (* any)))
         "fooxbarfbar")

(test-re '("abcd" "abcd")
         '($ (* (or "ab" "cd")))
         "abcd")

;; first match is a list of ab's, second match is the last (temporary) cd
(test-re '("abcdc" (("ab") ("cd")) "cd")
         '(: (* (*$ (or "ab" "cd"))) "c")
         "abcdc")

(test-re '("ababc" "abab")
         '(: bos ($ (* "ab")) "c")
         "ababc")
(test-re '("ababc" "abab")
         '(: ($ (* "ab")) "c" eos)
         "ababc")
(test-re '("ababc" "abab")
         '(: bos ($ (* "ab")) "c" eos)
         "ababc")
(test-re #f
         '(: bos ($ (* "ab")) eos "c")
         "ababc")
(test-re #f
         '(: ($ (* "ab")) bos "c" eos)
         "ababc")

(test-re '("ababc" "abab")
         '(: bol ($ (* "ab")) "c")
         "ababc")
(test-re '("ababc" "abab")
         '(: ($ (* "ab")) "c" eol)
         "ababc")
(test-re '("ababc" "abab")
         '(: bol ($ (* "ab")) "c" eol)
         "ababc")
(test-re #f
         '(: bol ($ (* "ab")) eol "c")
         "ababc")
(test-re #f
         '(: ($ (* "ab")) bol "c" eol)
         "ababc")
(test-re '("\nabc\n" "abc")
         '(: (* #\newline) bol ($ (* alpha)) eol (* #\newline))
         "\nabc\n")
(test-re #f
         '(: (* #\newline) bol ($ (* alpha)) eol (* #\newline))
         "\n'abc\n")
(test-re #f
         '(: (* #\newline) bol ($ (* alpha)) eol (* #\newline))
         "\nabc.\n")

(test-re '("ababc" "abab")
         '(: bow ($ (* "ab")) "c")
         "ababc")
(test-re '("ababc" "abab")
         '(: ($ (* "ab")) "c" eow)
         "ababc")
(test-re '("ababc" "abab")
         '(: bow ($ (* "ab")) "c" eow)
         "ababc")
(test-re #f
         '(: bow ($ (* "ab")) eow "c")
         "ababc")
(test-re #f
         '(: ($ (* "ab")) bow "c" eow)
         "ababc")
(test-re '("  abc  " "abc")
         '(: (* space) bow ($ (* alpha)) eow (* space))
         "  abc  ")
(test-re #f
         '(: (* space) bow ($ (* alpha)) eow (* space))
         " 'abc  ")
(test-re #f
         '(: (* space) bow ($ (* alpha)) eow (* space))
         " abc.  ")

(test-re '("beef")
         '(* (/"af"))
         "beef")

(test-re '("12345beef" "beef")
         '(: (* digit) ($ (* (/"af"))))
         "12345beef")

(test-re '("12345BeeF" "BeeF")
         '(: (* digit) (w/nocase ($ (* (/"af")))))
         "12345BeeF")

(test-re #f '(* lower) "abcD")
(test-re '("abcD") '(w/nocase (* lower)) "abcD")

(test '("123" "456" "789") (regexp-extract '(+ digit) "abc123def456ghi789"))
(test '("123" "456" "789") (regexp-extract '(* digit) "abc123def456ghi789"))
(test '("abc" "def" "ghi") (regexp-split '(+ digit) "abc123def456ghi789"))
(test '("a" "b" "c" "d" "e" "f" "g" "h" "i")
    (regexp-split '(* digit) "abc123def456ghi789"))

(test "abc def" (regexp-replace '(+ space) "abc \t\n def" " "))
(test "  abc-abc"
    (regexp-replace '(: ($ (+ alpha)) ":" (* space)) "  abc: " '(1 "-" 1)))
(test "  abc-  abc"
    (regexp-replace '(: ($ (+ alpha)) ":" (* space)) "  abc: " '(1 "-" pre 1)))

(test " abc d ef " (regexp-replace-all '(+ space) "  abc \t\n d ef  " " "))

(define (subst-matches matches input subst)
  (define (submatch n)
    (rx-match-submatch matches input n))
  (and
   matches
   (call-with-output-string
     (lambda (out)
       (call-with-input-string subst
         (lambda (in)
           (let lp ()
             (let ((c (read-char in)))
               (cond
                ((not (eof-object? c))
                 (case c
                   ((#\&)
                    (display (or (submatch 0) "") out))
                   ((#\\)
                    (let ((c (read-char in)))
                      (if (char-numeric? c)
                          (let lp ((res (list c)))
                            (if (and (char? (peek-char in))
                                     (char-numeric? (peek-char in)))
                                (lp (cons (read-char in) res))
                                (display
                                 (or (submatch (string->number
                                                (list->string (reverse res))))
                                     "")
                                 out)))
                          (write-char c out))))
                   (else
                    (write-char c out)))
                 (lp)))))))))))

(define (test-pcre line)
  (match (string-split line #\tab)
    ((pattern input result subst output)
     (let ((name (string-append pattern " " input " " result " " subst)))
       (cond
        ((equal? "c" result)
         (test-error name (regexp-search (pcre->sre pattern) input)))
        ((equal? "n" result)
         (test-assert name (not (regexp-search (pcre->sre pattern) input))))
        (else
         (test name output
           (subst-matches (regexp-search (pcre->sre pattern) input)
                          input
                          subst))))))
    (else
     (error "invalid regex test line" line))))

(test-group "pcre"
  (call-with-input-file "tests/re-tests.txt"
    (lambda (in)
      (for-each
       (lambda (line) (test-pcre line))
       (port->list read-line in)))))

(test-end)
