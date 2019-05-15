;;; Guix Data Service -- Information about Guix over time
;;; Copyright © 2016, 2017, 2018, 2019 Ricardo Wurmus <rekado@elephly.net>
;;; Copyright © 2018, 2019 Arun Isaac <arunisaac@systemreboot.net>
;;; Copyright © 2019 Christopher Baines <mail@cbaines.net>
;;;
;;; This program is free software: you can redistribute it and/or
;;; modify it under the terms of the GNU Affero General Public License
;;; as published by the Free Software Foundation, either version 3 of
;;; the License, or (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Affero General Public License for more details.
;;;
;;; You should have received a copy of the GNU Affero General Public
;;; License along with this program.  If not, see
;;; <http://www.gnu.org/licenses/>.

(define-module (guix-data-service web view html)
  #:use-module (guix-data-service config)
  #:use-module (guix-data-service web query-parameters)
  #:use-module (guix-data-service web util)
  #:use-module (ice-9 vlist)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-19)
  #:use-module (texinfo)
  #:use-module (texinfo html)
  #:export (index
            view-statistics
            view-revision-package-and-version
            view-revision
            view-revision-packages
            view-branches
            view-branch
            view-builds
            view-derivation
            view-store-item
            compare
            compare/derivations
            compare/packages
            compare-unknown-commit
            error-page))

