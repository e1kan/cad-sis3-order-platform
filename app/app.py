import json
import logging
import os
import signal
import sys
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3

logging.basicConfig(stream=sys.stdout, level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("orders-api")

TOPIC_ARN = os.environ["TOPIC_ARN"]          # configuration comes from the environment
sns = boto3.client("sns", region_name=os.environ.get("AWS_REGION"))


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":            # cheap: does not touch SNS or the database
            self._send(200, {"status": "ok"})
        else:
            self._send(200, {"service": "orders-api", "hint": "POST /orders"})

    def do_POST(self):
        if self.path != "/orders":
            return self._send(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length))
            customer = str(data["customerId"])
            total = float(data["total"])
            if total <= 0:
                raise ValueError("total must be positive")
        except (KeyError, ValueError, TypeError):
            return self._send(400, {"error": "need customerId and a positive total"})
        # A client may send its own orderId: a retry then carries the same business key.
        order_id = str(data.get("orderId") or uuid.uuid4())
        event = {"orderId": order_id, "customerId": customer, "total": total}
        try:
            sns.publish(TopicArn=TOPIC_ARN, Message=json.dumps(event),
                        MessageAttributes={"eventType": {"DataType": "String",
                                                         "StringValue": "OrderPlaced"}})
        except Exception:
            log.exception("publish failed orderId=%s", order_id)
            return self._send(500, {"error": "could not publish event"})
        log.info("published OrderPlaced orderId=%s", order_id)
        self._send(202, {"orderId": order_id, "status": "ACCEPTED"})


def main():
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)   # 0.0.0.0, not localhost

    def stop(signum, frame):                  # ECS sends SIGTERM before it kills the task
        log.info("SIGTERM received, shutting down")
        threading.Thread(target=server.shutdown).start()

    signal.signal(signal.SIGTERM, stop)
    log.info("listening on 0.0.0.0:8080")
    server.serve_forever()
    server.server_close()


if __name__ == "__main__":
    main()
