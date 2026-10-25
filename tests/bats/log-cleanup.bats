setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../bin/log-cleanup.sh"
  LOGS="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$LOGS"
  # touch -t works the same on GNU and BSD, unlike touch -d.
  aged() {
    touch -t "$(python3 -c 'import datetime as d, sys; print((d.datetime.now() - d.timedelta(days=int(sys.argv[1]))).strftime("%Y%m%d%H%M"))' "$2")" "$LOGS/$1"
  }
  aged fresh.log 1
  aged week-old.log 10
  aged ancient.log 40
  aged ancient.log.gz 40
  aged keep.txt 40
}

@test "compresses old logs and deletes very old ones" {
  run "$SCRIPT" -c 7 -r 30 "$LOGS"
  [ "$status" -eq 0 ]
  [ "$output" = "deleted=2 compressed=1 dry_run=false" ]
  [ -f "$LOGS/fresh.log" ]
  [ -f "$LOGS/week-old.log.gz" ]
  [ ! -e "$LOGS/ancient.log" ]
  [ ! -e "$LOGS/ancient.log.gz" ]
  [ -f "$LOGS/keep.txt" ]
}

@test "dry run changes nothing" {
  run "$SCRIPT" -n "$LOGS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] rm"* ]]
  [[ "$output" == *"[dry-run] gzip"* ]]
  [ -f "$LOGS/ancient.log" ]
  [ -f "$LOGS/week-old.log" ]
}

@test "refuses a delete age at or below the compress age" {
  run "$SCRIPT" -c 30 -r 7 "$LOGS"
  [ "$status" -eq 2 ]
}

@test "refuses a missing directory" {
  run "$SCRIPT" "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}
