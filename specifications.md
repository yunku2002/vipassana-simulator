# Vipassana Simulator

A Godot-based sequence of minigames based on the 10-day introductory meditation course given by the Vipassana Research Institute.

## Design Goals

- The minigames illustrate the curriculum of the course, broadly divided into 3 steps: Anapana, Vipassana, and Metta Bhavana.
- Each step consists of multiple stages, with the last step consisting of only one.
- Since the game is not focused on challenge, all stages are unlocked from the beginning.
- But the experience still should be a fun, "gamified" one.
- Mastery and progress are mainly portrayed by previous elements being simplified or automated.
- Only simple instructions for gameplay are shown first, with detailed theoretical background given upon request.

## UI

- A responsive, landscape UI.
- The title screen shows Start, Stage Select, and Options.
- The Start button loads the first stage, but if there is a "next stage", it becomes Continue, which loads that stage.
- Whenever a stage is started, it is set as the next stage, and when it is cleared, the next one is set as the next stage, unless the stage was the final one, in which case it is unset.
- The Stage Select button loads a list of buttons for all stages, each of which loads the stage, and a Back button.
- The Options button opens the options panel (options listed below) with a dimmed background.
- Each stage starts with a panel showing a one-sentence goal and gameplay instructions, with a Learn More button for theoretical background and a Continue button.
- Every stage has an Instructions button on the upper left corner, which opens the same panel described above, an Options button below it, which acts the same as the one on the title screen, and a Main Menu button below it, which prompts the user for confirmation before returning to the title screen.
- After each stage is cleared, a Stage Clear message pops up with Continue and Main Menu buttons.
- For the final stage, the Continue button is replaced with a goodbye message.

## Options

- Language: English (default) or Korean
- Volume: A single slider that controls all audio and a mute button

## Stage Summary

- Anapana-1: Observe your breathing.
- Anapana-2: Stay aware of your breathing, letting go of all thoughts.
- Anapana-3: Observe the sensations around the nostrils and the upper lip.
- Anapana-4: Observe the fainter sensations on the narrower area: the philtrum.
- Vipassana-1: Observe the sensations of the entire body, part by part.
- Vipassana-2: Avoid generating craving or aversion towards sensations.
- Vipassana-3: Observe symmetrically.
- Vipassana-4: Observe as a free flow.
- Metta Bhavana: Share the goodwill with all beings.

## Stage Mechanics

### Anapana-1

A human figure sitting on the floor is shown breathing slowly through the nostrils (animated). The respiration period is not fixed, but rather fluctuating a little, in order to simulate natural breath. Arrows are shown below the nostrils to better signify the respiratory state, colored red when inhaling and blue when exhaling.
The objective is to press and hold the correct Inhaling/Exhaling button (above the figure) in accordance with the breathing cycle, filling up the vertical awareness gauge on the right. The gauge depletes gradually when the correct button is not pressed. The stage is cleared when the gauge is full.

### Anapana-2

Same as Anapana-1, but the gauge is full in the beginning and random thoughts start to appear over the buttons, obscuring and disabling them, and interrupting any current hold. They appear as thought bubbles with a subject (that bears no significance) chosen randomly from a list (chosen to be universal and not too specific). Some subjects are marked so that they appear more often than others. For each thought bubble, an arced trail connecting the figure's head and the bubble, consisting of two to four dots depending on the distance, appears first, its dots revealed one by one at evenly spaced intervals over a fixed period. The buttons are disabled only when the bubble appears after the last trail dot.
The player should remove the thought by pressing and holding it. The thought gradually becomes transparent when held and opaque when not. After the first thought is erased, more thoughts appear to a maximum of five and may overlap. New thoughts appear underneath, and only the oldest thought can be removed. Other thoughts are grayed out. The frequency increases for a while but then eventually fades. The stage is cleared after a certain number of thoughts are removed and the gauge is full.
Thoughts will continue to appear once in a while throughout the rest of the game, except the last stage.

### Anapana-3

From now on, the breathing figure is moved to the lower left corner in a smaller size, still breathing constantly, but without the arrows. The breath buttons are no longer needed, but the gauge still is. The same figure is shown again in the center, zoomed in to show only the head (so no breathing is necessary). We focus only on the upper lip and the area around the nostrils, so the rest is darkened.
A circular region within the area, with randomized position and size kept to be around 1/10th of the area, occasionally turns yellow for a short while, signifying a sensation. At the same time, a question mark appears in the center of the region. The player's goal is to press the region before the color turns back and the question mark disappears. When pressed, the question mark turns into an exclamation mark that expands as it fades away. This fills the awareness gauge, which constantly depletes little by little. Multiple non-overlapping regions can be lit at the same time, and each should be handled independently.
Random thoughts appear from the figure's head in the corner, obscuring the figure in the center. Regions cannot be pressed unless the thought is removed. There is at most only one thought bubble at the same time.

