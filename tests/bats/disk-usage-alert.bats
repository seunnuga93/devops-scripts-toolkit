setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../bin/disk-usage-alert.sh"
}

@test "threshold of 0 reports every filesystem" {
  run "$SCRIPT" -t 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"Disk usage above 0%"* ]]
}

@test "threshold above 100 reports nothing" {
  run "$SCRIPT" -t 101
  [ "$status" -eq 0 ]
  [ "$output" = "All filesystems below 101%" ]
}

@test "rejects a non-numeric threshold" {
  run "$SCRIPT" -t high
  [ "$status" -eq 2 ]
}
