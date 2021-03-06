
(define-library (chibi regexp)
  (export regexp regexp? regexp-match regexp-search
          regexp-replace regexp-replace-all
          regexp-fold regexp-extract regexp-split
          rx-match? rx-match-num-matches
          rx-match-submatch rx-match-submatch/list
          rx-match->list rx-match->sexp)
  (import (srfi 33) (srfi 69))
  ;; Chibi's char-set library is more factored than SRFI-14.
  (cond-expand
   (chibi
    (import (chibi) (srfi 9) (chibi char-set) (chibi char-set full)))
   (else
    (import (scheme base) (srfi 14))))
  ;; Use string-cursors where available.
  (begin
    (define string-cursor? integer?))
  (cond-expand
   (chibi
    (begin
      (define (string-start-arg s o)
        (if (pair? o) (string-index->offset s (car o)) (string-cursor-start s)))
      (define (string-end-arg s o)
        (if (pair? o) (string-index->offset s (car o)) (string-cursor-end s)))
      (define (string-concatenate-reverse ls)
        (string-concatenate (reverse ls)))))
   (else
    (begin
      (define (string-start-arg s o)
        (if (pair? o) (string-index->offset (car o)) 0))
      (define (string-end-arg s o)
        (if (pair? o) (string-index->offset (car o)) (string-length s)))
      (define string-cursor=? =)
      (define string-cursor<? <)
      (define string-cursor<=? <=)
      (define string-cursor>? >)
      (define string-cursor>=? >=)
      (define string-cursor-ref string-ref)
      (define substring-cursor substring)
      (define (string-offset->index str off) off)
      (define (string-concatenate-reverse ls)
        (apply string-append (reverse ls))))))
  (include "regexp.scm"))
