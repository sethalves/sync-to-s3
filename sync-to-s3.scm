#! /bin/bash
#| -*- scheme -*-
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
# Ph'nglui mglw'nafh Cthulhu R'lyeh wgah'nagl fhtagn
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
X=$CHIBI_MODULE_PATH
CHIBI_MODULE_PATH="" exec chibi-scheme -A "$DIR" -A "$X" -A . -s "$0" "$@"
|#


(import (scheme base)
        (scheme read)
        (scheme write)
        (scheme file)
        (scheme process-context)
        (srfi 1)
        (srfi 13)
        (srfi 29)
        (srfi 37)
        (srfi 69)
        (snow bytevector)
        (snow filesys)
        (snow genport)
        (snow zlib)
        (snow tar)
        (seth crypt md5)
        (seth port-extras)
        (seth aws common)
        (seth aws s3))

(cond-expand
 (chibi
  (import (chibi filesystem)))
 (gauche
  (import (file util)))
 (else))


(define (list-prefix-equal? small-list big-list)
  ;; does all of small-list match the first part of big-list?
  (cond ((null? small-list) #t)
        ((null? big-list) #f)
        ((equal? (car small-list) (car big-list))
         (list-prefix-equal? (cdr small-list) (cdr big-list)))
        (else #f)))


(define (sync-file-to-s3 credentials bucket
                         local-filename remote-filename
                         key/md5 tbf-size dry-run)
  ;; upload a file if the local md5 doesn't match the one on s3
  (let ((md5-on-s3 (get-object-md5 credentials bucket remote-filename)))

    (define (upload-file)
      (let* ((h (open-binary-input-file local-filename)))
        (put-object! credentials bucket remote-filename h tbf-size)
        (close-input-port h)))

    (cond ((not md5-on-s3)
           (display (format "[  ] ~a\n" local-filename))
           (upload-file))
          ((equal? md5-on-s3 key/md5)
           (display (format "[ok] ~a\n" local-filename)))
          (else
           (display (format "[up] ~a\n" local-filename))
           (if (not dry-run) (upload-file))))))


(define (say-skipping-file why path-parts)
  (display (format "skipping file [~s] ~s\n" why path-parts)
           (current-error-port)))


(define (walk top bucket to-skip credentials dry-run)
  (snow-directory-tree-walk
   top

   ;; this is called for each directory
   (lambda (directory-path-parts)
     (let* ((filename (snow-combine-filename-parts directory-path-parts))
            (result
             (cond ((null? directory-path-parts) #t)
                   ((snow-file-symbolic-link? filename) #f)
                   ((equal? (last directory-path-parts) ".svn") #f)
                   ((equal? (last directory-path-parts) ".git") #f)
                   ((equal? (last directory-path-parts) ".git") #f)
                   ((equal? (last directory-path-parts) ".Private") #f)
                   ((equal? (last directory-path-parts) ".deps") #f)
                   ((equal? (last directory-path-parts) ".bak") #f)
                   ((any (lambda (tskip)
                           (list-prefix-equal? tskip directory-path-parts))
                         to-skip)
                    #f)
                   (else #t))))
       (cond ((not result)
              (display (format "skipping ~s\n" directory-path-parts)
                       (current-error-port))))
       result))

   ;; this is called for each file
   (lambda (file-path-parts)
     (guard
      (err (#t
            (display (format "failed ~s\n" file-path-parts)
                     (current-error-port))
            (write (error-object-message err) (current-error-port))
            (newline (current-error-port))
            (write (error-object-irritants err) (current-error-port))
            (newline (current-error-port))))

      (let ((local-filename (snow-combine-filename-parts file-path-parts))
            (remote-filename (snow-combine-filename-parts
                              (drop file-path-parts
                                    (length (snow-split-filename top))))))
        (cond ((snow-file-symbolic-link? local-filename) ;; skip symlinks
               (say-skipping-file "symbolic link" file-path-parts)
               #t)

              ((string-suffix? "~" local-filename)
               (say-skipping-file "emacs backup" file-path-parts)
               #t)

              ((string-suffix? ".bak" local-filename)
               (say-skipping-file "emacs backup" file-path-parts)
               #t)

              (else
               (let* ((file-size (snow-file-size local-filename))
                      (file-md5 (filename->md5 local-filename)))
                 (sync-file-to-s3 credentials bucket
                                  local-filename remote-filename
                                  file-md5 file-size dry-run)))))))))



(define options
  (list
   (option '(#\v "verbose") #f #f
           (lambda (option name arg local-path bucket
                           verbose dry-run open-archives)
             (values local-path bucket #t dry-run open-archives)))

   (option '(#\n "dry-run") #f #f
           (lambda (option name arg local-path bucket
                           verbose dry-run open-archives)
             (values local-path bucket verbose #t open-archives)))

   (option '(#\o "open-archives") #f #f
           (lambda (option name arg local-path bucket
                           verbose dry-run open-archives)
             (values local-path bucket verbose dry-run #t)))

   (option '(#\h "help") #f #f
           (lambda (option name arg local-path bucket
                           verbose dry-run open-archives)
             (usage "")))))


(define (usage msg)
  (let ((pargs (command-line)))
    (display msg (current-error-port))
    (display (car pargs) (current-error-port))
    (display " " (current-error-port))
    (display "[arguments] local-path bucket-name\n"
             (current-error-port))
    (display "  -n --dry-run         " (current-error-port))
    (display "Don't make changes\n" (current-error-port))
    (display "  -o --open-archives   " (current-error-port))
    (display "Search for duplicates in archives\n" (current-error-port))
    (display "  -v --verbose         " (current-error-port))
    (display "Print more.\n" (current-error-port))
    (display "  -h --help            " (current-error-port))
    (display "Print usage message.\n" (current-error-port))
    (exit 1)))



(define (main-program)
  (let-values
      (((local-path bucket verbose dry-run open-archives)
        (args-fold
         (cdr (command-line))
         options
         ;; unrecognized
         (lambda (option name arg . seeds)
           (usage (string-append "Unrecognized option:"
                                 (if (string? name) name (string name))
                                 "\n\n")))
         ;; operand (arguments that don't start with a hyphen)
         (lambda (operand local-path bucket verbose dry-run open-archives)
           (cond ((and local-path bucket)
                  (usage "Too many non-optional arguments."))
                 (local-path
                  (values local-path operand verbose dry-run open-archives))
                 (else
                  (values operand bucket verbose dry-run open-archives))))
         #f ;; initial value of local-path
         #f ;; initial value of bucket
         #f ;; initial value of verbose
         #f ;; initial value of dry-run
         #f ;; initial value of open-archives
         )))

    (cond (verbose
           (display (format "local-path=~a\n" local-path))
           (display (format "bucket=~a\n" bucket))
           (display (format "verbose=~a\n" verbose))
           (display (format "dry-run=~a\n" dry-run))))

    (cond ((or (not local-path) (not bucket))
           (usage "local-path and bucket are required arguments.")))

    (let ((to-skip '(;; "/home/seth/tmp"
                     ;; "/home/seth/crypt"
                     ;; "/home/seth/.wine/dosdevices"
                     ))
          (credentials (get-credentials-for-s3-bucket bucket)))

      (if (not (bucket-exists? credentials bucket))
          (create-bucket! credentials bucket))

      (walk local-path bucket (map snow-split-filename to-skip)
            credentials dry-run))))

(main-program)

