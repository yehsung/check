#!/usr/bin/env python3
"""Raw completion-count contracts on an already running disposable fixture.

Apply the physics, matches and progress drafts through the fixture owner's startup
first, then run: python3 docs/plan/alkkagi/server/harness/test_progress.py
Run test_http.py THEN this suite, separately from native apps sharing the accounts.
This suite never starts services or installs SQL. Owner SQL seeds only owned
matches/clocks and restores counter baselines; it never contacts production.
Passing these tests does not establish private achievement/reward eligibility.
"""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import json
import unittest

import local_stack as stack
import test_http as http_contracts  # Do not import/subclass its TestCase into this module.


COUNTS = ("played", "wins", "losses", "draws")
uuid_sql = http_contracts.uuid_sql
json_sql = http_contracts.json_sql
action_id = http_contracts.action_id


class ProgressContracts(unittest.TestCase):
    def setUp(self):
        self.http = http_contracts.HTTPContracts()
        self.addCleanup(self.http.doCleanups)
        self.http.setUp()  # Enforces the managed loopback fixture and tracks owned matches.
        self.users = ",".join(uuid_sql(stack.USERS[user]) for user in "ab")
        self.baseline = json.loads(stack.sql(f"""
            select jsonb_build_object(
              'totals', (select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                from public.alk_progress_totals t where user_id in ({self.users})),
              'daily', (select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb)
                from public.alk_progress_daily d where user_id in ({self.users}))
            );
        """))
        self.addCleanup(self.restore_counters)
        self.initial = {user: self.progress(user) for user in "ab"}

    def restore_counters(self):
        # HTTP cleanup removes our matches; retention deliberately cannot remove
        # counters, so restore the exact pre-test rows separately.
        stack.sql(f"""
            begin;
            delete from public.alk_progress_daily where user_id in ({self.users});
            delete from public.alk_progress_totals where user_id in ({self.users});
            insert into public.alk_progress_totals
              select * from jsonb_populate_recordset(null::public.alk_progress_totals,
                {json_sql(self.baseline['totals'])});
            insert into public.alk_progress_daily
              select * from jsonb_populate_recordset(null::public.alk_progress_daily,
                {json_sql(self.baseline['daily'])});
            commit;
        """)

    def progress(self, user):
        result = json.loads(stack.sql(f"select public.alk_progress({uuid_sql(stack.USERS[user])});"))
        self.assertEqual(set(result), {*COUNTS, *("today_" + field for field in COUNTS), "kst_day"})
        for field in (*COUNTS, *("today_" + field for field in COUNTS)):
            self.assertIs(type(result[field]), int)
            self.assertGreaterEqual(result[field], 0)
        self.assertEqual(result["played"], sum(result[field] for field in ("wins", "losses", "draws")))
        self.assertEqual(result["today_played"], sum(result["today_" + field] for field in ("wins", "losses", "draws")))
        self.assertEqual(result["kst_day"], datetime.now(timezone(timedelta(hours=9))).date().isoformat())
        return result

    def assert_delta(self, user, *, played, wins, losses, draws, historical=False):
        after = self.progress(user)
        for field, delta in zip(COUNTS, (played, wins, losses, draws)):
            self.assertEqual(after[field], self.initial[user][field] + delta, field)
            self.assertEqual(after["today_" + field], self.initial[user]["today_" + field]
                             + (0 if historical else delta), "today_" + field)

    def guard(self, match_id):
        return json.loads(stack.sql(f"select coalesce(to_jsonb(progress_recorded_at), 'null'::jsonb) from public.alk_matches "
                                    f"where id = {uuid_sql(match_id)};"))

    def seed_rolling(self, match_id, result, *, finished_at=None):
        """Seed only this test's active match; the normal HTTP clock path finishes it."""
        self.assertIn(match_id, self.http.matches)
        self.assertIn(result, ("black", "white", "draw"))
        ended = "clock_timestamp() - interval '1 second'"
        if finished_at is not None:
            instant = datetime.fromisoformat(finished_at)
            self.assertIsNotNone(instant.tzinfo)
            ended = "'" + instant.isoformat() + "'::timestamptz"
        stack.sql(f"""
            begin;
            update public.alk_match_members set is_ready = true where match_id = {uuid_sql(match_id)};
            with fixture as (
              select {ended} as ended,
                public.alk_autofill(public.alk_autofill(stones, 'black'), 'white') as stones
              from public.alk_matches where id = {uuid_sql(match_id)} and status = 'active'
            )
            update public.alk_matches m set phase = 'rolling', stones = f.stones,
              roll_until = f.ended, deadline_at = f.ended + interval '29 seconds',
              rolling_result = '{result}', shot_count = 1,
              shot = jsonb_build_object('id', {uuid_sql(action_id())}, 'stone_id', 0,
                'pull', jsonb_build_object('x', 0, 'y', 60), 'steps', 240,
                'started_at_ms', public.alk_ms(f.ended - interval '1 second'), 'initial_stones', f.stones)
              from fixture f where m.id = {uuid_sql(match_id)};
            commit;
        """)

    def test_resignation_counts_both_and_retries_leave_and_status_rewrites_count_once(self):
        state = self.http.active()
        match_id = state["id"]
        for user in "ab":
            self.assertEqual(self.progress(user), self.initial[user])
        self.assertIsNone(self.guard(match_id))
        resign = action_id()
        finished = self.http.write("a", "resign", match_id, revision=state["revision"], action=resign)["state"]
        self.assertEqual((finished["phase"], finished["result"]), ("finished", "white"))
        self.assertNotIn("progress_recorded_at", finished)
        recorded_at = self.guard(match_id)
        self.assertIsNotNone(recorded_at)
        self.assert_delta("a", played=1, wins=0, losses=1, draws=0)
        self.assert_delta("b", played=1, wins=1, losses=0, draws=0)
        self.http.write("a", "resign", match_id, revision=state["revision"], action=resign)
        self.http.write("a", "resign", match_id, expected="not_active")
        leave = action_id()
        self.http.write("a", "leave", match_id, action=leave)
        self.http.write("a", "leave", match_id, action=leave)
        self.http.write("a", "leave", match_id)
        self.http.write("b", "leave", match_id)
        stack.sql(f"update public.alk_matches set status = status where id = {uuid_sql(match_id)};")
        self.assertEqual(self.guard(match_id), recorded_at)
        self.assert_delta("a", played=1, wins=0, losses=1, draws=0)
        self.assert_delta("b", played=1, wins=1, losses=0, draws=0)

    def test_concurrent_lazy_ring_out_finalization_counts_once(self):
        state = self.http.active()
        match_id = state["id"]
        self.seed_rolling(match_id, "black")
        self.assertIsNone(self.guard(match_id))
        for user in "ab":
            self.assertEqual(self.progress(user), self.initial[user])
        with ThreadPoolExecutor(max_workers=2) as pool:
            states = list(pool.map(lambda user: self.http.state(user, match_id), "ab"))
        for after in states:
            self.assertEqual((after["phase"], after["result"], after["finish_reason"]),
                             ("finished", "black", "ring_out"))
            self.assertEqual(after["revision"], state["revision"] + 1)
        recorded_at = self.guard(match_id)
        self.assertIsNotNone(recorded_at)
        self.http.state("a", match_id)
        self.http.state("b", match_id)
        self.assertEqual(self.guard(match_id), recorded_at)
        self.assert_delta("a", played=1, wins=1, losses=0, draws=0)
        self.assert_delta("b", played=1, wins=0, losses=1, draws=0)

    def test_match_retention_does_not_erase_lifetime_or_daily_counts(self):
        match_id = self.http.active()["id"]
        self.http.write("a", "resign", match_id)
        before = {user: self.progress(user) for user in "ab"}
        stack.sql(f"""
            begin;
            delete from realtime.fixture_signals where event = 'alkkagi' and payload ->> 'm' = '{match_id}';
            delete from public.alk_matches where id = {uuid_sql(match_id)};
            commit;
        """)
        for user in "ab":
            self.assertIsNone(self.http.rpc(user, "state", "not_found", p_match_id=match_id)["state"])
            self.assertEqual(self.progress(user), before[user])

    def test_kst_daily_boundary_uses_canonical_finish_instead_of_late_poll(self):
        # Adjacent UTC seconds fall on different KST days; both are polled years later.
        for result, instant in (("draw", "2020-01-01T14:59:59+00:00"), ("black", "2020-01-01T15:00:00+00:00")):
            match_id = self.http.active()["id"]
            self.seed_rolling(match_id, result, finished_at=instant)
            self.assertEqual(self.http.state("a", match_id)["result"], result)
        self.assert_delta("a", played=2, wins=1, losses=0, draws=1, historical=True)
        self.assert_delta("b", played=2, wins=0, losses=1, draws=1, historical=True)
        for user in "ab":
            for day, deltas in (("2020-01-01", (1, 0, 0, 1)),
                                ("2020-01-02", (1, 1, 0, 0) if user == "a" else (1, 0, 1, 0))):
                before = next((row for row in self.baseline["daily"]
                               if row["user_id"] == stack.USERS[user] and row["kst_day"] == day), {})
                after = json.loads(stack.sql(f"select to_jsonb(d) from public.alk_progress_daily d "
                                             f"where user_id = {uuid_sql(stack.USERS[user])} and kst_day = '{day}';"))
                for field, delta in zip(COUNTS, deltas):
                    self.assertEqual(after[field], before.get(field, 0) + delta, (user, day, field))
            # Session timezone must not change the helper's KST date or today's counters.
            shifted = json.loads(stack.sql(f"""
                begin;
                set local time zone 'Pacific/Honolulu';
                select public.alk_progress({uuid_sql(stack.USERS[user])});
                rollback;
            """))
            self.assertEqual(shifted, self.progress(user))

    def test_rolled_back_finish_rolls_back_guard_and_both_counter_sets(self):
        match_id = self.http.active()["id"]
        inside = json.loads(stack.sql(f"""
            begin;
            update public.alk_matches set status = 'finished', phase = 'finished', result = 'black',
              finish_reason = 'resign', finished_at = clock_timestamp(), deadline_at = null
              where id = {uuid_sql(match_id)};
            select jsonb_build_object('a', public.alk_progress({uuid_sql(stack.USERS['a'])}),
              'b', public.alk_progress({uuid_sql(stack.USERS['b'])}),
              'guard', (select progress_recorded_at from public.alk_matches where id = {uuid_sql(match_id)}));
            rollback;
        """))
        self.assertIsNotNone(inside["guard"])
        for user, deltas in (("a", (1, 1, 0, 0)), ("b", (1, 0, 1, 0))):
            for field, delta in zip(COUNTS, deltas):
                self.assertEqual(inside[user][field], self.initial[user][field] + delta)
                self.assertEqual(inside[user]["today_" + field], self.initial[user]["today_" + field] + delta)
            self.assertEqual(self.progress(user), self.initial[user])
        self.assertIsNone(self.guard(match_id))
        self.assertEqual(self.http.state("a", match_id)["phase"], "placing")
        self.http.write("a", "resign", match_id)
        self.assert_delta("a", played=1, wins=0, losses=1, draws=0)
        self.assert_delta("b", played=1, wins=1, losses=0, draws=0)

    def test_counter_tables_helpers_and_match_guard_are_private(self):
        for user in ("a", None):
            for table in ("alk_progress_totals", "alk_progress_daily"):
                for method, body in (("GET", None), ("POST", {}), ("PATCH", {"played": 999}), ("DELETE", None)):
                    with self.subTest(user=user, table=table, method=method):
                        self.http.assert_denied(user, method, "/" + table, body, missing_code="PGRST205")
            for helper, body in (("alk_record_progress", {}),
                                 ("alk_progress", {"p_user_id": stack.USERS["a"]}),
                                 ("alk_progress", {"p_user_id": stack.USERS["b"]})):
                self.http.assert_denied(user, "POST", "/rpc/" + helper, body, missing_code="PGRST202")
            self.http.assert_denied(user, "GET", "/alk_matches?select=progress_recorded_at", missing_code="PGRST205")
            self.http.assert_denied(user, "PATCH", "/alk_matches", {"progress_recorded_at": None}, missing_code="PGRST205")
        for user in "ab":
            self.assertEqual(self.progress(user), self.initial[user])

    def test_profile_cascade_erases_only_its_own_counter_rows(self):
        # A transaction-local extra profile avoids deleting shared fixture users.
        synthetic = uuid_sql(action_id())
        remaining = json.loads(stack.sql(f"""
            begin;
            insert into auth.users(id) values ({synthetic});
            insert into public.profiles(id, display_name) values ({synthetic}, 'Progress FK fixture');
            insert into public.alk_progress_totals(user_id, played, wins) values ({synthetic}, 1, 1);
            insert into public.alk_progress_daily(user_id, kst_day, played, wins)
              values ({synthetic}, '2020-01-01', 1, 1);
            delete from public.profiles where id = {synthetic};
            select jsonb_build_object(
              'totals', (select count(*) from public.alk_progress_totals where user_id = {synthetic}),
              'daily', (select count(*) from public.alk_progress_daily where user_id = {synthetic}));
            rollback;
        """))
        self.assertEqual(remaining, {"totals": 0, "daily": 0})
        for user in "ab":
            self.assertEqual(self.progress(user), self.initial[user])


if __name__ == "__main__":
    unittest.main(verbosity=2)
