-- Alkkagi rolling helper. Draft only; apply with the match/placement RPC migration.
-- Source of truth: Sources/CheckCore/AlkkagiGame.swift (shoot, step, contactTime,
-- resolveContact, moveStones and finishShot). No placement, clocks or authorization.
-- The caller must authorize the shot/owner and pass the server's stored stone order:
-- array order is significant because the last pair wins equal-time contacts.
--
-- Input: 1..10 canonical stones with unique int32 ids, black/white owners, numeric
-- position/velocity {x,y}, and boolean isOut/isPlaced. All numbers must be finite.
-- The selected stone must be placed, in play, and have its center in [0,600]^2.
-- Pull length must be finite and >= 6; speed = min(length,135)*11, opposite pull.
-- Unplaced/out stones do not participate. Surviving centers are not radius-clamped;
-- ring-outs retain the departed center, as in Swift. Output keeps the input order,
-- ids, owners and placement flags, and canonicalizes EVERY velocity to zero.
-- Invalid input or unsafe float8 arithmetic raises SQLSTATE 22023.
--
-- Output: {stones:[...],steps:int,duration:float8,result:null|black|white|draw}.
-- duration is simulated seconds (steps/240), not wall-clock time or animation time.
-- Only the fully settled state determines the result; eliminating one color early
-- must not prevent the last survivor from subsequently ringing out for a draw.
--
-- Each tick has the same 64-contact limit as Swift, including discarding any time
-- left when that limit is reached. There are at most 2400 ticks (10 seconds). At
-- the cap, retain positions/out flags and force rest before determining the result.
-- This final forced rest is a server safeguard absent from the Swift engine.
-- A normal shot from rest has total speed norm <= 1485; restitution cannot increase
-- its energy and each tick damps by exp(-2/240). Thus all speeds are < 6 by tick
-- 662 (2.758334 seconds), well before the cap. Seeded velocities are accepted for
-- deterministic replay/testing but need not satisfy that tighter bound.
-- Lengths use PostgreSQL's built-in point distance (scaled hypot), avoiding the
-- spurious overflow of sqrt(x*x+y*y). Cross-language float8/libm rounding can differ.

