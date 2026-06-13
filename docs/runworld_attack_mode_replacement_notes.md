# RunWorld Attack Mode And Segmented Runner Notes

Date: 2026-06-13
Branch: gameplayv2

## Purpose

This document records the temporary greybox character animation and mouse attack-mode work so it can be replaced cleanly by real model parts, rigged animation clips, or imported character assets later.

The current implementation is intentionally visual-only. It adds a readable attack input and a stronger right-hand slash pose, but it does not add hit detection, damage, weapon collision, monster stagger, combat balance, or event-resolution changes.

## Files Changed

- `project.godot`
  - Adds the `attack` input action.
  - Binds `attack` to `InputEventMouseButton` with `button_index = 1`, the left mouse button.
- `scripts/RunWorld.gd`
  - Owns the attack timer and cooldown.
  - Detects `Input.is_action_just_pressed("attack")`.
  - Sends attack state and progress into `PlayerGreybox.update_run_visual_state(...)`.
  - Shows the attack timer in the RunWorld HUD.
  - Keeps attack visual-only; no lane, event, grid, or monster interaction is changed.
- `scripts/PlayerGreybox.gd`
  - Builds a temporary segmented block-character visual when `use_segmented_runner` is enabled.
  - Hides the imported character mesh when `hide_imported_model_when_segmented` is enabled.
  - Drives run bob, side sway, lateral lean, dash lean, dodge crouch, skill pose, and attack pose procedurally.
  - Implements the current right-hand attack slash animation.
- `scripts/monsters/RunMonsterPlaceholder.gd`
  - Caches collision radius and face-detection distance to avoid scanning the monster node tree every frame.
- `scenes/RunWorld.tscn`
  - Contains current gameplayv2 runtime tuning values for RunWorld speed and camera composition.

## Input Contract

The new attack action is named `attack`.

Current binding:

- Left mouse button: `MOUSE_BUTTON_LEFT`

Runtime behavior:

- A single left-click triggers one attack.
- Holding the button does not continuously attack, because `RunWorld.gd` uses `Input.is_action_just_pressed("attack")`.
- While `attack_timer > 0.0`, the character receives `attack_active = true`.
- Attack progress is calculated as `1.0 - attack_timer / attack_duration`, clamped to `0.0...1.0`.

Current RunWorld attack parameters:

- `attack_duration = 0.58`
- `attack_cooldown_duration = 0.12`

The cooldown currently only prevents immediate retriggering during and just after the attack. It is not a combat-balance value yet.

## RunWorld Data Flow

`RunWorld.gd` owns gameplay state and forwards visual state to the player:

1. `_handle_input(delta)` checks left-click through the `attack` action.
2. On trigger, it sets `attack_timer` and `attack_cooldown`.
3. `_update_timers(delta)` decreases both values over time.
4. `_get_attack_progress()` converts the timer into normalized progress.
5. `_update_player_visual_forward(delta)` calls:

```gdscript
player_node.call(
	"update_run_visual_state",
	delta,
	lateral_axis,
	forward_axis,
	speed_ratio,
	is_player_controlling,
	lane_dash_elapsed > 0.0,
	lane_dash_direction,
	dodge_timer > 0.0,
	skill_timer > 0.0,
	attack_timer > 0.0,
	_get_attack_progress(),
	current_player_visual_yaw_deg
)
```

Replacement guidance:

- Keep `attack_active` and `attack_progress` as the bridge from RunWorld gameplay state into character visuals.
- If replacing the block character with an imported rig, keep this API and map it to an `AnimationTree`, `AnimationPlayer`, or model-specific controller.
- Do not make the animation controller write back into `lane_target`, `player_lane`, grid lines, lane guides, or event trigger logic.

## Temporary Segmented Runner

`PlayerGreybox.gd` currently creates a block-character runner under `VisualRoot/SegmentedRunnerRoot`.

Generated parts:

- `Pelvis`
- `Torso`
- `ChestAccent`
- `Head`
- `LeftArm`
- `RightArm`
- `LeftLeg`
- `RightLeg`

Arm and leg parts use pivot nodes so procedural rotations are easy to read and replace:

- `LeftArmPivot`
- `RightArmPivot`
- `LeftLegPivot`
- `RightLegPivot`

The imported visual model remains in the scene, but the segmented runner hides it by default through `hide_imported_model_when_segmented = true`. This makes the greybox body easier to read during gameplayV2 iteration while preserving the original scene structure for later replacement.

## Current Attack Animation

The right-hand slash is implemented in `_apply_attack_slash_pose(progress, lateral_axis)`.

The current motion has four poses:

- Base pose: normal run arm position.
- Raised pose: right arm lifts high toward the forward-upper area.
- Strike pose: right arm moves down and forward into the slash.
- Recovery pose: arm begins returning to run pose.

Current tuning values:

- `attack_slash_raise_deg = 148.0`
- `attack_slash_forward_deg = 64.0`
- `attack_slash_side_deg = 34.0`
- `attack_torso_twist_deg = 11.0`

Timing shape:

- `0.00...0.34`: arm raises high using ease-out.
- `0.34...0.68`: arm cuts down and forward using ease-in.
- `0.68...0.86`: arm recovers from strike pose.
- `0.86...1.00`: arm returns to base run pose.

The torso also reacts during the strike:

- Slight forward body lean.
- Y-axis twist.
- Z-axis lean adjusted by slash weight and current lateral input.

Replacement guidance:

- Treat this as a placeholder animation spec, not a final animation.
- The real model should provide a clearly readable "raise high, cut forward/down, recover" clip.
- The animation should be playable from `attack_active` or triggered once on left-click.
- The real animation should not alter world movement, lane position, or event triggering unless a later combat task explicitly asks for that.

## Existing Visual State Interactions

The segmented runner also handles:

- Running bob and arm swing.
- Lateral lean from A/D or arrow input.
- Lane dash lean from double-tap A/D.
- Dodge crouch while `dodge_timer > 0.0`.
- Skill pose while `skill_timer > 0.0`.

Attack currently overrides the right arm after the normal run and skill poses are applied. This means attack is visually prioritized for the right arm. If future animation layering is added, use a clearer priority model:

1. Locomotion base.
2. Dash or dodge additive pose.
3. Attack upper-body action.
4. Skill or weapon-specific override, if needed.

## Performance And Stability Notes

The version also includes two safety fixes from the freeze investigation:

- `RunWorld.gd` now has `camera_debug_enabled = false`, so camera solver debug output does not print every 0.5 seconds unless intentionally enabled.
- `RunMonsterPlaceholder.gd` caches collision radius and face-detection distance after configuration, instead of recursively scanning the monster node tree every frame for every monster.

These are not part of attack design, but they are part of the gameplayv2 version being uploaded.

## Verification Completed

- Godot headless project load succeeded.
- Left mouse attack probe succeeded:
  - `InputMap.has_action("attack") == true`
  - Attack click produced `attack_timer > 0.0`
  - Latest probe after longer attack duration produced `attack_timer = 0.513`, `attack_cooldown = 0.633`
- RunWorld simulation from freeze investigation completed without event queue runaway.

## Future Replacement Checklist

- Replace segmented runner with a real rigged model or proper greybox rig.
- Map `attack_active` and `attack_progress` to an animation clip or animation tree state.
- Preserve left-click as the player attack input unless design changes.
- Add hit window data only after attack collision or combat rules are requested.
- Add weapon or VFX only after the base pose reads clearly.
- Keep RunWorld grid, lane guide, and `lane_target` rules untouched unless explicitly requested.