(define* (header)
  `(nav
    (@ (id "header") (class "navbar navbar-default"))
    (div
     (@ (class "container-fluid"))
     (div
      (@ (class "navbar-header"))
      (div (@ (class "navbar-brand"))
           (a (@ (href "/") (class "logo"))))))))

(define* (layout #:key
                 (head '())
                 (body '())
                 (title "Guix Data Service")
                 (extra-headers '()))
  `(#:sxml ((doctype "html")
            (html
             (head
              (title ,title)
              (meta (@ (http-equiv "Content-Type")
                       (content "text/html; charset=UTF-8")))
              (meta (@ (http-equiv "Content-Language") (content "en")))
              (meta (@ (name "author") (content "Christopher Baines")))
              (meta (@ (name "viewport")
                       (content "width=device-width, initial-scale=1")))
              (link
               (@ (rel "stylesheet")
                  (media "screen")
                  (type "text/css")
                  (href "/css/reset.css")))
              (link
               (@ (rel "stylesheet")
                  (media "screen")
                  (type "text/css")
                  (href "/css/bootstrap.css")))
              ,@head
              (link
               (@ (rel "stylesheet")
                  (media "screen")
                  (type "text/css")
                  (href "/css/screen.css"))))
             (body ,@body
                   (footer
                    (p "Copyright © 2016—2019 by the GNU Guix community."
                       (br)
                       "Now with even more " (span (@ (class "lambda")) "λ") "! ")
                    (p "This is free software.  Download the "
                       (a (@ (href "https://git.cbaines.net/guix/data-service/"))
                          "source code here") ".")))))
    #:extra-headers ,extra-headers))


(define* (form-horizontal-control label query-parameters
                                  #:key
                                  help-text
                                  required?
                                  options)
  (define (value->text value)
    (match value
      (#f "")
      ((? date? date)
       (date->string date "~1 ~3"))
      (other other)))

  (let* ((input-id    (hyphenate-words
                       (string-downcase label)))
         (help-span-id (string-append
                        input-id "-help-text"))
         (input-name (underscore-join-words
                      (string-downcase label)))
         (has-error? (invalid-query-parameter?
                      (assq-ref query-parameters
                                (string->symbol input-name))))
         (show-help-span?
          (or help-text has-error? required?)))
    `(div
      (@ (class ,(string-append
                  "form-group form-group-lg"
                  (if has-error? " has-error" ""))))
      (label (@ (for ,input-id)
                (class "col-sm-2 control-label"))
             ,label)
      (div
       (@ (class "col-sm-9"))
       ,(if options
            `(select (@ (class "form-control")
                        (style "font-family: monospace;")
                        (multiple #t)
                        (id ,input-id)
                        ,@(if show-help-span?
                              `((aria-describedby ,help-span-id))
                              '())

                        (name ,input-name))
               ,@(let ((selected-options
                        (match (assq (string->symbol input-name)
                                     query-parameters)
                          ((_key . value)
                           value)
                          (_ '()))))

                   (map (lambda (option-value)
                          `(option
                            (@ ,@(if (member option-value selected-options)
                                     '((selected ""))
                                     '()))
                            ,(value->text option-value)))
                        options)))
            `(input (@ (class "form-control")
                       (style "font-family: monospace;")
                       (id ,input-id)
                       ,@(if required?
                             '((required #t))
                             '())
                       ,@(if show-help-span?
                             `((aria-describedby ,help-span-id))
                             '())
                       (name ,input-name)
                       ,@(match (assq (string->symbol input-name)
                                      query-parameters)
                           (#f '())
                           ((_key . ($ <invalid-query-parameter> value))
                            `((value ,(value->text value))))
                           ((_key . value)
                            `((value ,(value->text value))))))))
       ,@(if show-help-span?
             `((span (@ (id ,help-span-id)
                        (class "help-block"))
                     ,@(if has-error?
                           (let ((message
                                  (invalid-query-parameter-message
                                   (assq-ref query-parameters
                                             (string->symbol input-name)))))
                             `((p (strong
                                   ,(string-append
                                     "Error: "
                                     (if message
                                         message
                                         "invalid value."))))))
                           '())
                     ,@(if required? '((strong "Required. ")) '())
                     ,@(if help-text
                           (list help-text)
                           '())))
             '())))))

(define (index git-repositories-and-revisions)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h1 "Guix Data Service")))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (form
         (@ (id "compare")
            (action "/compare"))
         (div
          (@ (class "col-md-6"))
          (div
           (@ (class "form-group form-group-lg"))
           (label (@ (class "control-label")
                     (style "font-size: 18px;")
                     (for "base_commit"))
                  "Base commit")
           (input (@ (type "text")
                     (class "form-control")
                     (style "font-family: monospace;")
                     (id   "base_commit")
                     (name "base_commit")
                     (placeholder "base commit"))))
          (div
           (@ (class "form-group form-group-lg"))
           (label (@ (class "control-label")
                     (style "font-size: 18px;")
                     (for "target_commit"))
                  "Target commit")
           (input (@ (type "text")
                     (class "form-control")
                     (style "font-family: monospace;")
                     (id   "target_commit")
                     (name "target_commit")
                     (placeholder "target commit")))))
         (div
          (@ (class "col-md-6"))
          (button
           (@ (type "submit")
              (class "btn btn-lg btn-primary"))
           "Compare")))))
      ,@(map
         (match-lambda
           (((id label url) . revisions)
            `(div
              (@ (class "row"))
              (div
               (@ (class "col-sm-12"))
               (h3 ,url)
               ,(if (null? revisions)
                    '(p "No revisions")
                    `(table
                      (@ (class "table"))
                      (thead
                       (tr
                        (th (@ (class "col-md-6")) "Commit")))
                      (tbody
                       ,@(map
                          (match-lambda
                            ((id job-id commit source branches)
                             `(tr
                               (td ,(if (string-null? id)
                                        `(samp ,commit)
                                        `(a (@ (href ,(string-append
                                                       "/revision/" commit)))
                                            (samp ,commit))))
                               (td
                                ,@(map
                                   (match-lambda
                                     ((name date)
                                      `(a (@ (href ,(string-append
                                                     "/branch/" name)))
                                          ,name)))
                                   branches)))))
                          revisions))))))))
         git-repositories-and-revisions)))))

(define (view-statistics guix-revisions-count derivations-count)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-6"))
        (h3 "Guix revisions")
        (strong (@ (class "text-center")
                   (style "font-size: 2em; display: block;"))
                ,guix-revisions-count))
       (div
        (@ (class "col-md-6"))
        (h3 "Derivations")
        (strong (@ (class "text-center")
                   (style "font-size: 2em; display: block;"))
                ,derivations-count)))))))

