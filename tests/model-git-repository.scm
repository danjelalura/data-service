(define-module (test-model-git-repository)
  #:use-module (srfi srfi-64)
  #:use-module (guix-data-service database)
  #:use-module (guix-data-service model git-repository))

(test-begin "test-model-git-repository")

(with-postgresql-connection
 (lambda (conn)
   (test-assert "returns an id for a non existent URL"
     (with-postgresql-transaction
      conn
      (lambda (conn)
        (number?
         (string->number
          (git-repository-url->git-repository-id
           conn
           "test-non-existent-url"))))
      #:always-rollback? #t))

   (test-assert "returns the right id for an existing URL"
     (with-postgresql-transaction
      conn
      (lambda (conn)
        (let* ((url "test-url")
               (id (git-repository-url->git-repository-id conn url)))
          (string=?
           id
           (git-repository-url->git-repository-id conn url))))
      #:always-rollback? #t))))

(test-end)
