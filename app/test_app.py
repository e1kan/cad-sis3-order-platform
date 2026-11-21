import json
import os
import threading
import unittest
import urllib.error
import urllib.request
from unittest import mock

os.environ.setdefault("TOPIC_ARN", "arn:aws:sns:eu-central-1:000000000000:test-topic")
os.environ.setdefault("AWS_REGION", "eu-central-1")

import app  # noqa: E402  (needs the environment variables above)


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = app.ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
        cls.base = "http://127.0.0.1:%d" % cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def call(self, path, body=None):
        data = None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
        req = urllib.request.Request(self.base + path, data=data, method="GET" if data is None else "POST")
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_health_returns_ok(self):
        status, body = self.call("/health")
        self.assertEqual(status, 200)
        self.assertEqual(body, {"status": "ok"})

    def test_valid_order_publishes_one_event(self):
        with mock.patch.object(app.sns, "publish") as publish:
            status, body = self.call("/orders", {"orderId": "o-1", "customerId": "c42", "total": 19.5})
        self.assertEqual(status, 202)
        self.assertEqual(body["orderId"], "o-1")
        publish.assert_called_once()
        kwargs = publish.call_args.kwargs
        self.assertEqual(kwargs["MessageAttributes"]["eventType"]["StringValue"], "OrderPlaced")
        self.assertEqual(json.loads(kwargs["Message"])["customerId"], "c42")

    def test_missing_customer_is_rejected(self):
        with mock.patch.object(app.sns, "publish") as publish:
            status, _ = self.call("/orders", {"total": 5})
        self.assertEqual(status, 400)
        publish.assert_not_called()

    def test_invalid_json_is_rejected(self):
        status, _ = self.call("/orders", b"junk")
        self.assertEqual(status, 400)

    def test_publish_failure_gives_500(self):
        with mock.patch.object(app.sns, "publish", side_effect=RuntimeError("boom")):
            status, _ = self.call("/orders", {"customerId": "c1", "total": 1})
        self.assertEqual(status, 500)


if __name__ == "__main__":
    unittest.main()
