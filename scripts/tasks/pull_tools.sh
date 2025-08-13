task_pull_tools() {
  say "Pulling bcftools/samtools images"
  docker pull staphb/bcftools:1.20
  docker pull staphb/samtools:1.20
  ok "Images pulled"
}
register_task "pull-tools" "Pull staphb/bcftools:1.20 and staphb/samtools:1.20" task_pull_tools
