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
- Each stage starts with a panel showing a one-sentence goal and gameplay instructions, with a Learn More button for theoretical background and a Continue button.
- Every stage has an Instructions button on the upper left corner, which opens the same panel described above, an Options button below it, which acts the same as the one on the title screen, and a Main Menu button below it, which prompts the user for confirmation before returning to the title screen.
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

Same as before, but the gauge is full in the beginning and random thoughts start to appear over the buttons, obscuring and disabling them, and interrupting any current hold. They appear as thought bubbles with a subject (that bears no significance) chosen randomly from a list (chosen to be universal and not too specific). Some subjects are marked so that they appear more often than others. For each thought bubble, an arced trail connecting the figure's head and the bubble, consisting of two to four dots depending on the distance, appears first, its dots revealed one by one at evenly spaced intervals over a fixed period. The buttons are disabled only when the bubble appears after the last trail dot.
The player should remove the thought by pressing and holding it. The thought gradually becomes transparent when held and opaque when not. After the first thought is erased, more thoughts appear to a maximum of five and may overlap. New thoughts appear underneath, and only the oldest thought can be removed. Other thoughts are grayed out. The frequency increases for a while but then eventually fades. The stage is cleared after a certain number of thoughts are removed and the gauge is full.
Thoughts will continue to appear once in a while throughout the rest of the game, except the last stage.

### Anapana-3

From now on, the breathing figure is moved to the lower left corner in a smaller size, still breathing constantly, but without the arrows. The breath buttons are no longer needed, but the gauge still is. The same figure is shown again in the center, zoomed in to show only the head (so no breathing is necessary). We focus only on the upper lip and the area around the nostrils, so the rest is darkened.
The area consists of around 10 elliptical regions. Each region occasionally turns yellow for a short while, signifying a sensation. When a region turns yellow, a question mark appears in the center of the region at the same time. The player's goal is to press the region before the color turns back and the question mark disappears. When pressed, the question mark turns into an exclamation mark that expands as it fades away. This fills the awareness gauge, which constantly depletes little by little. Multiple regions can be lit at the same time, and each should be handled independently.
Random thoughts appear from the figure's head in the corner, obscuring the figure in the center. Regions cannot be pressed unless the thought is removed. There is at most only one thought bubble at the same time.
