;; @file: functions for script parsing and execution

(include "vars")
(include "script-grammar")
(include "script-statement")
(include "utils")

(use irregex srfi-1)

;; @descr: exports current environment variables to a script
(define (generate-script)
  (string-merge/deliminated 
    (map (lambda (variable)                
           (statement->script
             (make-op/assign               ; represent vars as assignment statements
               (first variable)            ; scope
               (second variable)           ; name
               (list (third variable)))))  ; value
         (read-all-vars))
    "\n"))                                 ; deliminate with new lines

;; @descr: parse script and execute it
(define (execute-script script) 
  (let* ((script (preprocess-script script))        ; preprocess and check for errors
         (found-bad-tokens (invalid-tokens script)))          
    (if (null? found-bad-tokens)
        (for-each execute-statement!                ; execute each statement
                  (parse-statements script))
        (for-each                                   ; report errors
          (lambda (bad-token)
            (write-line (~ "Unrecognized input: " bad-token)))
          found-bad-tokens))))

;; @descr: performs action described by statement data structure
(define (execute-statement! statement) 
  (write-line (statement->script statement)))

;; @descr: apply all preprocessing steps to script 
;;         (runs before syntax validation and parsing)
(define (preprocess-script script)
  (strip-comments                              
    (evaluate-shell-blocks script)))              
  
;; @descr: parses a preprocessed script into a list of statements
(define (parse-statements script)
  (map                                  ; map each statement              
    (lambda (statement-match)
      ; helper
      (define (value-of submatch-name)
        (submatch-named statement-match submatch-name))
      
      ; body
      (define scope (if (equal? (value-of `scope) "@")
                        system_scope
                        user_scope))
      (define name (value-of `name))
            
      (if (equal? (value-of `op) ":")   ; operator ":"
          (make-op/assign scope         ; scope
                          name          ; name
                          (map          ; map each value in brackets
                            (lambda (value-match)
                              (submatch-named value-match `value))
                            (irregex-search/all-matches
                              value-igx
                              (submatch-named statement-match `values))))
          ((if (equal? (value-of `op) "+")     ; + or - operator
               make-op/create                  ;    +
               make-op/remove) scope name)))   ;    -
    (irregex-search/all-matches statement-igx script)))

;; @descr: evaluates $() blocks as environment variables 
;;         or as shell commands if prefixed with "shell" keyword
(define (evaluate-shell-blocks str)
  (irregex-replace/all eval-igx str (lambda (match)
                                      ; helper
                                      (define (value-of submatch-name)
                                        (submatch-named match submatch-name))
                                      
                                      (if (value-of `command)
                                          (shell-evaluate! (value-of `command))
                                          (read-var 
                                            (if (equal? (value-of `scope) "@")
                                                system_scope
                                                user_scope)
                                            (value-of `variable))))))
  
;; @descr: remove all commented out text from a string
(define (strip-comments str)
  (irregex-replace/all 
    comment-igx
    str
    ""))

;; @descr: returns a list of unrecognized strings
(define (invalid-tokens script)
  (filter 
    not-whitespace?
    (irregex-split statement-igx script)))

;; @descr: renders statement into a script string
(define (statement->script statement) 
  (~ (if (equal? (op-arg statement `scope) system_scope)
         "@"
         "")
     (op-arg statement `name)
     (cond ((op-assign? statement)
            (~
              " : "
              (apply string-append (map 
                                     (lambda (value)
                                       (~ "[" value "] "))
                                     (op-arg statement `values)))
              
              ))
           ((op-create? statement)
            " + ")
           ((op-remove? statement)
            " - "))))
