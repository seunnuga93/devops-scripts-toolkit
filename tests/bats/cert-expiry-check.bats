setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../../bin/cert-expiry-check.sh"
  TMP="$BATS_TEST_TMPDIR"
  make_cert() {
    openssl req -x509 -newkey rsa:2048 -nodes -subj "/CN=$1" -days "$2" \
      -keyout "$TMP/$1.key" -out "$TMP/$1.pem" 2>/dev/null
  }
  make_cert long 365
  make_cert short 5
}

@test "passes for a cert valid longer than the threshold" {
  run "$SCRIPT" -d 30 -f "$TMP/long.pem"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "flags a cert expiring within the threshold" {
  run "$SCRIPT" -d 30 -f "$TMP/short.pem"
  [ "$status" -eq 1 ]
  [[ "$output" == *"EXPIRING within 30 days"* ]]
}

@test "checks several certs and reports the worst result" {
  run "$SCRIPT" -d 30 -f "$TMP/long.pem" "$TMP/short.pem"
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "returns 2 for an unreadable cert" {
  run "$SCRIPT" -f "$TMP/missing.pem"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "rejects a non-numeric threshold" {
  run "$SCRIPT" -d soon -f "$TMP/long.pem"
  [ "$status" -eq 2 ]
}
