#!/usr/bin/env python3
"""Storage 객체 목록·내려받기 — backup-db.sh --download-storage 가 부른다.

DB 덤프(storage.objects 행)는 객체의 **메타데이터**뿐이고 파일 본체는 Storage(S3) 에 따로 있다(감사 문서 §6).
이 스크립트는 Storage REST API 로 버킷을 재귀 목록화하고, --dest 가 있으면 본체를 내려받는다.

  python3 storage-download.py --list-only          # 버킷별 객체 수·용량만(내려받지 않음)
  python3 storage-download.py --dest <폴더>         # 내려받기(폴더 700, 파일 600). 개인정보 — 저장소 밖에만.

service_role 키는 .env.local 에서 프로세스 안에서만 읽는다. 객체 경로는 출력하지 않는다(사용자 id 가 경로에 든다).
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

PROJECT_REF = "xfnhfjvubetkdnfkfljg"
BASE = "https://%s.supabase.co/storage/v1" % PROJECT_REF
ENV_FILE = os.environ.get("CHECK_ENV_FILE", "/Users/yesung/check/.env.local")
KEY_NAME = "CHECK_SUPABASE_SERVICE_ROLE_KEY"
PAGE = 1000


def service_key():
    with open(ENV_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith(KEY_NAME + "="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("storage: %s 없음" % KEY_NAME)


class Client(object):
    def __init__(self):
        self._key = service_key()

    def _req(self, method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(BASE + path, data=data, method=method)
        req.add_header("apikey", self._key)
        req.add_header("Authorization", "Bearer " + self._key)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        return urllib.request.urlopen(req, timeout=60)

    def json(self, method, path, body=None):
        with self._req(method, path, body) as r:
            return json.loads(r.read().decode())

    def walk(self, bucket, prefix=""):
        """(경로, 크기) 를 재귀로 낸다. 폴더 항목은 id 가 null 이다."""
        offset = 0
        while True:
            items = self.json("POST", "/object/list/" + urllib.parse.quote(bucket, safe=""),
                              {"prefix": prefix, "limit": PAGE, "offset": offset,
                               "sortBy": {"column": "name", "order": "asc"}})
            for it in items:
                path = (prefix + "/" + it["name"]) if prefix else it["name"]
                if it.get("id") is None:
                    for x in self.walk(bucket, path):
                        yield x
                else:
                    yield path, int(((it.get("metadata") or {}).get("size")) or 0)
            if len(items) < PAGE:
                return
            offset += PAGE

    def download(self, bucket, path, dest):
        q = "/object/authenticated/%s/%s" % (urllib.parse.quote(bucket, safe=""), urllib.parse.quote(path))
        os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
        fd = os.open(dest + ".part", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as out, self._req("GET", q) as r:
            while True:
                chunk = r.read(1 << 16)
                if not chunk:
                    break
                out.write(chunk)
        os.replace(dest + ".part", dest)


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--list-only", action="store_true")
    g.add_argument("--dest")
    args = ap.parse_args()
    c = Client()
    summary, failed = [], 0
    for b in c.json("GET", "/bucket"):
        name = b["id"]
        n = size = 0
        for path, sz in c.walk(name):
            n += 1
            size += sz
            if args.dest:
                target = os.path.normpath(os.path.join(args.dest, name, path))
                if not target.startswith(os.path.normpath(args.dest) + os.sep):
                    failed += 1          # 경로 탈출('..') 방어
                    continue
                try:
                    c.download(name, path, target)
                except (urllib.error.URLError, OSError) as e:
                    failed += 1
                    print("storage: %s 객체 하나 실패(%s)" % (name, type(e).__name__), file=sys.stderr)
        summary.append({"bucket": name, "public": bool(b.get("public")), "objects": n, "bytes": size})
    print(json.dumps({"buckets": summary, "downloaded": bool(args.dest), "failed": failed}, ensure_ascii=False))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
