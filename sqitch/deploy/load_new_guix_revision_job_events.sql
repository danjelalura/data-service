-- Deploy guix-data-service:load_new_guix_revision_job_events to pg

BEGIN;

CREATE TYPE job_event AS ENUM ('start', 'failure', 'success');

ALTER TABLE ONLY load_new_guix_revision_jobs
    ADD CONSTRAINT load_new_guix_revision_jobs_id UNIQUE (id);

CREATE TABLE load_new_guix_revision_job_events (
    id integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    job_id integer NOT NULL,
    event job_event NOT NULL,
    occurred_at timestamp without time zone NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT job_id FOREIGN KEY (job_id) REFERENCES load_new_guix_revision_jobs (id)
);

COMMIT;