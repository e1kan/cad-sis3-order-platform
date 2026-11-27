#!/usr/bin/env bash
# All SIS 3 tests in one run:   ./test.sh [app-stack]
#   DLQ=1  ./test.sh   also runs the poison-message test (about 6-8 minutes)
#   STOP=1 ./test.sh   also stops one task and checks the ALB keeps answering
set -uo pipefail
APP="${1:-cad-sis3-app}"
export AWS_REGION="${AWS_REGION:-eu-central-1}"
out() { aws cloudformation describe-stacks --stack-name "$APP" \
        --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
ALB=$(out AlbDnsName); Q=$(out QueueUrl); DLQ=$(out DlqUrl); TABLE=$(out TableName)
CLUSTER=$(out ClusterName); SVC=$(out ServiceName); TG=$(out TargetGroupArn)
LOGS="/aws/lambda/$APP-consumer"
ID="o-$(date +%s)"
PASS=0; FAIL=0
check() { if [ "$2" = "yes" ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1"; FAIL=$((FAIL+1)); fi; }
http() { curl -s -o /tmp/body.txt -w '%{http_code}' "$@"; }
wait_for() { # wait_for <seconds> <command...>  - retry until the command succeeds
  local t=$1; shift; local end=$((SECONDS+t))
  while [ $SECONDS -lt $end ]; do "$@" >/dev/null 2>&1 && return 0; sleep 5; done; return 1; }
has_item() { [ "$(aws dynamodb get-item --table-name "$TABLE" --key "{\"pk\":{\"S\":\"$1\"}}" \
             --query 'Item.pk.S' --output text 2>/dev/null)" = "$1" ]; }
log_has() { # log_has <message> <orderId>  - structured JSON log line with these fields
  [ -n "$(aws logs filter-log-events --log-group-name "$LOGS" \
        --filter-pattern "{ \$.message = \"$1\" && \$.orderId = \"$2\" }" \
        --query 'events[0].message' --output text 2>/dev/null | grep -v '^None$')" ]; }

echo "== Stack $APP, ALB http://$ALB, test order id $ID"

echo "-- 1. target health and /health"
HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$TG" \
  --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)
check "2 targets healthy (found $HEALTHY)" "$([ "$HEALTHY" = "2" ] && echo yes || echo no)"
check "GET /health returns 200" "$([ "$(http http://$ALB/health)" = 200 ] && echo yes || echo no)"

echo "-- 2. valid order"
check "POST /orders returns 202" "$([ "$(http -X POST http://$ALB/orders -d "{\"orderId\":\"$ID\",\"customerId\":\"c42\",\"total\":19.5}")" = 202 ] && echo yes || echo no)"
check "order stored in DynamoDB (ORDER#$ID)" "$(wait_for 60 has_item "ORDER#$ID" && echo yes || echo no)"
check "dedup marker stored (IDEMP#$ID)" "$(has_item "IDEMP#$ID" && echo yes || echo no)"
check "log has order_processed for $ID" "$(wait_for 60 log_has order_processed "$ID" && echo yes || echo no)"

echo "-- 3. duplicate (same orderId again)"
check "second POST returns 202" "$([ "$(http -X POST http://$ALB/orders -d "{\"orderId\":\"$ID\",\"customerId\":\"c42\",\"total\":19.5}")" = 202 ] && echo yes || echo no)"
check "log has order_duplicate_ignored for $ID" "$(wait_for 90 log_has order_duplicate_ignored "$ID" && echo yes || echo no)"

echo "-- 4. invalid body"
check "POST without customerId returns 400" "$([ "$(http -X POST http://$ALB/orders -d '{"total":5}')" = 400 ] && echo yes || echo no)"
check "POST with junk returns 400" "$([ "$(http -X POST http://$ALB/orders -d 'junk')" = 400 ] && echo yes || echo no)"

if [ "${DLQ:-0}" = "1" ]; then
  echo "-- 5. poison message -> DLQ (waits up to 8 minutes)"
  count() { aws sqs get-queue-attributes --queue-url "$DLQ" --attribute-names ApproximateNumberOfMessages \
            --query 'Attributes.ApproximateNumberOfMessages' --output text; }
  BEFORE=$(count)
  aws sqs send-message --queue-url "$Q" --message-body 'not-json' >/dev/null
  dlq_grew() { [ "$(count)" -gt "$BEFORE" ]; }
  check "message reached the DLQ" "$(wait_for 480 dlq_grew && echo yes || echo no)"
  alarm_on() { aws cloudwatch describe-alarms --alarm-types MetricAlarm \
     --query "MetricAlarms[?contains(AlarmName,'OrdersDlqAlarm') && contains(AlarmName,'$APP')].StateValue" \
     --output text | grep -q ALARM; }
  check "DLQ alarm is in ALARM" "$(wait_for 240 alarm_on && echo yes || echo no)"
  echo "   (optional cleanup: aws sqs purge-queue --queue-url $DLQ)"
fi

if [ "${STOP:-0}" = "1" ]; then
  echo "-- 6. stop one task, ALB must keep answering"
  TASK=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SVC" --query 'taskArns[0]' --output text)
  aws ecs stop-task --cluster "$CLUSTER" --task "$TASK" --reason "SIS3 test" >/dev/null
  OK=0; for i in $(seq 1 12); do [ "$(http http://$ALB/health)" = 200 ] && OK=$((OK+1)); sleep 5; done
  check "ALB answered 200 in $OK of 12 checks while the task was replaced" "$([ "$OK" -ge 10 ] && echo yes || echo no)"
  back() { [ "$(aws ecs describe-services --cluster "$CLUSTER" --services "$SVC" --query 'services[0].runningCount' --output text)" = 2 ]; }
  check "service is back to 2 running tasks" "$(wait_for 240 back && echo yes || echo no)"
fi

echo "== Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
