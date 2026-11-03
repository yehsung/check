#!/bin/bash
# 구버전 복제(tf_old.sql) + 시험 본문 = 하네스에 넘기는 시험 파일. 인자: 출력 경로.
D="$(cd "$(dirname "$0")" && pwd)"
{ printf -- "-- 생성물(build_test.sh). 정본: tetris_frames_test.body.sql + tf_old.sql\nset local role postgres;\n"; cat "$D/tf_old.sql"; cat "$D/tetris_frames_test.body.sql"; } > "$1"
