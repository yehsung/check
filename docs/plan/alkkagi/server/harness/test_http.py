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
        state = body.get("state")
        if state is not None:
            self.assertIs(type(state["placement_revision"]), int)
            self.assertGreaterEqual(state["placement_revision"], 1)
            for field in ("my_ready", "opponent_ready"):
                self.assertIs(type(state[field]), bool)
            if state["phase"] == "placing" or not (state["my_ready"] and state["opponent_ready"]):
                self.assert_hidden_arrangement(state)
        return body

    def write(self, user, operation, match_id, *, revision=None, placement_revision=None,
              action=None, expected="ok", **parameters):
        if revision is not None:
            parameters["p_expected_revision"] = revision
        if placement_revision is not None:
            parameters["p_expected_placement_revision"] = placement_revision
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
        response = self.write("b", "respond", match_id, p_accept=True)
        state = response["state"]
        self.assertEqual(state["id"], match_id)
        self.assertEqual(state["phase"], "placing")
        self.assertEqual(state["current_player"], "black")
        self.assertEqual(state["my_color"], "white")
        self.assertEqual(state["placement_revision"], 1)
        self.assertFalse(state["my_ready"])
        self.assertFalse(state["opponent_ready"])
        self.assertAlmostEqual(state["deadline_ms"], response["server_now_ms"] + 30_000, delta=1000)
        return self.state("a", match_id)

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
        if before["my_color"] == after["my_color"]:
            for field in ("placement_revision", "my_ready", "opponent_ready"):
                self.assertEqual(after[field], before[field], field)

    def assert_hidden_arrangement(self, state):
        # Check every RPC snapshot, including error, retry, chat and lobby paths.
        # An allowlist also rejects opponent counters or alternate board payloads.
        self.assertEqual(set(state), {
            "id", "revision", "phase", "placement_revision", "my_ready", "opponent_ready",
            "current_player", "my_color", "black", "white", "stones", "deadline_ms",
            "shot_count", "result", "finish_reason", "shot", "chat_seq", "chat", "muted",
        })
        first_id = 0 if state["my_color"] == "black" else 5
        self.assertEqual([stone["id"] for stone in state["stones"]], list(range(first_id, first_id + 5)))
        self.assertTrue(all(stone["owner"] == state["my_color"] for stone in state["stones"]))
        self.assertEqual(state["shot_count"], 0)
        self.assertIsNone(state["shot"])

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
        self.assertEqual(accepted["phase"], "placing")
        self.assertEqual(accepted["my_color"], "white")
        self.assertEqual(accepted["black"]["id"], stack.USERS["a"])
        self.assertEqual(accepted["white"]["id"], stack.USERS["b"])
        self.assertEqual(len(accepted["stones"]), 5)
        self.assertFalse(any(stone["isPlaced"] for stone in accepted["stones"]))
        self.assertEqual(accepted["placement_revision"], 1)
        self.assertFalse(accepted["my_ready"])
        self.assertFalse(accepted["opponent_ready"])
        self.assert_board_unchanged(self.state("a", match_id), self.challenge(action=challenge_action)["state"])
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
        placement_deadline = state["deadline_ms"]
        self.write("a", "ready", match_id, placement_revision=state["placement_revision"], expected="invalid")
        for user, color, first_id, y in (("a", "black", 0, 470), ("b", "white", 5, 130)):
            state = self.state(user, match_id)
            for offset in range(5):
                with self.subTest(color=color, stone=first_id + offset):
                    before = state
                    parameters = {"p_stone_id": first_id + offset, "p_x": 90 + 100 * offset, "p_y": y}
                    placement = action_id()
                    state = self.write(user, "place", match_id, placement_revision=before["placement_revision"],
                                       action=placement, **parameters)["state"]
                    self.assertEqual(state["revision"], before["revision"] + 1)
                    self.assertEqual(state["placement_revision"], before["placement_revision"] + 1)
                    self.assertEqual(state["deadline_ms"], placement_deadline)
                    stone = next(s for s in state["stones"] if s["id"] == first_id + offset)
                    self.assertEqual(stone["owner"], color)
                    self.assertTrue(stone["isPlaced"])
                    self.assertEqual(stone["position"], {"x": parameters["p_x"], "y": y})
                    if offset == 0:
                        retry = self.write(user, "place", match_id, placement_revision=before["placement_revision"],
                                           action=placement, **parameters)["state"]
                        self.assert_board_unchanged(state, retry)
                        stale = self.write(user, "place", match_id, placement_revision=before["placement_revision"],
                                           expected="stale", **parameters)["state"]
                        self.assert_board_unchanged(state, stale)
            ready = action_id()
            revision = state["placement_revision"]
            readied = self.write(user, "ready", match_id, placement_revision=revision, action=ready)
            state = readied["state"]
            self.assertEqual(state["placement_revision"], revision + 1)
            self.assertTrue(state["my_ready"])
            self.assertEqual(state["opponent_ready"], user == "b")
            self.assertEqual(state["phase"], "placing" if user == "a" else "aiming")
            self.assertEqual(state["current_player"], "black")
            if user == "a":
                self.assertEqual(state["deadline_ms"], placement_deadline)
            else:
                self.assertAlmostEqual(state["deadline_ms"], readied["server_now_ms"] + 30_000, delta=1000)
            self.assert_board_unchanged(state, self.write(
                user, "ready", match_id, placement_revision=revision, action=ready)["state"])
        self.assertEqual(len(state["stones"]), 10)
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

    def test_both_members_place_and_ready_concurrently_at_own_revisions(self):
        black = self.active()
        match_id = black["id"]
        states = {"a": black, "b": self.state("b", match_id)}
        revision = black["revision"]
        with ThreadPoolExecutor(max_workers=2) as pool:
            for offset in range(5):
                def place(user):
                    return self.write(user, "place", match_id,
                                      placement_revision=states[user]["placement_revision"],
                                      p_stone_id=offset + (0 if user == "a" else 5),
                                      p_x=90 + 100 * offset, p_y=470 if user == "a" else 130)["state"]

                results = list(pool.map(place, "ab"))
                self.assertEqual(sorted(s["revision"] for s in results), [revision + 1, revision + 2])
                revision += 2
                for user, after in zip("ab", results):
                    self.assertEqual(after["placement_revision"], offset + 2)
                    self.assertEqual(after["phase"], "placing")
                    self.assertEqual(after["deadline_ms"], black["deadline_ms"])
                    self.assertEqual(sum(s["isPlaced"] for s in after["stones"]), offset + 1)
                    self.assertFalse(after["my_ready"] or after["opponent_ready"])
                    states[user] = after

            def ready(user):
                return self.write(user, "ready", match_id,
                                  placement_revision=states[user]["placement_revision"])

            responses = list(pool.map(ready, "ab"))
        self.assertEqual(sorted(r["state"]["phase"] for r in responses), ["aiming", "placing"])
        self.assertEqual(sorted(r["state"]["revision"] for r in responses), [revision + 1, revision + 2])
        for response in responses:
            after = response["state"]
            self.assertEqual(after["placement_revision"], 7)
            self.assertTrue(after["my_ready"])
            self.assertEqual(after["current_player"], "black")
            if after["phase"] == "placing":
                self.assertFalse(after["opponent_ready"])
                self.assertEqual(after["deadline_ms"], black["deadline_ms"])
            else:
                self.assertTrue(after["opponent_ready"])
                self.assertEqual(len(after["stones"]), 10)
                self.assertAlmostEqual(after["deadline_ms"], response["server_now_ms"] + 30_000, delta=1000)
        for user in "ab":
            after = self.state(user, match_id)
            self.assertEqual(after["phase"], "aiming")
            self.assertEqual(after["placement_revision"], 7)
            self.assertEqual(len(after["stones"]), 10)

    def test_white_can_ready_first_and_arrangement_freezes_until_shared_timeout(self):
        black = self.active()
        match_id = black["id"]
        white = self.state("b", match_id)
        for offset in range(5):
            white = self.write("b", "place", match_id, placement_revision=white["placement_revision"],
                               p_stone_id=5 + offset, p_x=90 + 100 * offset, p_y=130)["state"]
        ready_action = action_id()
        expected_revision = white["placement_revision"]
        white = self.write("b", "ready", match_id, action=ready_action,
                           placement_revision=expected_revision)["state"]
        self.assertEqual(white["phase"], "placing")
        self.assertEqual(white["deadline_ms"], black["deadline_ms"])
        self.assertEqual(white["placement_revision"], 7)
        self.assertTrue(white["my_ready"])
        self.assertFalse(white["opponent_ready"])
        for operation, parameters in (("ready", {}), ("place", {"p_stone_id": 5, "p_x": 95, "p_y": 135})):
            rejected = self.write("b", operation, match_id, placement_revision=7,
                                  expected="not_active", **parameters)["state"]
            self.assert_board_unchanged(white, rejected)
        self.assert_board_unchanged(white, self.write(
            "b", "ready", match_id, action=ready_action, placement_revision=expected_revision)["state"])
        black = self.state("a", match_id)
        self.assertEqual(black["placement_revision"], 1)
        self.assertFalse(black["my_ready"])
        self.assertTrue(black["opponent_ready"])
        black = self.write("a", "place", match_id, placement_revision=1,
                           p_stone_id=0, p_x=90, p_y=470)["state"]
        self.assertEqual(black["placement_revision"], 2)
        self.assertEqual(black["deadline_ms"], white["deadline_ms"])
        expired_at = self.set_time(match_id, "deadline_at")
        revealed = self.state("b", match_id)
        self.assertEqual(revealed["phase"], "aiming")
        self.assertEqual(revealed["current_player"], "black")
        self.assertEqual(revealed["revision"], black["revision"] + 1)
        self.assertEqual(revealed["placement_revision"], 7)
        self.assertTrue(revealed["my_ready"] and revealed["opponent_ready"])
        self.assertAlmostEqual(revealed["deadline_ms"], expired_at + 30_000, delta=0.1)
        self.assertEqual(revealed["stones"][5:], white["stones"])
        self.assertEqual(revealed["stones"][0], black["stones"][0])
        self.assertEqual(self.state("a", match_id)["placement_revision"], 2)
        for user, revision in (("a", 2), ("b", 7)):
            for operation, parameters in (("ready", {}), ("place", {
                    "p_stone_id": 0 if user == "a" else 5, "p_x": 95, "p_y": 470 if user == "a" else 130})):
                after = self.write(user, operation, match_id, placement_revision=revision,
                                   expected="not_active", **parameters)["state"]
                self.assertEqual(after["placement_revision"], revision)
                self.assertEqual(after["stones"], revealed["stones"])

    def test_all_responses_hide_opponent_arrangements_including_early_resignation(self):
        challenge_action, accept_action = action_id(), action_id()
        match_id = self.challenge(action=challenge_action)["outgoing"]["id"]
        self.write("b", "respond", match_id, action=accept_action, p_accept=True)
        placements = {}
        for user, stone_id, y in (("a", 0, 329), ("b", 5, 271)):
            placements[user] = action_id()
            self.write(user, "place", match_id, placement_revision=1, action=placements[user],
                       p_stone_id=stone_id, p_x=333, p_y=y)
        self.assertEqual(stack.sql(f"select jsonb_array_length(stones) from public.alk_matches "
                                   f"where id = {uuid_sql(match_id)};"), "10")
        self.challenge(action=challenge_action)
        self.write("b", "respond", match_id, action=accept_action, p_accept=True)
        self.write("b", "respond", match_id, p_accept=True, expected="not_pending")
        self.write("a", "cancel", match_id, expected="not_pending")
        for user, own_id, opponent_id in (("a", 0, 5), ("b", 5, 0)):
            state = self.state(user, match_id)
            self.assertEqual(state["placement_revision"], 2)
            for users in (False, True):
                self.rpc(user, "lobby", p_users=users)
            self.write(user, "place", match_id, placement_revision=1, action=placements[user],
                       p_stone_id=opponent_id, p_x=-1, p_y=-1)  # UUID retry precedes payload validation.
            self.write(user, "place", match_id, placement_revision=1, expected="stale",
                       p_stone_id=own_id, p_x=333, p_y=329 if user == "a" else 271)
            self.write(user, "place", match_id, placement_revision=2, expected="invalid",
                       p_stone_id=opponent_id, p_x=333, p_y=329 if user == "a" else 271)
            for operation, parameters in (("place", {"p_stone_id": own_id, "p_x": 333, "p_y": 329}), ("ready", {})):
                self.write(user, operation, match_id, p_expected_placement_revision=None,
                           expected="invalid", **parameters)
                status, error = self.request(user, "POST", "/rpc/alkkagi_" + operation, {
                    "p_protocol": 1, "p_match_id": match_id, "p_action_id": action_id(),
                    "p_expected_revision": state["revision"], **parameters,
                })
                self.assertEqual(status, 404, "Placement endpoints require the member revision wire key")
                self.assertEqual(error["code"], "PGRST202")
            self.write(user, "ready", match_id, placement_revision=1, expected="stale")
            self.write(user, "ready", match_id, placement_revision=2, expected="invalid")
            self.write(user, "shoot", match_id, revision=state["revision"], expected="not_active",
                       p_stone_id=own_id, p_pull_x=0, p_pull_y=60)
            self.write(user, "leave", match_id, revision=state["revision"], expected="not_active")
            self.write(user, "chat_mute", match_id, p_muted=True)
            self.write(user, "chat_send", match_id, p_body=" ", expected="invalid")
            chat_action = action_id()
            self.write(user, "chat_send", match_id, action=chat_action, p_body="hidden board")
            self.write(user, "chat_send", match_id, action=chat_action, p_body="retry")
            stack.sql(f"update public.alk_match_members set last_chat_at = clock_timestamp() + interval '1 hour' "
                      f"where match_id = {uuid_sql(match_id)} and user_id = {uuid_sql(stack.USERS[user])};")
            self.write(user, "chat_send", match_id, p_body="too soon", expected="rate_limited")
            self.assert_board_unchanged(state, self.state(user, match_id))
        finished = self.write("b", "resign", match_id)["state"]
        self.assertEqual(finished["phase"], "finished")
        self.assertEqual(len(finished["stones"]), 5)
        for user in "ab":
            self.assert_hidden_arrangement(self.state(user, match_id))
            self.assert_hidden_arrangement(self.rpc(user, "lobby", p_users=False)["state"])

    def test_cross_half_boundary_does_not_leak_hidden_collisions(self):
        state = self.active()
        match_id = state["id"]
        black = self.write("a", "place", match_id, placement_revision=1,
                           p_stone_id=0, p_x=300, p_y=320)["state"]
        white = self.write("b", "place", match_id, placement_revision=1,
                           p_stone_id=5, p_x=300, p_y=280)["state"]
        # Opposite edge stones touch at distance 40; own stones need clearance 42.
        for user, stone_id, y, before in (("a", 1, 320, black), ("b", 6, 280, white)):
            rejected = self.write(user, "place", match_id, placement_revision=2, expected="invalid",
                                  p_stone_id=stone_id, p_x=341, p_y=y)["state"]
            self.assertEqual(rejected["placement_revision"], 2)
            self.assertEqual(rejected["stones"], before["stones"])
            accepted = self.write(user, "place", match_id, placement_revision=2,
                                  p_stone_id=stone_id, p_x=342, p_y=y)["state"]
            self.assertEqual(accepted["placement_revision"], 3)
        # Reverse arrival order too, without any opponent position in the wire.
        self.write("b", "place", match_id, placement_revision=3, p_stone_id=7, p_x=450, p_y=280)
        self.write("a", "place", match_id, placement_revision=3, p_stone_id=2, p_x=450, p_y=320)
        self.set_time(match_id, "deadline_at")
        revealed = self.state("a", match_id)
        self.assertEqual(revealed["phase"], "aiming")
        self.assertEqual(len(revealed["stones"]), 10)
        for first, second in ((0, 5), (1, 6), (2, 7)):
            a, b = (revealed["stones"][stone]["position"] for stone in (first, second))
            self.assertEqual(math.hypot(a["x"] - b["x"], a["y"] - b["y"]), 40)

    def test_concurrent_shot_retries_apply_once(self):
        state = self.active()
        match_id = state["id"]
        self.set_time(match_id, "deadline_at")
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
                revision = state["revision"] if operation in ("cancel", "shoot", "resign", "leave") else None
                placement_revision = state["placement_revision"] if operation in ("place", "ready") else None
                response = self.write("c", operation, match_id, revision=revision, placement_revision=placement_revision,
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
        white_state = self.state("b", match_id)
        muted = self.write("b", "chat_mute", match_id, action=mute, p_muted=True)["state"]
        self.assertTrue(muted["muted"])
        self.assert_board_unchanged(white_state, muted)
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
        self.assert_board_unchanged(white_state, second)
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
        # Occupy another own stone's default spot on BOTH halves before one expiry.
        placed = {}
        for user, stone_id, y in (("a", 0, 460), ("b", 5, 140)):
            before = self.state(user, match_id)
            after = self.write(user, "place", match_id, placement_revision=before["placement_revision"],
                               p_stone_id=stone_id, p_x=190, p_y=y)["state"]
            self.assertEqual(after["phase"], "placing")
            self.assertEqual(after["deadline_ms"], state["deadline_ms"])
            placed[stone_id] = next(s for s in after["stones"] if s["id"] == stone_id)
        before = self.state("a", match_id)
        self.assertEqual(before["deadline_ms"], self.state("b", match_id)["deadline_ms"])
        expired_at = self.set_time(match_id, "deadline_at")
        aiming = self.state("a", match_id)
        self.assertEqual(aiming["phase"], "aiming")
        self.assertEqual(aiming["current_player"], "black")
        self.assertEqual(aiming["revision"], before["revision"] + 1)
        self.assertEqual(aiming["placement_revision"], 2)
        self.assertTrue(aiming["my_ready"])
        self.assertTrue(aiming["opponent_ready"])
        self.assertEqual(len(aiming["stones"]), 10)
        self.assertAlmostEqual(aiming["deadline_ms"], expired_at + 30_000, delta=0.1)
        for stone_id, stone in placed.items():
            self.assertEqual(aiming["stones"][stone_id], stone)
        white = self.state("b", match_id)
        self.assertEqual(white["placement_revision"], 2)
        self.assert_board_unchanged(aiming, white)
        self.assertEqual(stack.sql(f"select jsonb_array_length(stones) from public.alk_matches "
                                   f"where id = {uuid_sql(match_id)};"), "10")
        for index, stone in enumerate(aiming["stones"]):
            self.assertTrue(stone["isPlaced"])
            self.assertFalse(stone["isOut"])
            x, y = stone["position"]["x"], stone["position"]["y"]
            self.assertTrue(20 <= x <= 580)
            self.assertTrue(320 <= y <= 580 if stone["owner"] == "black" else 20 <= y <= 280)
            for other in aiming["stones"][:index]:
                clearance = 42 if other["owner"] == stone["owner"] else 40
                self.assertGreaterEqual(math.hypot(x - other["position"]["x"], y - other["position"]["y"]), clearance)

    def test_overdue_turns_pass_from_original_deadlines(self):
        state = self.active()
        match_id = state["id"]
        self.set_time(match_id, "deadline_at", 31)
        aiming = self.state("a", match_id)
        self.assertEqual(aiming["phase"], "aiming")
        self.assertEqual(aiming["current_player"], "white")
        self.assertEqual(aiming["revision"], state["revision"] + 2)
        self.assertEqual(aiming["placement_revision"], 1)
        self.assertTrue(aiming["my_ready"] and aiming["opponent_ready"])
        self.assertTrue(all(s["isPlaced"] for s in aiming["stones"]))
        for seconds, passes, player in ((1, 1, "black"), (31, 2, "black"), (61, 3, "white")):
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

    def test_finished_peers_can_leave_with_the_same_observed_revision(self):
        state = self.active()
        match_id = state["id"]
        state = self.write("a", "resign", match_id)["state"]
        observed = state["revision"]
        self.write("a", "leave", match_id, revision=observed)
        self.write("b", "leave", match_id, revision=observed)
        left = stack.sql(f"select count(*) from public.alk_match_members where match_id = {uuid_sql(match_id)} "
                         "and left_at is not null;")
        self.assertEqual(left, "2", "One peer leaving cannot prevent the other peer returning to the lobby")

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
