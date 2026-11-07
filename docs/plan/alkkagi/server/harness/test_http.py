#!/usr/bin/env python3
"""HTTP contracts against an already running, disposable local_stack fixture.

Run: python3 docs/plan/alkkagi/server/harness/test_http.py
This suite never starts services or applies SQL drafts. Owner SQL only controls
fixture clocks/privacy and restores the synthetic records after every test.
"""

import json
from concurrent.futures import ThreadPoolExecutor
import math
import re
import unittest
import urllib.error
import urllib.parse
import urllib.request
import uuid

import local_stack as stack


def uuid_sql(value):
    """Only canonical UUIDs enter SQL; SQL is sent through stack.sql's stdin."""
    return "'" + str(uuid.UUID(value)) + "'::uuid"


def json_sql(value):
    return "'" + json.dumps(value, ensure_ascii=False, allow_nan=False).replace("'", "''") + "'::jsonb"


def action_id():
    return str(uuid.uuid4())


class HTTPContracts(unittest.TestCase):
    def setUp(self):
        endpoint = urllib.parse.urlsplit(stack.BASE_URL)
        self.assertEqual(endpoint.scheme, "http", "Use the disposable loopback fixture")
        self.assertIn(endpoint.hostname, ("127.0.0.1", "localhost", "::1"))
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        self.fixture_users = ",".join(uuid_sql(stack.USERS[key]) for key in "abcd")
        self.challenges = set()
        self.matches = set()
        a, b = (uuid_sql(stack.USERS[key]) for key in "ab")
        self.baseline = json.loads(stack.sql(f"""
            select jsonb_build_object(
              'profiles', (select jsonb_agg(jsonb_build_object(
                'id', id, 'visibility', visibility, 'focus_mode', focus_mode))
                from public.profiles where id in ({self.fixture_users})),
              'clients', (select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb)
                from public.alk_clients c where user_id in ({self.fixture_users})),
              'blocks', (select coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb)
                from public.fixture_blocks f where (a = {a} and b = {b}) or (a = {b} and b = {a}))
            );
        """))
        self.addCleanup(self.reset_fixture)
        for user in "abcd":
            self.rpc(user, "lobby", p_users=False)

    def reset_fixture(self):
        # Also find a created match if an assertion failed before its ID was read.
        challenges = ",".join(uuid_sql(value) for value in sorted(self.challenges)) or "null::uuid"
        matches = ",".join(uuid_sql(value) for value in sorted(self.matches)) or "null::uuid"
        owned = f"""select id from public.alk_matches where id in ({matches}) or id in (
            select match_id from public.alk_match_actions
            where actor_id in ({self.fixture_users}) and action_id in ({challenges}) and kind = 'challenge')"""
        a, b = (uuid_sql(stack.USERS[key]) for key in "ab")
        stack.sql(f"""
            begin;
            delete from realtime.fixture_signals
              where event = 'alkkagi' and payload ->> 'm' in (select id::text from ({owned}) owned);
            delete from public.alk_matches where id in ({owned});
            delete from public.alk_clients where user_id in ({self.fixture_users});
            insert into public.alk_clients(user_id, protocol, last_seen_at)
              select user_id, protocol, last_seen_at
              from jsonb_populate_recordset(null::public.alk_clients, {json_sql(self.baseline['clients'])});
            update public.profiles p set visibility = original.visibility, focus_mode = original.focus_mode
              from jsonb_to_recordset({json_sql(self.baseline['profiles'])})
                as original(id uuid, visibility text, focus_mode integer)
              where p.id = original.id;
            delete from public.fixture_blocks where (a = {a} and b = {b}) or (a = {b} and b = {a});
            insert into public.fixture_blocks(a, b)
              select a, b from jsonb_populate_recordset(
                null::public.fixture_blocks, {json_sql(self.baseline['blocks'])});
            commit;
        """)

    def request(self, user, method, path, body=None):
        headers = {"Accept": "application/json"}
        if user is not None:
            headers["Authorization"] = "Bearer " + stack.token(user)
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body, ensure_ascii=False, allow_nan=False).encode("utf-8")
        request = urllib.request.Request(
            stack.BASE_URL.rstrip("/") + path, data=data, headers=headers, method=method
        )
        try:
            with self.opener.open(request, timeout=20) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as error:
            with error:
                status, raw = error.code, error.read()
        except (OSError, urllib.error.URLError):
            self.fail(f"{method} {path}: could not reach the managed local fixture")
        try:
            return status, json.loads(raw) if raw else None
        except (ValueError, UnicodeDecodeError):
            self.fail(f"{method} {path}: HTTP {status}, expected JSON")

    def rpc(self, user, operation, expected="ok", **parameters):
        status, body = self.request(
            user, "POST", "/rpc/alkkagi_" + operation, {"p_protocol": 1, **parameters}
        )
        # Never log Request objects, headers, tokens, or arbitrary response bodies.
        error = ""
        if status != 200 and isinstance(body, dict):
            error = f" ({body.get('code')}: {body.get('message')})"
            error = re.sub(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "[redacted]", error)
        self.assertEqual(status, 200, f"alkkagi_{operation}: HTTP {status}{error}")
        self.assertIsInstance(body, dict)
        self.assertEqual(body.get("status"), expected, f"alkkagi_{operation}")
        self.assertEqual(body.get("protocol"), 1)
        self.assertTrue(math.isfinite(body["server_now_ms"]))
        self.assertGreater(body["server_now_ms"], 0)
        self.assertEqual(body["me"]["id"], stack.USERS[user])
        return body

    def write(self, user, operation, match_id, *, revision=None, action=None, expected="ok", **parameters):
        if revision is not None:
            parameters["p_expected_revision"] = revision
        return self.rpc(user, operation, expected, p_match_id=match_id,
                        p_action_id=action or action_id(), **parameters)

    def challenge(self, user="a", opponent="b", *, action=None, expected="ok"):
        action = action or action_id()
        self.challenges.add(action)
        response = self.rpc(user, "challenge", expected,
                            p_opponent=stack.USERS[opponent], p_action_id=action)
        for key in ("outgoing", "state"):
            if response.get(key):
                self.matches.add(str(uuid.UUID(response[key]["id"])))
        return response

    def invite(self):
        return self.challenge()["outgoing"]["id"]

    def active(self):
        match_id = self.invite()
        state = self.write("b", "respond", match_id, p_accept=True)["state"]
        self.assertEqual(state["id"], match_id)
        self.assertEqual(state["phase"], "placing_black")
        self.assertEqual(state["current_player"], "black")
        self.assertEqual(state["my_color"], "white")
        return state

    def state(self, user, match_id, cursor=0):
        return self.rpc(user, "state", p_match_id=match_id, p_since_chat_seq=cursor)["state"]

    def set_time(self, match_id, column, seconds_ago=1):
        self.assertIn(column, ("deadline_at", "invite_expires_at", "roll_until", "finished_at"))
        self.assertIs(type(seconds_ago), int)
        return float(stack.sql(f"""
            update public.alk_matches
              set {column} = clock_timestamp() - interval '{seconds_ago:d} seconds'
              where id = {uuid_sql(match_id)} returning extract(epoch from {column}) * 1000;
        """))

    def visibility(self, private):
        value = "private" if private else "public"
        stack.sql(f"update public.profiles set visibility = '{value}' where id = {uuid_sql(stack.USERS['b'])};")

    def block(self, direction=None):
        a, b = (uuid_sql(stack.USERS[key]) for key in "ab")
        query = f"delete from public.fixture_blocks where (a = {a} and b = {b}) or (a = {b} and b = {a});"
        if direction is not None:
            self.assertIn(direction, ("ab", "ba"))
            first, second = (uuid_sql(stack.USERS[key]) for key in direction)
            query += f"insert into public.fixture_blocks(a, b) values ({first}, {second});"
        stack.sql(query)

    def assert_board_unchanged(self, before, after):
        for field in ("revision", "phase", "current_player", "stones", "shot_count", "shot", "result"):
            self.assertEqual(after[field], before[field], field)

    def test_invitation_retries_and_acceptance(self):
        challenge_action = action_id()
        invited = self.challenge(action=challenge_action)
        self.assertIsNone(invited["state"])
        invite = invited["outgoing"]
        match_id = invite["id"]
        self.assertEqual(invite["opponent"]["id"], stack.USERS["b"])
        self.assertGreater(invite["expires_at_ms"], invited["server_now_ms"])
        self.assertEqual(self.challenge(action=challenge_action)["outgoing"], invite)
        self.assertEqual(self.challenge(expected="already_pending")["outgoing"]["id"], match_id)
        incoming = self.rpc("b", "lobby", p_users=False)
        self.assertNotIn("users", incoming)
        self.assertEqual([row["id"] for row in incoming["incoming"]], [match_id])
        self.assertEqual(incoming["incoming"][0]["opponent"]["id"], stack.USERS["a"])
        self.write("a", "respond", match_id, p_accept=True, expected="forbidden")
        self.write("b", "cancel", match_id, expected="forbidden")
        accept_action = action_id()
        accepted = self.write("b", "respond", match_id, action=accept_action, p_accept=True)["state"]
        retried = self.write("b", "respond", match_id, action=accept_action, p_accept=True)["state"]
        self.assert_board_unchanged(accepted, retried)
        self.assertEqual(accepted["phase"], "placing_black")
        self.assertEqual(accepted["my_color"], "white")
        self.assertEqual(accepted["black"]["id"], stack.USERS["a"])
        self.assertEqual(accepted["white"]["id"], stack.USERS["b"])
        self.assertEqual(len(accepted["stones"]), 10)
        self.assertFalse(any(stone["isPlaced"] for stone in accepted["stones"]))
        self.assert_board_unchanged(accepted, self.challenge(action=challenge_action)["state"])
        for user, color in (("a", "black"), ("b", "white")):
            lobby = self.rpc(user, "lobby", p_users=False)
            self.assertIsNone(lobby["outgoing"])
            self.assertEqual(lobby["incoming"], [])
            self.assertEqual(lobby["state"]["id"], match_id)
            self.assertEqual(lobby["state"]["my_color"], color)
            self.assertTrue(lobby["me"]["busy"])
        self.challenge("a", "c", expected="busy")
        self.challenge("c", "a", expected="target_busy")

    def test_place_ready_shoot_and_retries(self):
        state = self.active()
        match_id = state["id"]
        self.write("a", "ready", match_id, revision=state["revision"], expected="invalid")
        for user, color, first_id, y in (("a", "black", 0, 470), ("b", "white", 5, 130)):
            for offset in range(5):
                with self.subTest(color=color, stone=first_id + offset):
                    before = state
                    parameters = {"p_stone_id": first_id + offset, "p_x": 90 + 100 * offset, "p_y": y}
                    placement = action_id()
                    state = self.write(user, "place", match_id, revision=before["revision"],
                                       action=placement, **parameters)["state"]
                    self.assertEqual(state["revision"], before["revision"] + 1)
                    stone = next(s for s in state["stones"] if s["id"] == first_id + offset)
                    self.assertEqual(stone["owner"], color)
                    self.assertTrue(stone["isPlaced"])
                    self.assertEqual(stone["position"], {"x": parameters["p_x"], "y": y})
                    if offset == 0:
                        retry = self.write(user, "place", match_id, revision=before["revision"],
                                           action=placement, **parameters)["state"]
                        self.assert_board_unchanged(state, retry)
                        stale = self.write(user, "place", match_id, revision=before["revision"],
                                           expected="stale", **parameters)["state"]
                        self.assert_board_unchanged(state, stale)
            ready = action_id()
            revision = state["revision"]
            state = self.write(user, "ready", match_id, revision=revision, action=ready)["state"]
            self.assertEqual(state["phase"], "placing_white" if user == "a" else "aiming")
            self.assertEqual(state["current_player"], "white" if user == "a" else "black")
            self.assert_board_unchanged(state, self.write(
                user, "ready", match_id, revision=revision, action=ready)["state"])
        self.assertTrue(all(stone["isPlaced"] for stone in state["stones"]))
        for user, stone, expected in (("b", 5, "forbidden"), ("a", 5, "invalid")):
            rejected = self.write(user, "shoot", match_id, revision=state["revision"],
                                  p_stone_id=stone, p_pull_x=0, p_pull_y=60, expected=expected)["state"]
            self.assert_board_unchanged(state, rejected)
        shot_action = action_id()
        revision = state["revision"]
        shot = self.write("a", "shoot", match_id, revision=revision, action=shot_action,
                          p_stone_id=0, p_pull_x=0, p_pull_y=60)["state"]
        self.assertEqual(shot["phase"], "rolling")
        self.assertEqual(shot["revision"], revision + 1)
        self.assertEqual(shot["shot_count"], 1)
        self.assertIsNone(shot["result"])
        self.assertEqual(shot["deadline_ms"], state["deadline_ms"])
        self.assertEqual(shot["shot"]["id"], shot_action)
        self.assertEqual(shot["shot"]["stone_id"], 0)
        self.assertEqual(shot["shot"]["pull"], {"x": 0, "y": 60})
        self.assertEqual(shot["shot"]["initial_stones"], state["stones"])
        self.assertGreater(shot["shot"]["steps"], 0)
        self.assertNotEqual(shot["stones"], state["stones"])
        self.assertTrue(all(s["velocity"] == {"x": 0, "y": 0} for s in shot["stones"]))
        self.set_time(match_id, "roll_until", -3600)
        retry = self.write("a", "shoot", match_id, revision=revision, action=shot_action,
                           p_stone_id=0, p_pull_x=0, p_pull_y=60)["state"]
        self.assert_board_unchanged(shot, retry)
        self.write("a", "shoot", match_id, revision=revision, expected="stale",
                   p_stone_id=0, p_pull_x=0, p_pull_y=60)
        self.set_time(match_id, "roll_until")
        next_turn = self.state("b", match_id)
        self.assertEqual(next_turn["phase"], "aiming")
        self.assertEqual(next_turn["current_player"], "white")
        self.assertEqual(next_turn["shot_count"], 1)
        self.assertEqual(next_turn["revision"], shot["revision"] + 1)
        self.assertEqual(next_turn["stones"], shot["stones"])
        self.assert_board_unchanged(next_turn, self.write(
            "a", "shoot", match_id, revision=revision, action=shot_action,
            p_stone_id=0, p_pull_x=0, p_pull_y=60)["state"])

    def test_concurrent_shot_retries_apply_once(self):
        state = self.active()
        match_id = state["id"]
        self.set_time(match_id, "deadline_at", seconds_ago=31)
        state = self.state("a", match_id)
        self.assertEqual((state["phase"], state["current_player"]), ("aiming", "black"))
        action = action_id()

        def shoot(_):
            return self.write("a", "shoot", match_id, revision=state["revision"], action=action,
                              p_stone_id=0, p_pull_x=0, p_pull_y=70)["state"]

        with ThreadPoolExecutor(max_workers=2) as pool:
            first, second = list(pool.map(shoot, range(2)))
        self.assertEqual(first["shot_count"], 1)
        self.assertEqual(first["revision"], state["revision"] + 1)
        self.assert_board_unchanged(first, second)
        count = stack.sql(f"select count(*) from public.alk_match_actions where match_id = {uuid_sql(match_id)} "
                          f"and action_id = {uuid_sql(action)};")
        self.assertEqual(count, "1")

    def test_outsider_cannot_observe_or_mutate_match(self):
        state = self.active()
        match_id = state["id"]
        response = self.rpc("c", "state", "not_found", p_match_id=match_id)
        self.assertIsNone(response["state"])
        operations = (
            ("cancel", {}), ("respond", {"p_accept": True}),
            ("place", {"p_stone_id": 0, "p_x": 90, "p_y": 470}),
            ("ready", {}), ("shoot", {"p_stone_id": 0, "p_pull_x": 0, "p_pull_y": 60}),
            ("resign", {}), ("leave", {}),
            ("chat_send", {"p_body": "outsider"}), ("chat_mute", {"p_muted": True}),
        )
        for operation, parameters in operations:
            with self.subTest(operation=operation):
                revision = state["revision"] if operation in ("cancel", "place", "ready", "shoot", "resign", "leave") else None
                response = self.write("c", operation, match_id, revision=revision,
                                      expected="not_found", **parameters)
                self.assertIsNone(response["state"])
                self.assertNotIn("incoming", response)
                self.assertNotIn("outgoing", response)
        after = self.state("a", match_id)
        self.assert_board_unchanged(state, after)
        self.assertEqual(after["chat_seq"], 0)
        self.assertEqual(after["chat"], [])

    def test_chat_cursor_retries_and_member_mute(self):
        state = self.active()
        match_id = state["id"]
        for body in (" \t\n", "한" * 101):
            self.write("a", "chat_send", match_id, p_body=body, expected="invalid")
        mute = action_id()
        muted = self.write("b", "chat_mute", match_id, action=mute, p_muted=True)["state"]
        self.assertTrue(muted["muted"])
        self.assert_board_unchanged(state, muted)
        self.assertFalse(self.state("a", match_id)["muted"])
        first_action = action_id()
        text = "한" * 99 + "🙂"  # 100 Unicode codepoints, more than 100 UTF-8 bytes.
        first = self.write("a", "chat_send", match_id, action=first_action, p_body="  " + text + " \n")["state"]
        self.assertEqual(first["chat_seq"], 1)
        self.assertEqual(first["chat"][0]["body"], text)
        self.assertEqual(first["chat"][0]["sender_id"], stack.USERS["a"])
        self.assertTrue(self.state("b", match_id)["muted"])
        second = self.write("b", "chat_send", match_id, p_body="답장 ' $(never-a-shell)")["state"]
        self.assertEqual(second["chat_seq"], 2)
        self.assertTrue(second["muted"])
        self.assert_board_unchanged(state, second)
        retried = self.write("a", "chat_send", match_id, action=first_action, p_body="  " + text + " \n")["state"]
        self.assertEqual(retried["chat_seq"], 2)
        self.assertEqual([row["seq"] for row in retried["chat"]], [1, 2])
        self.assertEqual(self.state("b", match_id, 1)["chat"], [second["chat"][1]])
        self.assertEqual(self.state("b", match_id, 2)["chat"], [])
        self.assertEqual(self.state("b", match_id, -1)["chat"], second["chat"])
        self.assertEqual(self.write("b", "chat_mute", match_id, action=mute, p_muted=True)["state"]["chat_seq"], 2)
        unmuted = self.write("b", "chat_mute", match_id, p_muted=False)["state"]
        self.assertFalse(unmuted["muted"])
        self.assertEqual(unmuted["chat"], second["chat"])

    def test_placement_deadlines_autofill_and_preserve_placed_stones(self):
        state = self.active()
        match_id = state["id"]
        # Occupy a different stone's default spot, forcing collision-safe autofill.
        placed = self.write("a", "place", match_id, revision=state["revision"],
                            p_stone_id=0, p_x=190, p_y=460)["state"]
        expired_at = self.set_time(match_id, "deadline_at")
        black_filled = self.state("b", match_id)
        self.assertEqual(black_filled["phase"], "placing_white")
        self.assertEqual(black_filled["current_player"], "white")
        self.assertEqual(black_filled["revision"], placed["revision"] + 1)
        self.assertAlmostEqual(black_filled["deadline_ms"], expired_at + 30_000, delta=0.1)
        self.assertEqual(black_filled["stones"][0], placed["stones"][0])
        self.assertEqual(sum(s["isPlaced"] for s in black_filled["stones"] if s["owner"] == "black"), 5)
        self.assertFalse(any(s["isPlaced"] for s in black_filled["stones"] if s["owner"] == "white"))
        expired_at = self.set_time(match_id, "deadline_at")
        aiming = self.state("a", match_id)
        self.assertEqual(aiming["phase"], "aiming")
        self.assertEqual(aiming["current_player"], "black")
        self.assertEqual(aiming["revision"], black_filled["revision"] + 1)
        self.assertAlmostEqual(aiming["deadline_ms"], expired_at + 30_000, delta=0.1)
        self.assertEqual(aiming["stones"][0], placed["stones"][0])
        for index, stone in enumerate(aiming["stones"]):
            self.assertTrue(stone["isPlaced"])
            self.assertFalse(stone["isOut"])
            x, y = stone["position"]["x"], stone["position"]["y"]
            self.assertTrue(20 <= x <= 580)
            self.assertTrue(320 <= y <= 580 if stone["owner"] == "black" else 20 <= y <= 280)
            for other in aiming["stones"][:index]:
                self.assertGreaterEqual(math.hypot(x - other["position"]["x"], y - other["position"]["y"]), 42)

    def test_overdue_turns_pass_from_original_deadlines(self):
        state = self.active()
        match_id = state["id"]
        self.set_time(match_id, "deadline_at", 31)
        aiming = self.state("a", match_id)
        self.assertEqual(aiming["phase"], "aiming")
        self.assertEqual(aiming["current_player"], "black")
        self.assertEqual(aiming["revision"], state["revision"] + 2)
        self.assertTrue(all(s["isPlaced"] for s in aiming["stones"]))
        for seconds, passes, player in ((1, 1, "white"), (31, 2, "white"), (61, 3, "black")):
            with self.subTest(missed_turns=passes):
                expired_at = self.set_time(match_id, "deadline_at", seconds)
                response = self.rpc("b", "state", p_match_id=match_id)
                after = response["state"]
                self.assertEqual(after["phase"], "aiming")
                self.assertEqual(after["current_player"], player)
                self.assertEqual(after["revision"], aiming["revision"] + passes)
                self.assertAlmostEqual(after["deadline_ms"], expired_at + passes * 30_000, delta=0.1)
                self.assertGreater(after["deadline_ms"], response["server_now_ms"])
                self.assertEqual(after["stones"], aiming["stones"])
                self.assertEqual(after["shot_count"], 0)
                aiming = after

    def test_invitation_expiry_allows_a_new_invitation(self):
        match_id = self.invite()
        self.set_time(match_id, "invite_expires_at")
        self.assertEqual(self.rpc("b", "lobby", p_users=False)["incoming"], [])
        expired = self.write("b", "respond", match_id, p_accept=True, expected="expired")
        self.assertIsNone(expired["state"])
        self.assertIsNone(self.rpc("a", "lobby", p_users=False)["outgoing"])
        self.assertNotEqual(self.invite(), match_id)

    def test_visibility_filters_peers_invitations_acceptance_and_chat(self):
        peers = self.rpc("a", "lobby")["users"]
        self.assertEqual({row["id"] for row in peers}, {stack.USERS["b"], stack.USERS["c"]})
        self.challenge("a", "d", expected="not_found")
        match_id = self.invite()
        self.visibility(True)
        self.assertNotIn(stack.USERS["b"], {p["id"] for p in self.rpc("a", "lobby")["users"]})
        self.assertIsNone(self.rpc("a", "lobby", p_users=False)["outgoing"])
        self.assertEqual(self.rpc("b", "lobby", p_users=False)["incoming"], [])
        self.challenge("c", "b", expected="not_found")
        self.write("b", "respond", match_id, p_accept=True, expected="forbidden")
        self.visibility(False)
        self.assertEqual([i["id"] for i in self.rpc("b", "lobby", p_users=False)["incoming"]], [match_id])
        self.write("b", "respond", match_id, p_accept=True)
        self.visibility(True)
        for user in "ab":
            self.write(user, "chat_send", match_id, p_body="private", expected="forbidden")
        self.assertEqual(self.state("a", match_id)["chat_seq"], 0)

    def test_blocks_are_symmetric_for_peers_invitations_acceptance_and_chat(self):
        match_id = self.invite()
        for direction in ("ab", "ba"):
            with self.subTest(blocker=direction[0]):
                self.block(direction)
                for user, other in (("a", "b"), ("b", "a")):
                    lobby = self.rpc(user, "lobby")
                    self.assertNotIn(stack.USERS[other], {p["id"] for p in lobby["users"]})
                    self.assertEqual(lobby["incoming"], [])
                    self.assertIsNone(lobby["outgoing"])
                    self.challenge(user, other, expected="not_found")
                self.write("b", "respond", match_id, p_accept=True, expected="forbidden")
        self.block()
        self.write("b", "respond", match_id, p_accept=True)
        self.block("ba")
        for user in "ab":
            self.write(user, "chat_send", match_id, p_body="blocked", expected="forbidden")
        self.assertEqual(self.state("b", match_id)["chat_seq"], 0)

    def assert_denied(self, user, method, path, body=None, *, missing_code):
        status, response = self.request(user, method, path, body)
        self.assertIn(status, (401, 403, 404), f"{method} {path}: HTTP {status}")
        self.assertIsInstance(response, dict)
        self.assertIn(response.get("code"), ("42501", missing_code))

    def test_direct_tables_and_owner_helpers_are_denied(self):
        state = self.active()
        match_id = state["id"]
        tables = (
            ("alk_clients", "user_id", stack.USERS["a"], {"protocol": 1}),
            ("alk_matches", "id", match_id, {"revision": 9999}),
            ("alk_match_members", "match_id", match_id, {"muted": True}),
            ("alk_match_actions", "match_id", match_id, {"kind": "forged"}),
            ("alk_chat_messages", "match_id", match_id, {"body": "forged"}),
        )
        for user in ("a", None):
            for table, key, value, patch in tables:
                for method, path, body in (
                    ("GET", f"/{table}?{key}=eq.{value}&select=*", None),
                    ("POST", f"/{table}", {}),
                    ("PATCH", f"/{table}?{key}=eq.{value}", patch),
                    ("DELETE", f"/{table}?{key}=eq.{value}", None),
                ):
                    with self.subTest(user=user or "anon", table=table, method=method):
                        self.assert_denied(user, method, path, body, missing_code="PGRST205")
        helpers = (
            ("alk_ms", {"p_at": "2026-11-08T00:00:00Z"}),
            ("alk_lock_users", {"p_first": stack.USERS["a"], "p_second": stack.USERS["b"]}),
            ("alk_initial_stones", {}),
            ("alk_can_place", {"p_stones": state["stones"], "p_color": "black", "p_stone_id": 0, "p_x": 90, "p_y": 470}),
            ("alk_autofill", {"p_stones": state["stones"], "p_color": "black"}),
            ("alk_busy", {"p_user_id": stack.USERS["a"]}),
            ("alk_peer", {"p_user_id": stack.USERS["a"]}),
            ("alk_notify", {"p_match_id": match_id, "p_revision": state["revision"]}),
            ("alk_advance", {"p_match_id": match_id, "p_now": None}),
            ("alk_snapshot", {"p_match_id": match_id, "p_user_id": stack.USERS["a"], "p_since_chat_seq": 0}),
            ("alk_response", {"p_status": "ok", "p_user_id": stack.USERS["a"], "p_match_id": match_id, "p_since_chat_seq": 0}),
            ("alk_match_call", {"p_operation": "state", "p_match_id": match_id, "p_action_id": None,
                                "p_expected_revision": None, "p_payload": {}, "p_protocol": 1}),
            ("alkkagi_simulate", {"p_stones": state["stones"], "p_stone_id": 0, "p_pull_x": 0, "p_pull_y": 60}),
        )
        for user in ("a", None):
            for helper, parameters in helpers:
                with self.subTest(user=user or "anon", helper=helper):
                    self.assert_denied(user, "POST", "/rpc/" + helper, parameters, missing_code="PGRST202")
        self.assert_denied(None, "POST", "/rpc/alkkagi_lobby", {"p_protocol": 1}, missing_code="PGRST202")
        self.assert_board_unchanged(state, self.state("a", match_id))

    def test_finished_leave_is_idempotent_and_clears_chat_after_both_leave(self):
        state = self.active()
        match_id = state["id"]
        self.write("a", "leave", match_id, revision=state["revision"], expected="not_active")
        self.write("a", "chat_send", match_id, p_body="good game")
        finished = self.write("b", "resign", match_id, revision=state["revision"])["state"]
        self.assertEqual(finished["phase"], "finished")
        self.assertEqual(finished["result"], "black")
        self.assertEqual(finished["finish_reason"], "resign")
        self.assertIsNone(finished["deadline_ms"])
        self.assertFalse(self.rpc("a", "lobby", p_users=False)["me"]["busy"])
        grace_chat = self.write("b", "chat_send", match_id, p_body="thanks")["state"]
        self.assertEqual(grace_chat["chat_seq"], 2)
        leave = action_id()
        left = self.write("a", "leave", match_id, revision=finished["revision"], action=leave)["state"]
        self.assertEqual(left["chat"], [])
        self.assertEqual(left["chat_seq"], 2)
        self.assertEqual(left["revision"], finished["revision"] + 1)
        self.assert_board_unchanged(left, self.write(
            "a", "leave", match_id, revision=finished["revision"], action=leave)["state"])
        self.assert_board_unchanged(left, self.write(
            "a", "leave", match_id, revision=left["revision"])["state"])
        self.write("a", "chat_send", match_id, p_body="already left", expected="not_active")
        self.write("a", "chat_mute", match_id, p_muted=True, expected="not_active")
        self.assertIsNone(self.rpc("a", "lobby", p_users=False)["state"])
        self.assertEqual(len(self.state("b", match_id)["chat"]), 2)
        both_left = self.write("b", "leave", match_id, revision=left["revision"])["state"]
        self.assertEqual(both_left["chat"], [])
        self.assertEqual(both_left["chat_seq"], 2)
        self.assertIsNone(self.rpc("b", "lobby", p_users=False)["state"])
        self.assertEqual(stack.sql(f"select count(*) from public.alk_chat_messages where match_id = {uuid_sql(match_id)};"), "0")


if __name__ == "__main__":
    unittest.main(verbosity=2)
