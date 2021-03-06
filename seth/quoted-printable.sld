
(define-library (seth quoted-printable)
  (export quoted-printable-encode quoted-printable-encode-string
          quoted-printable-encode-header
          quoted-printable-decode quoted-printable-decode-string)
  (import (scheme base)
          (scheme write)
          (scheme char)
          (srfi 60)
          (srfi 13)
          )
  (cond-expand
   (chibi
    (import (chibi quoted-printable)))
   (chicken
    (import (ports)))
   (gauche
    (import (rfc quoted-printable)))
   (foment
    (import (seth string-read-write))
    )
   (sagittarius
    (import (sagittarius io))
    ))
  (begin

    (cond-expand
     ((or chibi gauche))
     (else

;; quoted-printable.scm -- RFC2045 implementation
;; Copyright (c) 2005-2014 Alex Shinn.  All rights reserved.
;; BSD-style license: http://synthcode.com/license.txt

;;> RFC 2045 quoted printable encoding and decoding utilities.  This
;;> API is backwards compatible with the Gauche library
;;> rfc.quoted-printable.

;;> \schemeblock{
;;> (define (mime-encode-header header value charset)
;;>   (let ((prefix (string-append header ": "))
;;>         (str (ces-convert value "UTF8" charset)))
;;>     (string-append
;;>      prefix
;;>      (quoted-printable-encode-header charset str (string-length prefix)))))
;;> }

(define *default-max-col* 76)

;; Allow for RFC1522 quoting for headers by always escaping ? and _
(define (qp-encode str start-col max-col separator)
  (define (hex i) (integer->char (+ i (if (<= i 9) 48 55))))
  (let ((end (string-length str))
        (buf (make-string max-col)))
    (let lp ((i 0) (col start-col) (res '()))
      (cond
        ((= i end)
         (if (pair? res)
           (string-concatenate (reverse (cons (substring buf 0 col) res))
                               separator)
           (substring buf start-col col)))
        ((>= col (- max-col 3))
         (lp i 0 (cons (substring buf (if (pair? res) 0 start-col) col) res)))
        (else
         (let ((c (char->integer (string-ref str i))))
           (cond
             ((and (<= 33 c 126) (not (memq c '(61 63 95))))
              (string-set! buf col (integer->char c))
              (lp (+ i 1) (+ col 1) res))
             (else
              (string-set! buf col #\=)
              (string-set! buf (+ col 1) (hex (arithmetic-shift c -4)))
              (string-set! buf (+ col 2) (hex (bitwise-and c #b1111)))
              (lp (+ i 1) (+ col 3) res)))))))))

;;> Return a quoted-printable encoded representation of the input
;;> according to the official standard as described in RFC2045.
;;>
;;> ? and _ are always encoded for compatibility with RFC1522
;;> encoding, and soft newlines are inserted as necessary to keep each
;;> lines length less than \var{max-col} (default 76).  The starting
;;> column may be overridden with \var{start-col} (default 0).

(define (quoted-printable-encode-string . o)
  (let ((src (if (pair? o) (car o) (current-input-port)))
        (start-col (if (and (pair? o) (pair? (cdr o))) (cadr o) 0))
        (max-col (if (and (pair? o) (pair? (cdr o)) (pair? (cddr o)))
                     (car (cddr o))
                     *default-max-col*)))
    (qp-encode (if (string? src) src (read-string #f src))
               start-col max-col "=\r\n")))

;;> Variation of the above to read and write to ports.

(define (quoted-printable-encode . o)
  (display (apply quoted-printable-encode-string o)))

;;> Return a quoted-printable encoded representation of string as
;;> above, wrapped in =?ENC?Q?...?= as per RFC1522, split across
;;> multiple MIME-header lines as needed to keep each lines length
;;> less than \var{max-col}.  The string is encoded as is, and the
;;> encoding \var{enc} is just used for the prefix, i.e. you are
;;> responsible for ensuring \var{str} is already encoded according to
;;> \var{enc}.

(define (quoted-printable-encode-header encoding . o)
  (let ((src (if (pair? o) (car o) (current-input-port)))
        (start-col (if (and (pair? o) (pair? (cdr o))) (cadr o) 0))
        (max-col (if (and (pair? o) (pair? (cdr o)) (pair? (cddr o)))
                     (car (cddr o))
                     *default-max-col*))
        (nl (if (and (pair? o) (pair? (cdr o)) (pair? (cddr o)) (pair? (cdr (cddr o))))
                (cadr (cddr o))
                "\r\n")))
    (let* ((prefix (string-append "=?" encoding "?Q?"))
           (prefix-length (+ 2 (string-length prefix)))
           (separator (string-append "?=" nl "\t" prefix))
           (effective-max-col (- max-col prefix-length)))
      (string-append prefix
                     (qp-encode (if (string? src) src (read-string #f src))
                                start-col effective-max-col separator)
                     "?="))))

;;> Return a quoted-printable decoded representation of \var{str}.  If
;;> \var{mime-header?} is specified and true, _ will be decoded as as
;;> space in accordance with RFC1522.  No errors will be raised on
;;> invalid input.

(define (quoted-printable-decode-string  . o)
  (define (hex? c) (or (char-numeric? c) (<= 65 (char->integer c) 70)))
  (define (unhex1 c)
    (let ((i (char->integer c))) (if (>= i 65) (- i 55) (- i 48))))
  (define (unhex c1 c2)
    (integer->char (+ (arithmetic-shift (unhex1 c1) 4) (unhex1 c2))))
  (let ((src (if (pair? o) (car o) (current-input-port)))
        (mime-header? (and (pair? o) (pair? (cdr o)) (car (cdr o)))))
    (let* ((str (if (string? src) src (read-string #f src)))
           (end (string-length str)))
      (call-with-output-string
        (lambda (out)
          (let lp ((i 0))
            (cond
             ((< i end)
              (let ((c (string-ref str i)))
                (case c
                  ((#\=)                ; = escapes
                   (cond
                    ((< (+ i 2) end)
                     (let ((c2 (string-ref str (+ i 1))))
                       (cond
                        ((eq? c2 #\newline) (lp (+ i 2)))
                        ((eq? c2 #\return)
                         (lp (if (eq? (string-ref str (+ i 2)) #\newline)
                                 (+ i 3)
                                 (+ i 2))))
                        ((hex? c2)
                         (let ((c3 (string-ref str (+ i 2))))
                           (if (hex? c3) (write-char (unhex c2 c3) out))
                           (lp (+ i 3))))
                        (else (lp (+ i 3))))))))
                  ((#\_)                ; maybe translate _ to space
                   (write-char (if mime-header? #\space c) out)
                   (lp (+ i 1)))
                  ((#\space #\tab)      ; strip trailing whitespace
                   (let lp2 ((j (+ i 1)))
                     (cond
                      ((not (= j end))
                       (case (string-ref str j)
                         ((#\space #\tab) (lp2 (+ j 1)))
                         ((#\newline)
                          (lp (+ j 1)))
                         ((#\return)
                          (let ((k (+ j 1)))
                            (lp (if (and (< k end)
                                         (eqv? #\newline (string-ref str k)))
                                    (+ k 1) k))))
                         (else (display (substring str i j) out) (lp j)))))))
                  (else                 ; a literal char
                   (write-char c out)
                   (lp (+ i 1)))))))))))))

;;> Variation of the above to read and write to ports.

(define (quoted-printable-decode . o)
  (display (apply quoted-printable-decode-string o)))


))))