(define (view-revision-package-and-version revision-commit-hash name version
                                           package-metadata
                                           derivations git-repositories)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 (a (@ (href ,(string-append
                          "/revision/" revision-commit-hash)))
               "Revision " (samp ,revision-commit-hash)))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h1 "Package " ,name " @ " ,version)))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        ,(match package-metadata
           (((synopsis description home-page file line column-number
                       licenses))
            `(dl
              (@ (class "dl-horizontal"))
              (dt "Synopsis")
              (dd ,(stexi->shtml (texi-fragment->stexi synopsis)))
              (dt "Description")
              (dd ,(stexi->shtml (texi-fragment->stexi description)))
              (dt "Home page")
              (dd (a (@ (href ,home-page)) ,home-page))
              ,@(if (and file (not (string-null? file))
                         (not (null? git-repositories)))
                    `((dt "Location")
                      (dd ,@(map
                             (match-lambda
                               ((id label url cgit-url-base)
                                (if
                                 (and cgit-url-base
                                      (not (string-null? cgit-url-base)))
                                 `(a (@ (href
                                         ,(string-append
                                           cgit-url-base "tree/"
                                           file "?id=" revision-commit-hash
                                           "#n" line)))
                                     ,file
                                     " (line: " ,line
                                     ", column: " ,column-number ")")
                                 '())))
                             git-repositories)))
                    '())
              ,@(if (> (vector-length licenses) 0)
                    `((dt ,(if (eq? (vector-length licenses) 1)
                               "License"
                               "Licenses"))
                      (dd (ul
                           ,@(map (lambda (license)
                                    `(li (a (@ (href ,(assoc-ref license "uri")))
                                            ,(assoc-ref license "name"))))
                                  (vector->list licenses)))))
                    '()))))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (table
         (@ (class "table"))
         (thead
          (tr
           (th "System")
           (th "Target")
           (th "Derivation")
           (th "Build status")))
         (tbody
          ,@(map
             (match-lambda
               ((system target file-name status)
                `(tr
                  (td (samp ,system))
                  (td (samp ,target))
                  (td (a (@ (href ,file-name))
                         ,(display-store-item-short file-name)))
                  (td ,(build-status-span status)))))
             derivations)))))))))

(define (view-revision commit-hash packages-count derivations-count)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-12"))
        (h1 (@ (style "white-space: nowrap;"))
            "Revision " (samp ,commit-hash))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-6"))
        (h3 "Packages")
        (strong (@ (class "text-center")
                   (style "font-size: 2em; display: block;"))
                ,packages-count)
        (a (@ (href ,(string-append "/revision/" commit-hash
                                    "/packages")))
           "View packages"))
       (div
        (@ (class "col-md-6"))
        (h3 "Derivations")
        (table
         (@ (class "table")
            (style "white-space: nowrap;"))
         (thead
          (tr
           (th "System")
           (th "Target")
           (th "Derivations")))
         (tbody
          ,@(map (match-lambda
                   ((system target count)
                    (if (string=? system target)
                        `(tr
                          (td (@ (class "text-center")
                                 (colspan 2))
                              (samp ,system))
                          (td (samp ,count)))
                        `(tr
                          (td (samp ,system))
                          (td (samp ,target))
                          (td (samp ,count))))))
                 derivations-count)))))))))

