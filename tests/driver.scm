;;; Copyright © 2015, 2016 Mathieu Lirzin <mthl@gnu.org>
;;; Copyright © 2019 Christopher Baines <mail@cbaines.net>
;;;
;;; This program is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(define-module (tests driver)
  #:use-module (ice-9 pretty-print)
  #:use-module (srfi srfi-26)
  #:use-module (srfi srfi-64)
  #:export (setup-runner))

(define* (test-display field value  #:optional (port (current-output-port))
                       #:key pretty?)
  "Display \"FIELD: VALUE\\n\" on PORT."
  (if pretty?
      (begin
        (format port "~A:~%" field)
        (pretty-print value port #:per-line-prefix "+ "))
      (format port "~A: ~S~%" field value)))

(define* (result->string symbol #:key colorize?)
  "Return SYMBOL as an upper case string.  Use colors when COLORIZE is #t."
  (let ((result (string-upcase (symbol->string symbol))))
    (if colorize?
        (string-append (case symbol
                         ((pass)       "[0;32m")  ;green
                         ((xfail)      "[1;32m")  ;light green
                         ((skip)       "[1;34m")  ;blue
                         ((fail xpass) "[0;31m")  ;red
                         ((error)      "[0;35m")) ;magenta
                       result
                       "[m")          ;no color
        result)))

(define* (test-runner-gnu #:key color? brief? out-port trs-port)
  "Return an custom SRFI-64 test runner.  COLOR? specifies whether to use colors,
and BRIEF?, well, you know.  OUT-PORT and TRS-PORT must be output ports.  The
current output port is supposed to be redirected to a '.log' file."

  (define (test-on-test-begin-gnu runner)
    ;; Procedure called at the start of an individual test case, before the
    ;; test expression (and expected value) are evaluated.
    (let ((result (cute assq-ref (test-result-alist runner) <>)))
      (format #t "location: ~A~%"
              (string-append (result 'source-file) ":"
                             (number->string (result 'source-line))))
      (test-display "source" (result 'source-form) #:pretty? #t)))

  (define (test-on-test-end-gnu runner)
    ;; Procedure called at the end of an individual test case, when the result
    ;; of the test is available.
    (let* ((results (test-result-alist runner))
           (result? (cut assq <> results))
           (result  (cut assq-ref results <>)))
      (unless brief?
        ;; Display the result of each test case on the console.
        (format out-port "~A: ~A~%"
                (result->string (test-result-kind runner) #:colorize? color?)
                (test-runner-test-name runner)))
      (when (result? 'expected-value)
        (test-display "expected-value" (result 'expected-value)))
      (when (result? 'expected-error)
        (test-display "expected-error" (result 'expected-error) #:pretty? #t))
      (when (result? 'actual-value)
        (test-display "actual-value" (result 'actual-value)))
      (when (result? 'actual-error)
        (test-display "actual-error" (result 'actual-error) #:pretty? #t))
      (format #t "result: ~a~%" (result->string (result 'result-kind)))
      (newline)
      (format trs-port ":test-result: ~A ~A~%"
              (result->string (test-result-kind runner))
              (test-runner-test-name runner))))

  (define (test-on-group-end-gnu runner)
    ;; Procedure called by a 'test-end', including at the end of a test-group.
    (let ((fail (or (positive? (test-runner-fail-count runner))
                    (positive? (test-runner-xpass-count runner))))
          (skip (or (positive? (test-runner-skip-count runner))
                    (positive? (test-runner-xfail-count runner)))))
      ;; XXX: The global results need some refinements for XPASS.
      (format trs-port ":global-test-result: ~A~%"
              (if fail "FAIL" (if skip "SKIP" "PASS")))
      (format trs-port ":recheck: ~A~%"
              (if fail "yes" "no"))
      (format trs-port ":copy-in-global-log: ~A~%"
              (if (or fail skip) "yes" "no"))
      (when brief?
        ;; Display the global test group result on the console.
        (format out-port "~A: ~%"
                (result->string (if fail 'fail (if skip 'skip 'pass))
                                #:colorize? color?)))
      #f))

  (let ((runner (test-runner-null)))
    (test-runner-on-test-begin! runner test-on-test-begin-gnu)
    (test-runner-on-test-end! runner test-on-test-end-gnu)
    (test-runner-on-group-end! runner test-on-group-end-gnu)
    (test-runner-on-bad-end-name! runner test-on-bad-end-name-simple)
    runner))

(define (setup-runner)
  (test-runner-current (test-runner-gnu)))

(setup-runner)
