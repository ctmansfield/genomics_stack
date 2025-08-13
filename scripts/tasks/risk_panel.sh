#!/usr/bin/env bash
# shellcheck shell=bash
register_task \
  "db-apply-risk-panel" \
  "Apply/update risk panel schema (idempotent)" \
  "cmd_db_apply_risk_panel" \
  $'Applies scripts/sql/risk_panel.sql to the DB.\nUsage: genomicsctl.sh db-apply-risk-panel'