(define (view-revision-packages revision-commit-hash
                                query-parameters
                                packages
                                show-next-page?)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 (a (@ (href ,(string-append
                          "/revision/" revision-commit-hash)))
               "Revision " (samp ,revision-commit-hash)))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-12"))
        (div
         (@ (class "well"))
         (form
          (@ (method "get")
             (action "")
             (class "form-horizontal"))
          ,(form-horizontal-control
            "Search query" query-parameters
            #:help-text
            "List packages where the name or synopsis match the query.")
          ,(form-horizontal-control
            "After name" query-parameters
            #:help-text
            "List packages that are alphabetically after the given name.")
          ,(form-horizontal-control
            "Limit results" query-parameters
            #:help-text "The maximum number of packages by name to return.")
          (div (@ (class "form-group form-group-lg"))
               (div (@ (class "col-sm-offset-2 col-sm-10"))
                    (button (@ (type "submit")
                               (class "btn btn-lg btn-primary"))
                            "Update results")))))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h1 "Packages")
        (table
         (@ (class "table table-responsive"))
         (thead
          (tr
           (th (@ (class "col-md-3")) "Name")
           (th (@ (class "col-md-3")) "Version")
           (th (@ (class "col-md-3")) "Synopsis")
           (th (@ (class "col-md-3")) "")))
         (tbody
          ,@(map
             (match-lambda
               ((name version synopsis)
                `(tr
                  (td ,name)
                  (td ,version)
                  (td ,(stexi->shtml (texi-fragment->stexi synopsis)))
                  (td (@ (class "text-right"))
                      (a (@ (href ,(string-append
                                    "/revision/" revision-commit-hash
                                    "/package/" name "/" version)))
                         "More information")))))
             packages)))))
      ,@(if show-next-page?
            `((div
               (@ (class "row"))
               (a (@ (href ,(string-append "/revision/" revision-commit-hash
                                           "/packages?after_name="
                                           (car (last packages)))))
                  "Next page")))
            '())))))

(define (view-branches branches-with-most-recent-commits)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-12"))
        (h1 "Branches")))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-12"))
        (table
         (@ (class "table table-responsive"))
         (thead
          (tr
           (th (@ (class "col-md-3")) "Name")
           (th (@ (class "col-md-3")) "Commit")
           (th (@ (class "col-md-3")) "Date")))
         (tbody
          ,@(map
             (match-lambda
               ((name commit date revision-exists)
                `(tr
                  (td
                   (a (@ (href ,(string-append "/branch/" name)))
                      ,name))
                  (td ,date)
                  (td ,(if (string=? revision-exists "t")
                           `(a (@ (href ,(string-append
                                          "/revision/" commit)))
                               (samp ,commit))
                           `(samp ,(if (string=? commit "NULL")
                                       "branch deleted"
                                       commit)))))))
             branches-with-most-recent-commits)))))))))

(define (view-branch branch-name query-parameters
                     branch-commits)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-12"))
        (h1 (@ (style "white-space: nowrap;"))
            (samp ,branch-name) " branch")))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-12"))
        (div
         (@ (class "well"))
         (form
          (@ (method "get")
             (action "")
             (class "form-horizontal"))
          ,(form-horizontal-control
            "After date" query-parameters
            #:help-text "Only show the branch history after this date.")
          ,(form-horizontal-control
            "Before date" query-parameters
            #:help-text "Only show the branch history before this date.")
          ,(form-horizontal-control
            "Limit results" query-parameters
            #:help-text "The maximum number of results to return.")
          (div (@ (class "form-group form-group-lg"))
               (div (@ (class "col-sm-offset-2 col-sm-10"))
                    (button (@ (type "submit")
                               (class "btn btn-lg btn-primary"))
                            "Update results")))))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-12"))
        (table
         (@ (class "table table-responsive"))
         (thead
          (tr
           (th (@ (class "col-md-3")) "Date")
           (th (@ (class "col-md-3")) "Commit")))
         (tbody
          ,@(map
             (match-lambda
               ((commit date revision-exists)
                `(tr
                  (td ,date)
                  (td ,(if (string=? revision-exists "t")
                           `(a (@ (href ,(string-append
                                          "/revision/" commit)))
                               (samp ,commit))
                           `(samp ,(if (string=? commit "NULL")
                                       "branch deleted"
                                       commit)))))))
             branch-commits)))))))))

(define (view-builds stats builds)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h1 "Builds")
        (table
         (@ (class "table"))
         (thead
          (tr
           (th (@ (class "col-md-2")) "Status")
           (th (@ (class "col-md-2")) "Count")))
         (tbody
          ,@(map
             (match-lambda
               ((status count)
                `(tr
                  (td ,(build-status-span status))
                  (td ,count))))
             stats)))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (table
         (@ (class "table"))
         (thead
          (tr
           (th (@ (class "col-xs-2")) "Status")
           (th (@ (class "col-xs-9")) "Derivation")
           (th (@ (class "col-xs-1")) "Started at")
           (th (@ (class "col-xs-1")) "Finished at")
           (th (@ (class "col-xs-1")) "")))
         (tbody
          ,@(map
             (match-lambda
               ((build-id build-server-url derivation-file-name
                          status-fetched-at starttime stoptime status)
                `(tr
                  (td (@ (class "text-center"))
                      ,(build-status-span status))
                  (td (a (@ (href ,derivation-file-name))
                         ,(display-store-item-short derivation-file-name)))
                  (td ,starttime)
                  (td ,stoptime)
                  (td (a (@ (href ,(simple-format
                                    #f "~Abuild/~A" build-server-url build-id)))
                         "View build on " ,build-server-url)))))
             builds)))))))))

(define (build-status-value->display-string value)
  (assoc-ref
   '(("scheduled" . "Scheduled")
     ("started" . "Started")
     ("succeeded" . "Succeeded")
     ("failed" . "Failed")
     ("failed-dependency" . "Failed (dependency)")
     ("failed-other" . "Failed (other)")
     ("canceled" . "Canceled")
     ("" . "Unknown"))
   value))