create function public.alkkagi_simulate(
  p_stones jsonb,
  p_stone_id integer,
  p_pull_x double precision,
  p_pull_y double precision
)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = pg_catalog
as $fn$
declare
  c_step constant double precision := 1.0::double precision / 240.0;
  c_board constant double precision := 600.0;
  c_diameter constant double precision := 40.0;
  c_damping constant double precision := exp(-2.0 * c_step);
  c_rest_speed constant double precision := 6.0;

  v_count integer;
  v_stone jsonb;
  v_id_number numeric;
  v_id integer;
  v_ids integer[] := '{}';
  v_owners text[] := '{}';
  v_x double precision[] := '{}';
  v_y double precision[] := '{}';
  v_vx double precision[] := '{}';
  v_vy double precision[] := '{}';
  v_out boolean[] := '{}';
  v_placed boolean[] := '{}';
  v_shooter integer;
  v_component double precision;
  v_length double precision;
  v_scale double precision;

  v_steps integer := 0;
  v_tick integer;
  v_iteration integer;
  v_index integer;
  v_first integer;
  v_second integer;
  v_contact_first integer;
  v_contact_second integer;
  v_time_left double precision;
  v_travel double precision;
  v_time double precision;
  v_dx double precision;
  v_dy double precision;
  v_rx double precision;
  v_ry double precision;
  v_separation double precision;
  v_closing double precision;
  v_speed_squared double precision;
  v_discriminant double precision;
  v_distance double precision;
  v_relative_length double precision;
  v_nx double precision;
  v_ny double precision;
  v_cx double precision;
  v_cy double precision;
  v_ix double precision;
  v_iy double precision;
  v_end_x double precision;
  v_end_y double precision;
  v_settled boolean;
  v_black integer := 0;
  v_white integer := 0;
  v_result text;
  v_stones jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_stones) is distinct from 'array' then
    raise exception using errcode = '22023', message = 'alkkagi_simulate: stones must be an array';
  end if;
  v_count := jsonb_array_length(p_stones);
  if v_count < 1 or v_count > 10 then
    raise exception using errcode = '22023', message = 'alkkagi_simulate: expected 1..10 stones';
  end if;
  if p_stone_id is null or p_pull_x is null or p_pull_y is null
     or not (p_pull_x > '-Infinity'::double precision and p_pull_x < 'Infinity'::double precision)
     or not (p_pull_y > '-Infinity'::double precision and p_pull_y < 'Infinity'::double precision) then
    raise exception using errcode = '22023', message = 'alkkagi_simulate: stone id and finite pull are required';
  end if;
  v_length := point(p_pull_x, p_pull_y) <-> point(0.0, 0.0);
  if not (v_length >= 6.0 and v_length < 'Infinity'::double precision) then
    raise exception using errcode = '22023', message = 'alkkagi_simulate: finite pull length must be at least 6';
  end if;

  for v_index in 1..v_count loop
    v_stone := p_stones -> (v_index - 1);
    if jsonb_typeof(v_stone) is distinct from 'object'
       or jsonb_typeof(v_stone -> 'id') is distinct from 'number'
       or jsonb_typeof(v_stone -> 'owner') is distinct from 'string'
       or (v_stone ->> 'owner') not in ('black', 'white')
       or jsonb_typeof(v_stone -> 'position') is distinct from 'object'
       or jsonb_typeof(v_stone #> '{position,x}') is distinct from 'number'
       or jsonb_typeof(v_stone #> '{position,y}') is distinct from 'number'
       or jsonb_typeof(v_stone -> 'velocity') is distinct from 'object'
       or jsonb_typeof(v_stone #> '{velocity,x}') is distinct from 'number'
       or jsonb_typeof(v_stone #> '{velocity,y}') is distinct from 'number'
       or jsonb_typeof(v_stone -> 'isOut') is distinct from 'boolean'
       or jsonb_typeof(v_stone -> 'isPlaced') is distinct from 'boolean' then
      raise exception using errcode = '22023', message = 'alkkagi_simulate: invalid canonical stone';
    end if;
    v_id_number := (v_stone ->> 'id')::numeric;
    if v_id_number <> trunc(v_id_number)
       or v_id_number < -2147483648::numeric or v_id_number > 2147483647::numeric then
      raise exception using errcode = '22023', message = 'alkkagi_simulate: stone id must be an int32';
    end if;
    v_id := v_id_number::integer;
    if v_id = any(v_ids) then
      raise exception using errcode = '22023', message = 'alkkagi_simulate: duplicate stone id';
    end if;
    v_ids[v_index] := v_id;
    v_owners[v_index] := v_stone ->> 'owner';
    v_x[v_index] := (v_stone #>> '{position,x}')::double precision;
    v_y[v_index] := (v_stone #>> '{position,y}')::double precision;
    v_vx[v_index] := (v_stone #>> '{velocity,x}')::double precision;
    v_vy[v_index] := (v_stone #>> '{velocity,y}')::double precision;
    v_out[v_index] := (v_stone ->> 'isOut')::boolean;
    v_placed[v_index] := (v_stone ->> 'isPlaced')::boolean;
    foreach v_component in array array[v_x[v_index], v_y[v_index], v_vx[v_index], v_vy[v_index]] loop
      if not (v_component > '-Infinity'::double precision and v_component < 'Infinity'::double precision) then
        raise exception using errcode = '22023', message = 'alkkagi_simulate: stone coordinates and velocities must be finite';
      end if;
    end loop;
    if v_id = p_stone_id then
      v_shooter := v_index;
    end if;
  end loop;

  if v_shooter is null then
    raise exception using errcode = '22023', message = 'alkkagi_simulate: unknown stone id';
  end if;
  if v_out[v_shooter] or not v_placed[v_shooter]
     or not (v_x[v_shooter] >= 0.0 and v_x[v_shooter] <= c_board
             and v_y[v_shooter] >= 0.0 and v_y[v_shooter] <= c_board) then
    raise exception using errcode = '22023', message = 'alkkagi_simulate: selected stone must be placed and on the board';
  end if;

  -- shoot: retain multiplication by the reciprocal and the Swift operation order.
  v_scale := -(least(v_length, 135.0::double precision) * 11.0) / v_length;
  v_vx[v_shooter] := p_pull_x * v_scale;
  v_vy[v_shooter] := p_pull_y * v_scale;

  for v_tick in 1..2400 loop
    v_steps := v_tick;
    v_time_left := c_step;

    -- step starts with moveStones(for: 0), before looking for contacts.
    for v_index in 1..v_count loop
      if not v_placed[v_index] or v_out[v_index] then continue; end if;
      if not (v_x[v_index] >= 0.0 and v_x[v_index] <= c_board
              and v_y[v_index] >= 0.0 and v_y[v_index] <= c_board) then
        v_out[v_index] := true;
        v_vx[v_index] := 0.0;
        v_vy[v_index] := 0.0;
      end if;
    end loop;

    for v_iteration in 1..64 loop
      v_travel := v_time_left;
      v_contact_first := null;
      v_contact_second := null;
      for v_first in 1..v_count loop
        if not v_placed[v_first] or v_out[v_first] then continue; end if;
        for v_second in (v_first + 1)..v_count loop
          if not v_placed[v_second] or v_out[v_second] then continue; end if;

          -- contactTime(first, second), including the immediate-overlap branch.
          v_dx := v_x[v_second] - v_x[v_first];
          v_dy := v_y[v_second] - v_y[v_first];
          v_rx := v_vx[v_second] - v_vx[v_first];
          v_ry := v_vy[v_second] - v_vy[v_first];
          v_separation := v_dx * v_dx + v_dy * v_dy - c_diameter * c_diameter;
          if v_separation < -1e-7::double precision then
            v_time := 0.0;
          else
            v_closing := v_dx * v_rx + v_dy * v_ry;
            v_speed_squared := v_rx * v_rx + v_ry * v_ry;
            if not (v_closing < 0.0 and v_speed_squared > 0.0) then continue; end if;
            v_discriminant := v_closing * v_closing - v_speed_squared * v_separation;
            if v_discriminant < 0.0 then continue; end if;
            v_time := (-v_closing - sqrt(v_discriminant)) / v_speed_squared;
            if v_time < -1e-10::double precision then continue; end if;
            v_time := greatest(0.0::double precision, v_time);
          end if;
          if v_time > v_travel then continue; end if;

          -- A collision only exists while both centers are still on the board.
          v_end_x := v_x[v_first] + v_vx[v_first] * v_time;
          v_end_y := v_y[v_first] + v_vy[v_first] * v_time;
          if not (v_end_x >= 0.0 and v_end_x <= c_board
                  and v_end_y >= 0.0 and v_end_y <= c_board) then continue; end if;
          v_end_x := v_x[v_second] + v_vx[v_second] * v_time;
          v_end_y := v_y[v_second] + v_vy[v_second] * v_time;
          if not (v_end_x >= 0.0 and v_end_x <= c_board
                  and v_end_y >= 0.0 and v_end_y <= c_board) then continue; end if;

          -- <= deliberately lets the later pair replace an equal-time contact.
          v_travel := v_time;
          v_contact_first := v_first;
          v_contact_second := v_second;
        end loop;
      end loop;

      -- moveStones(for: travel). Impact effects have no effect on rolling state.
      for v_index in 1..v_count loop
        if not v_placed[v_index] or v_out[v_index] then continue; end if;
        v_x[v_index] := v_x[v_index] + v_vx[v_index] * v_travel;
        v_y[v_index] := v_y[v_index] + v_vy[v_index] * v_travel;
        if not (v_x[v_index] >= 0.0 and v_x[v_index] <= c_board
                and v_y[v_index] >= 0.0 and v_y[v_index] <= c_board) then
          v_out[v_index] := true;
          v_vx[v_index] := 0.0;
          v_vy[v_index] := 0.0;
        end if;
      end loop;
      v_time_left := greatest(0.0::double precision, v_time_left - v_travel);
      exit when v_contact_first is null;

      -- resolveContact: use the saved pair, even if travel just rang one out.
      v_first := v_contact_first;
      v_second := v_contact_second;
      v_dx := v_x[v_second] - v_x[v_first];
      v_dy := v_y[v_second] - v_y[v_first];
      v_distance := point(v_dx, v_dy) <-> point(0.0, 0.0);
      v_rx := v_vx[v_second] - v_vx[v_first];
      v_ry := v_vy[v_second] - v_vy[v_first];
      if v_distance > 1e-10::double precision then
        v_scale := 1.0::double precision / v_distance;
        v_nx := v_dx * v_scale;
        v_ny := v_dy * v_scale;
      else
        v_relative_length := point(v_rx, v_ry) <-> point(0.0, 0.0);
        if v_relative_length > 0.0 then
          v_scale := -1.0::double precision / v_relative_length;
          v_nx := v_rx * v_scale;
          v_ny := v_ry * v_scale;
        else
          v_nx := 1.0;
          v_ny := 0.0;
        end if;
      end if;
      v_scale := greatest(0.0::double precision, c_diameter - v_distance) / 2.0;
      v_cx := v_nx * v_scale;
      v_cy := v_ny * v_scale;
      v_x[v_first] := v_x[v_first] - v_cx;
      v_y[v_first] := v_y[v_first] - v_cy;
      v_x[v_second] := v_x[v_second] + v_cx;
      v_y[v_second] := v_y[v_second] + v_cy;

      v_closing := v_rx * v_nx + v_ry * v_ny;
      if v_closing < -1e-8::double precision then
        -- Equal masses and restitution 0.92; preserve tangential motion.
        v_scale := -v_closing * 1.92::double precision / 2.0;
        v_ix := v_nx * v_scale;
        v_iy := v_ny * v_scale;
        v_vx[v_first] := v_vx[v_first] - v_ix;
        v_vy[v_first] := v_vy[v_first] - v_iy;
        v_vx[v_second] := v_vx[v_second] + v_ix;
        v_vy[v_second] := v_vy[v_second] + v_iy;
      end if;

      -- moveStones(for: 0): overlap correction can itself cause a ring-out.
      for v_index in 1..v_count loop
        if not v_placed[v_index] or v_out[v_index] then continue; end if;
        if not (v_x[v_index] >= 0.0 and v_x[v_index] <= c_board
                and v_y[v_index] >= 0.0 and v_y[v_index] <= c_board) then
          v_out[v_index] := true;
          v_vx[v_index] := 0.0;
          v_vy[v_index] := 0.0;
        end if;
      end loop;
      exit when v_time_left <= 1e-12::double precision;
    end loop;

    -- Damping runs once per fixed tick, even after exhausting the contact budget.
    v_settled := true;
    for v_index in 1..v_count loop
      if not v_placed[v_index] or v_out[v_index] then continue; end if;
      v_vx[v_index] := v_vx[v_index] * c_damping;
      v_vy[v_index] := v_vy[v_index] * c_damping;
      v_length := point(v_vx[v_index], v_vy[v_index]) <-> point(0.0, 0.0);
      if v_length < c_rest_speed then
        v_vx[v_index] := 0.0;
        v_vy[v_index] := 0.0;
      else
        v_settled := false;
      end if;
    end loop;
    exit when v_settled;
  end loop;

  -- finishShot, also used after forced settlement at the 10-second safety cap.
  for v_index in 1..v_count loop
    if v_placed[v_index] and not v_out[v_index] then
      if v_owners[v_index] = 'black' then v_black := v_black + 1;
      else v_white := v_white + 1; end if;
    end if;
    v_stones := v_stones || jsonb_build_array(jsonb_build_object(
      'id', v_ids[v_index],
      'owner', v_owners[v_index],
      'position', jsonb_build_object('x', v_x[v_index], 'y', v_y[v_index]),
      'velocity', jsonb_build_object('x', 0.0::double precision, 'y', 0.0::double precision),
      'isOut', v_out[v_index],
      'isPlaced', v_placed[v_index]
    ));
  end loop;
  if v_black = 0 and v_white = 0 then v_result := 'draw';
  elsif v_white = 0 then v_result := 'black';
  elsif v_black = 0 then v_result := 'white';
  end if;
  return jsonb_build_object(
    'stones', v_stones,
    'steps', v_steps,
    'duration', v_steps * c_step,
    'result', v_result
  );
exception
  when numeric_value_out_of_range or division_by_zero then
    raise exception using errcode = '22023', message = 'alkkagi_simulate: input exceeds safe float8 arithmetic';
end
$fn$;

comment on function public.alkkagi_simulate(jsonb, integer, double precision, double precision) is
  'Pure fixed-1/240 Alkkagi rolling simulation in canonical stone-array order. Returns settled stones, steps, duration in seconds and result. '
  'Caps work at 2400 ticks and 64 contacts per tick; only the owning authenticated-match SECURITY DEFINER RPC may invoke it.';

-- Supabase defaults can grant service_role explicitly; keep this helper owner-only.
revoke all on function public.alkkagi_simulate(jsonb, integer, double precision, double precision)
  from public, anon, authenticated, service_role;
