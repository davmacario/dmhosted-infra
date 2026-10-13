#!/usr/bin/env bash
# Force Renovate (CronJob) run

job_name="renovate-manual-$(date +%s)"

kubectl -n renovate create job --from=cronjob/renovate "$job_name"
