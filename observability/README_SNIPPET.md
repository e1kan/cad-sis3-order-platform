## Observability (Practice 8)

| Signal | Where |
|---|---|
| Custom metrics (EMF, namespace `CourseProject/Orders`, dimension `Stage`) | `OrdersProcessed`, `DuplicatesIgnored`, `OrdersFailed`, emitted by the consumer Lambda in `infra/app.yaml` |
| Structured logs | The consumer prints one JSON line per event (`level`, `message`, `orderId`, `errorType`) |
| Saved Logs Insights query | `orders-consumer/errors-by-type` (text below) |
| Alarms | `OrdersDlqAlarm`, `SnsDeliveryDlqAlarm` (DLQ depth >= 1) -> SNS topic `AlarmTopic` -> email |
| Dashboard | `observability/dashboard.json` (exported), created by the stack as `<stack>-overview` |
| Tracing | X-Ray active tracing on the consumer Lambda, plus a DynamoDB subsegment |
| Budget | `observability/create-budget.sh` (monthly, alerts at 50% and 100%) |

Saved query (`observability/errors-by-type.query`):

```
fields @timestamp, errorType
| filter level = "ERROR"
| stats count(*) as n by errorType
| sort n desc
| limit 20
```

Deploy with alarm emails: `ALARM_EMAIL=you@example.com ./deploy.sh` (click the confirmation link in the email).
