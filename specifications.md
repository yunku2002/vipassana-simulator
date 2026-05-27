# Vipassana Simulator

A Godot-based sequence of minigames based on the 10-day introductory meditation course given by the Vipassana Research Institute.

## Design Goals

- The minigames illustrate the curriculum of the course, broadly divided into 3 steps: Anapana, Vipassana, and Metta Bhavana.
- Each step consists of multiple stages, with the last step consisting of only one.
- Since the game is not focused on challenge, all stages are unlocked from the beginning.
- But the experience still should be a fun, "gamified" one.
- Mastery and progress is mainly portrayed by previous elements being simplified or automated.
- Only simple instructions for gameplay are shown first, with detailed theoretical background given upon request.

## UI

- A responsive, landscape UI.
- The title screen shows Start, Stage Select, and Options.
- The Start button loads the first stage, but if there is a "next stage", it becomes Continue, which loads the that stage.
- Whenever a stage is started, it is set as the next stage, and when in it is cleared, the next one is set as the next stage, unless the stage was the final one, in which case it is unset.
- The Stage Select button loads a list of buttons for all stages, each of which loads the stage, and a Back button.
- The Options button opens the options panel (options listed below) with a dimmed background.
- Each stage starts with showing a one-sentence goal and gameplay instructions, with a Learn More button for theoretical background.
- Every stage has an Options button on the upper left corner, which acts the same as the one on the title screen, and a Main Menu button below it, which prompts the user for confirmation before returning to the title screen.
- After each stage is cleared, Stage Clear message pops up with Continue and Main Menu buttons.
- For the final stage, the Continue button is replaced with a goodbye message.

## Options

- Language: English (default) or Korean
- Volume: A single slider that controls all audio and a mute button

## Stage Summary

- Anapana-1: Observe your breathing.
- Anapana-2: Stay aware of your breathing, letting go of all thoughts.
- Anapana-3: Observe the sensations around the nostrils and the upper lip.
- Anapana-4: Observe the subtler sensations on the narrower area: the philtrum.
- Vipassana-1: Observe the sensations of the entire body, part by part.
- Vipassana-2: Be mindful of impermanence and do not generate craving or aversion towards sensations.
- Vipassana-3: Observe symmetrically when possible.
- Vipassana-4: Keeping equanimity towards gross sensations will break them down into subtle ones.
- Vipassana-5: Observe as a "free flow" when possible.
- Vipassana-6: Observe into the body.
- Metta Bhavana: Share the goodwill with all beings.

## Stage Mechanics

### Anapana-1

A human figure sitting on the floor is shown breathing slowly through the nostrils (animated). The respiration period is not fixed, but rather fluctuating a little, in order to simulate natural breath. Arrows are shown below the nostrils to better signify the respiratory state, colored red when inhaling and blue when exhaling.
The objective is to press and hold the correct Inhaling/Exhaling button (above the figure) in accordance with the breathing cycle, filling up the vertical awareness gauge on the right. The gauge depletes gradually when the correct button is not pressed. The stage is cleared when the gauge is full.

### Anapana-2

Same as before, but the gauge is full in the beginning and random thoughts start to appear, covering and disabling the buttons. They appear as thought bubbles with a subject (that bears no significance) chosen randomly from a list.
The player should remove the thought by rubbing across the bubble like an eraser. After the first thought is erased after appearing, more thoughts appear and may overlap underneath. The frequency increases for a while but then eventually fades. The stage is cleared after a certain number of thoughts are removed and the gauge is full.
Thoughts continue to appear once in a while throughout the rest of the game, except the last stage.