### Anapana-4

Same as Anapana-3, only the area of focus is smaller, and so are the regions, increasing the difficulty. Sensation duration is also shorter. Exclamation marks are replaced with random sensation names. Sensations are categorized into gross and subtle, but it makes no gameplay difference at this stage.

### Vipassana-1

Now the area of focus is circular and moves over the entire body (visualized in a standing position). Observing is done automatically, and the player is charged with moving the area of focus by dragging the body figure. Visually, the area of focus remains still. The breathing figure remains, and random thoughts continue to block the area, pausing observation and focus movement.
Sensations appear within the intersection of the area of focus and the body figure. Each sensation, with a question mark, automatically expands and fades away with a name like in Anapana-4 after a short, randomized moment. The area of focus moving away does not cause them to disappear. Observed sensations leave a copy in blue denoting that the region is "covered". Sensation centers do not appear in covered regions or inside active sensations. (The circles may overlap.) The objective is to reach a certain high percentage of coverage, so the awareness gauge is replaced with a coverage gauge marked with a line representing the percentage goal.
After the goal is reached once, "Once more" appears for a short while. While the message is visible, no sensations appear, and all the remaining ones are naturally observed. When the message goes away, coverage is cleared, and the area of focus is reset to the top of the head. Sensation appearance and observing are faster. The stage is cleared when the goal is reached for the second time.
Sensation names aren't completely randomized, but clustered instead. Before each coverage goal begins, several invisible cluster centers are randomly spawned inside and outside the body figure, but kept a certain distance apart. Each cluster is given a random sensation name. A sensation later uses the name of the closest cluster center.

### Vipassana-2

Same as Vipassana-1, but an equanimity step is added, so observed sensations do not disappear right away. Observation is also simplified so sensations appear with their name, not with a question mark. They periodically shift between their default color and either red, for gross sensations, or green, for subtle ones. The duration in each color is set independently. The change in color should be interpolated. Sensations of the same cluster center are synchronized in color, even though they don't appear at the same time. Different clusters have different timing. Random thoughts pause every color shift.
Only when a sensation is pressed while in its default color and in the area of focus do all sensations of the same cluster expand and fade away at the same time, whether or not they are in the area of focus, leaving a blue copy and increasing coverage. An "anicca" sound effect is also played. Pressing a sensation in the area of focus while in the wrong color (or while blending) causes the soft edge of each sensation of the same cluster to briefly shift towards a more pronounced red. (The body figure can be dragged only when no active sensation in the area of focus is pressed.) The cluster continues to decide new sensations' name.
The coverage goal once again should be met twice as in Vipassana-1. The difference between the two passes is that on the first, sensations are in the default color for less time than in the other color, while it is the other way around in the second. Unresolved sensations are cleared at the start of the second pass. Both passes share the pace of Vipassana-1's second pass.

### Vipassana-3

Same as Vipassana-2, but with two areas of focus always positioned horizontally symmetrically. At the beginning of each pass, they coincide at the head. The standing figure is also composed of two symmetric views split down the middle, initially appearing as one because one view only shows the left side and the other, only the right. When the player drags one of the figures (views), both figures move the same vertically, and in opposite directions horizontally. But they only move horizontally when the areas of focus do not. When the areas of focus overlap (with some margin), they are the ones that move horizontally instead of the figures (in the other direction than the corresponding figure would have moved). They don't cross the center, so when the drag would get the areas of focus past the center, nothing actually moves horizontally. Each view also shouldn't show the other side, so when needed, the areas of focus move closer instead.
Random thoughts and clusters behave the same way. Sensations appear in each area of focus at the same time, so almost twice as fast. They should be pressed while in any one of the two areas of focus. Subtle sensations appear 75% of the time, instead of 50%. The coverage goal is the same. The first pass shares the sensation color timing of Vipassana-2's second pass. In the second pass, the default color time lasts longer and the other, shorter.

### Vipassana-4

Same as Vipassana-3, but sensations expand and fade away automatically at the start and midpoint of each default color phase, whether or not they are in the areas of focus. The sound effect is played only once every three times. The player only needs to move the areas of focus, but sensations may still be pressed as before. 95% of sensations are subtle, thoughts no longer appear, and clusters work the same way. The two passes share the timings of Vipassana-3's second pass with no difference between them.
