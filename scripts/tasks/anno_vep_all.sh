#!/usr/bin/env bash
# shellcheck shell=bash

# Call the already-registered task functions directly (we're sourced into the same shell)
cmd_anno_vep_all(){
  local id="${1:-}"; [[ -n "$id" ]] || die "Usage: genomicsctl.sh anno-vep-all <upload_id>"
  cmd_anno_vep "$id"
  cmd_anno_vep_import "$id"
  ok "Completed anno-vep-all for upload_id=$id"
}

register_task "anno-vep-all" "Export variants → run VEP → import results" "cmd_anno_vep_all"