(define (build-status-span status)
  `(span (@ (class ,(string-append
                     "label label-"
                     (assoc-ref
                      '(("scheduled" . "info")
                        ("started" . "primary")
                        ("succeeded" . "success")
                        ("failed" . "danger")
                        ("failed-dependency" . "warning")
                        ("failed-other" . "danger")
                        ("canceled" . "default")
                        ("" . "default"))
                      status)))
            (style "display: inline-block; font-size: 1.2em; margin-top: 0.4em;"))
         ,(build-status-value->display-string status)))

(define (display-store-item-short item)
  `((span (@ (style "font-size: small; font-family: monospace; display: block;"))
          ,(string-take item 44))
    (span (@ (style "font-size: x-large; font-family: monospace; display: block;"))
          ,(string-drop item 44))))

(define (display-store-item item)
  `((span (@ (style "font-size: small; font-family: monospace; white-space: nowrap;"))
          ,(string-take item 44))
    (span (@ (style "font-size: x-large; font-family: monospace; white-space: nowrap;"))
          ,(string-drop item 44))))

(define (display-store-item-title item)
  `(h1 (span (@ (style "font-size: 1em; font-family: monospace; display: block;"))
             ,(string-take item 44))
       (span (@ (style "line-height: 1.7em; font-size: 1.5em; font-family: monospace;"))
             ,(string-drop item 44))))

(define (display-file-in-store-item filename)
  (match (string-split filename #\/)
    (("" "gnu" "store" item fileparts ...)
     `(,(let ((full-item (string-append "/gnu/store/" item)))
          `(a (@ (href ,full-item))
              ,(display-store-item-short full-item)))
       ,(string-append
         "/" (string-join fileparts "/"))))))

(define (view-store-item filename derivations derivations-using-store-item-list)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        ,(display-store-item-title filename)))
      ,@(map (lambda (derivation derivations-using-store-item)
               `((div
                  (@ (class "row"))
                  (div
                   (@ (class "col-sm-12"))
                   (h4 "Derivation: ")
                   ,(match derivation
                      ((file-name output-id)
                       `(a (@ (href ,file-name))
                           ,(display-store-item file-name))))))
                 (div
                  (@ (class "row"))
                  (div
                   (@ (class "col-sm-12"))
                   (h2 "Derivations using this store item "
                       ,(let ((count (length derivations-using-store-item)))
                          (if (eq? count 100)
                              "(> 100)"
                              (simple-format #f "(~A)" count))))
                   (ul
                    (@ (class "list-unstyled"))
                    ,(map
                      (match-lambda
                        ((file-name)
                         `(li (a (@ (href ,file-name))
                                 ,(display-store-item file-name)))))
                      derivations-using-store-item))))))
             derivations
             derivations-using-store-item-list)))))

(define (view-derivation derivation derivation-inputs derivation-outputs
                         builds)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      ,(match derivation
         ((id file-name builder args env-vars system)
          `(div
            (@ (class "row"))
            (div
             (@ (class "col-sm-12"))
             ,(display-store-item-title file-name)))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-4"))
        (h3 "Inputs")
        ,(if (null? derivation-inputs)
             "No inputs"
             `(table
               (@ (class "table"))
               (thead
                (tr
                 (th "File name")))
               (tdata
                ,@(map (match-lambda
                         ((file-name output-name path)
                          `(tr
                            (td (a (@ (href ,file-name))
                                   ,(display-store-item-short path))))))
                       derivation-inputs)))))
       (div
        (@ (class "col-md-4"))
        (h3 "Derivation details")
        ,(match derivation
           ((id file-name builder args env-vars system)
            `(table
              (@ (class "table"))
              (tbody
               (tr
                (td "Builder")
                (td ,(if (string=? "builtin:download"
                                   builder)
                         "builtin:download"
                         `(a (@ (href ,builder))
                             ,(display-file-in-store-item builder)))))
               (tr
                (td "System")
                (td (samp ,system)))))))
        (h3 "Build status")
        ,@(if (null? builds)
              `((div
                 (@ (class "text-center"))
                 ,(build-status-span "")))
              (map
               (match-lambda
                 ((build-id build-server-url status-fetched-at
                            starttime stoptime status)
                  `(div
                    (@ (class "text-center"))
                    (div ,(build-status-span status))
                    (a (@ (style "display: inline-block; margin-top: 0.4em;")
                          (href ,(simple-format
                                  #f "~Abuild/~A" build-server-url build-id)))
                       "View build on " ,build-server-url))))
               builds)))
       (div
        (@ (class "col-md-4"))
        (h3 "Outputs")
        (table
         (@ (class "table"))
         (thead
          (tr
           (th "File name")))
         (tdata
          ,@(map (match-lambda
                   ((output-name path hash-algorithm hash recursive?)
                    `(tr
                      (td (a (@ (href ,path))
                             ,(display-store-item-short path))))))
                 derivation-outputs)))))))))

(define (compare base-commit
                 target-commit
                 new-packages
                 removed-packages
                 version-changes
                 derivation-changes)
  (define query-params
    (string-append "?base_commit=" base-commit
                   "&target_commit=" target-commit))

  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h1 (@ (class "pull-left"))
            "Comparing "
            (samp ,(string-take base-commit 8) "…")
            " and "
            (samp ,(string-take target-commit 8) "…"))
        (div
         (@ (class "btn-group-vertical btn-group-lg pull-right")
            (style "margin-top: 2em;")
            (role "group"))
         (a (@ (class "btn btn-default")
               (href ,(string-append "/compare/packages" query-params)))
            "Compare packages")
         (a (@ (class "btn btn-default")
               (href ,(string-append "/compare/derivations" query-params)))
            "Compare derivations"))))
      (div
       (@ (class "row") (style "clear: left;"))
       (div
        (@ (class "col-sm-12"))
        (a (@ (class "btn btn-default btn-lg")
              (href ,(string-append
                      "/compare.json" query-params)))
           "View JSON")))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 (@ (style "clear: both;"))
            "New packages")
        ,(if (null? new-packages)
             '(p "No new packages")
             `(table
               (@ (class "table"))
               (thead
                (tr
                 (th (@ (class "col-md-3")) "Name")
                 (th (@ (class "col-md-9")) "Version")))
               (tbody
                ,@(map
                   (match-lambda
                     ((('name . name)
                       ('version . version))
                      `(tr
                        (td ,name)
                        (td ,version))))
                   new-packages))))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 "Removed packages")
        ,(if (null? removed-packages)
             '(p "No removed packages")
             `(table
               (@ (class "table"))
               (thead
                (tr
                 (th (@ (class "col-md-3")) "Name")
                 (th (@ (class "col-md-9")) "Version")))
               (tbody
                ,@(map
                   (match-lambda
                     ((('name . name)
                       ('version . version))
                      `(tr
                        (td ,name)
                        (td ,version))))
                   removed-packages))))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 "Version changes")
        ,(if (null? version-changes)
             '(p "No version changes")
             `(table
               (@ (class "table"))
               (thead
                (tr
                 (th (@ (class "col-md-3")) "Name")
                 (th (@ (class "col-md-9")) "Versions")))
               (tbody
                ,@(map
                   (match-lambda
                     ((name . versions)
                      `(tr
                        (td ,name)
                        (td (ul
                             ,@(map (match-lambda
                                      ((type . versions)
                                       `(li (@ (class ,(if (eq? type 'base)
                                                           "text-danger"
                                                           "text-success")))
                                            ,(string-join
                                              (vector->list versions)
                                              ", ")
                                            ,(if (eq? type 'base)
                                                 " (old)"
                                                 " (new)"))))
                                    versions))))))
                   version-changes))))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 "Package derivation changes")
        ,(if
          (null? derivation-changes)
          '(p "No derivation changes")
          `(table
            (@ (class "table")
               (style "table-layout: fixed;"))
            (thead
             (tr
              (th "Name")
              (th "Version")
              (th "System")
              (th "Target")
              (th (@ (class "col-xs-5")) "Derivations")))
            (tbody
             ,@(append-map
                (match-lambda
                  ((('name . name)
                    ('version . version)
                    ('base . base-derivations)
                    ('target . target-derivations))
                   (let* ((system-and-versions
                           (delete-duplicates
                            (append (map (lambda (details)
                                           (cons (assq-ref details 'system)
                                                 (assq-ref details 'target)))
                                         (vector->list base-derivations))
                                    (map (lambda (details)
                                           (cons (assq-ref details 'system)
                                                 (assq-ref details 'target)))
                                         (vector->list target-derivations)))))
                          (data-columns
                           (map
                            (match-lambda
                              ((system . target)
                               (let ((base-derivation-file-name
                                      (assq-ref (find (lambda (details)
                                                        (and (string=? (assq-ref details 'system) system)
                                                             (string=? (assq-ref details 'target) target)))
                                                      (vector->list base-derivations))
                                                'derivation-file-name))
                                     (target-derivation-file-name
                                      (assq-ref (find (lambda (details)
                                                        (and (string=? (assq-ref details 'system) system)
                                                             (string=? (assq-ref details 'target) target)))
                                                      (vector->list target-derivations))
                                                'derivation-file-name)))
                                 `((td (samp (@ (style "white-space: nowrap;"))
                                             ,system))
                                   (td (samp (@ (style "white-space: nowrap;"))
                                             ,target))
                                   (td ,@(if base-derivation-file-name
                                             `((a (@ (style "display: block;")
                                                     (href ,base-derivation-file-name))
                                                  (span (@ (class "text-danger glyphicon glyphicon-minus pull-left")
                                                           (style "font-size: 1.5em; padding-right: 0.4em;")))
                                                  ,(display-store-item-short base-derivation-file-name)))
                                             '())
                                       ,@(if target-derivation-file-name
                                             `((a (@ (style "display: block; clear: left;")
                                                     (href ,target-derivation-file-name))
                                                  (span (@ (class "text-success glyphicon glyphicon-plus pull-left")
                                                           (style "font-size: 1.5em; padding-right: 0.4em;")))
                                                  ,(and=> target-derivation-file-name display-store-item-short)))
                                             '()))))))
                            system-and-versions)))

                     `((tr (td (@ (rowspan , (length system-and-versions)))
                               ,name)
                           (td (@ (rowspan , (length system-and-versions)))
                               ,version)
                           ,@(car data-columns))
                       ,@(map (lambda (data-row)
                                `(tr ,data-row))
                              (cdr data-columns))))))
                (vector->list derivation-changes)))))))))))

(define (compare/derivations query-parameters
                             valid-systems
                             valid-build-statuses
                             base-derivations
                             target-derivations)
  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (h1 ,@(let ((base-commit (assq-ref query-parameters 'base_commit))
                   (target-commit (assq-ref query-parameters 'target_commit)))
               (if (every string? (list base-commit target-commit))
                   `("Comparing "
                     (samp ,(string-take base-commit 8) "…")
                     " and "
                     (samp ,(string-take target-commit 8) "…"))
                   '("Comparing derivations")))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-md-12"))
        (div
         (@ (class "well"))
         (form
          (@ (method "get")
             (action "")
             (class "form-horizontal"))
          ,(form-horizontal-control
            "Base commit" query-parameters
            #:required? #t
            #:help-text "The commit to use as the basis for the comparison.")
          ,(form-horizontal-control
            "Target commit" query-parameters
            #:required? #t
            #:help-text "The commit to compare against the base commit.")
          ,(form-horizontal-control
            "System" query-parameters
            #:options valid-systems
            #:help-text "Only include derivations for this system.")
          ,(form-horizontal-control
            "Target" query-parameters
            #:options valid-systems
            #:help-text "Only include derivations that are build for this system.")
          ,(form-horizontal-control
            "Build status" query-parameters
            #:options valid-build-statuses
            #:help-text "Only include derivations which have this build status.")
          (div (@ (class "form-group form-group-lg"))
               (div (@ (class "col-sm-offset-2 col-sm-10"))
                    (button (@ (type "submit")
                               (class "btn btn-lg btn-primary"))
                            "Update results")))
          (a (@ (class "btn btn-default btn-lg pull-right")
                (href ,(let ((query-parameter-string
                              (query-parameters->string query-parameters)))
                         (string-append
                          "/compare/derivations.json"
                          (if (string-null? query-parameter-string)
                              ""
                              (string-append "?" query-parameter-string))))))
             "View JSON")))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 "Base"
            ,@(let ((base-commit (assq-ref query-parameters 'base_commit)))
                (if (string? base-commit)
                    `(" (" (samp ,base-commit) ")")
                    '())))
        (p "Derivations found only in the base revision.")
        (table
         (@ (class "table"))
         (thead
          (tr
           (th (@ (class "col-md-6")) "File Name")
           (th (@ (class "col-md-2")) "System")
           (th (@ (class "col-md-2")) "Target")
           (th (@ (class "col-md-4")) "Build status")))
         (tbody
          ,@(map
             (match-lambda
               ((file-name system target build-status)
                `(tr
                  (td (a (@ (href ,file-name))
                         ,(display-store-item-short file-name)))
                  (td (samp ,system))
                  (td (samp ,target))
                  (td ,(build-status-span build-status)))))
             base-derivations)))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 "Target"
            ,@(let ((target-commit (assq-ref query-parameters 'target_commit)))
                (if (string? target-commit)
                    `(" (" (samp ,target-commit) ")")
                    '())))
        (p "Derivations found only in the target revision.")
        (table
         (@ (class "table"))
         (thead
          (tr
           (th (@ (class "col-md-8")) "File Name")
           (th (@ (class "col-md-2")) "System")
           (th (@ (class "col-md-2")) "Target")
           (th (@ (class "col-md-4")) "Build status")))
         (tbody
          ,@(map
             (match-lambda
               ((file-name system target build-status)
                `(tr
                  (td (a (@ (href ,file-name))
                         ,(display-store-item-short file-name)))
                  (td (samp ,system))
                  (td (samp ,target))
                  (td ,(build-status-span build-status)))))
             target-derivations)))))))))

(define (compare/packages base-commit
                          target-commit
                          base-packages-vhash
                          target-packages-vhash)
  (define query-params
    (string-append "?base_commit=" base-commit
                   "&target_commit=" target-commit))

  (layout
   #:extra-headers
   '((cache-control . ((max-age . 60))))
   #:body
   `(,(header)
     (div
      (@ (class "container"))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h1 "Comparing "
            (samp ,(string-take base-commit 8) "…")
            " and "
            (samp ,(string-take target-commit 8) "…"))
        (a (@ (class "btn btn-default btn-lg")
              (href ,(string-append
                      "/compare/packages.json" query-params)))
           "View JSON")))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 "Base ("
            (samp ,base-commit)
            ")")
        (p "Packages found in the base revision.")
        (table
         (@ (class "table"))
         (thead
          (tr
           (th (@ (class "col-md-4")) "Name")
           (th (@ (class "col-md-4")) "Version")
           (th (@ (class "col-md-4")) "")))
         (tbody
          ,@(map
             (match-lambda
               ((name version)
                `(tr
                  (td ,name)
                  (td ,version)
                  (td (@ (class "text-right"))
                      (a (@ (href ,(string-append
                                    "/revision/" base-commit
                                    "/package/" name "/" version)))
                         "More information")))))
             (delete-duplicates
              (map (lambda (data)
                     (take data 2))
                   (vlist->list base-packages-vhash))))))))
      (div
       (@ (class "row"))
       (div
        (@ (class "col-sm-12"))
        (h3 "Target ("
            (samp ,target-commit)
            ")")
        (p "Packages found in the target revision.")
        (table
         (@ (class "table"))
         (thead
          (tr
           (th (@ (class "col-md-4")) "Name")
           (th (@ (class "col-md-4")) "Version")
           (th (@ (class "col-md-4")) "")))
         (tbody
          ,@(map
             (match-lambda
               ((name version)
                `(tr
                  (td ,name)
                  (td ,version)
                  (td (@ (class "text-right"))
                      (a (@ (href ,(string-append
                                    "/revision/" target-commit
                                    "/package/" name "/" version)))
                         "More information")))))
             (delete-duplicates
              (map (lambda (data)
                     (take data 2))
                   (vlist->list target-packages-vhash))))))))))))

(define (compare-unknown-commit base-commit target-commit
                                base-exists? target-exists?
                                base-job target-job)
  (layout
   #:body
   `(,(header)
     (div (@ (class "container"))
          (h1 "Unknown commit")
          ,(if base-exists?
               '()
               `(p "No known revision with commit "
                   (strong (samp ,base-commit))
                   ,(if (null? base-job)
                        " and it is not currently queued for processing"
                        " but it is queued for processing")))
          ,(if target-exists?
               '()
               `(p "No known revision with commit "
                   (strong (samp ,target-commit))
                   ,(if (null? target-job)
                        " and it is not currently queued for processing"
                        " but it is queued for processing")))))))

(define (error-page message)
  (layout
   #:body
   `(,(header)
     (div (@ (class "container"))
          (h1 "Error")
          (p "An error occurred.  Sorry about that!")
          ,message
          (p (a (@ (href "/")) "Try something else?"))))))
