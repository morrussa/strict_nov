# StrictNov

StrictNov is a high-reliability narrative engine for the Defold game engine. Unlike traditional visual novel frameworks that rely on runtime debugging, StrictNov utilizes a custom, machine-optimized syntax (MCODE) paired with an extremely strict static checker to ensure your narrative logic is airtight and bug-free.

Narrative scripts often fail due to "invisible" errors: an unclosed if statement, a broken jump target, or an accidental infinite loop. StrictNov solves this by enforcing a syntax that is easy for humans to write but impossible for machines to misinterpret.

The included dialogue/mcode_checker.py acts as a compiler for your story, catching:

    Logic Leaks: Blocks not explicitly closed with E (End), G (Goto), or > (Options).

    Flow Anomalies: Potential infinite loops and unreachable dialogue blocks.

    Structural Integrity: Improperly nested I (If) blocks or cross-block logic violations.

    Dead Ends: Dialogue paths that lead nowhere.

# MCODE Syntax Overview

MCODE uses single-character prefixes to maximize parsing speed and clarity.

1. Structural Commands
Command	Description	Example
O	Object/Block: Defines the start of a dialogue segment.	OStart_Scene
A	Anchor: A target point for jumping within or between blocks.	ALabel01
G	Goto: Manually jump to a specific Anchor.	GLabel01
E	End: Closes the current block and disables the UI.	E

2. Narrative & Visuals
Command	Description	Example
T	Text: The dialogue content. Supports \n and Rich Text tags.	THello, world!
N	Name: Sets the name of the current speaker.	NNarrator
C	Character: Changes character animations/expressions.	Cosage_happy
S	Speed: Sets the typewriter text speed (frames per char).	S20

3. Logic & Variables
Command	Description	Example
I(...)	If Block: Complex conditional logic. Must be closed with an I.	I($score > 10)
?(...)	Inline If: Simple, one-line conditional check.	?($gold < 5) TYou are poor.
M(...)	Manage: Variable modification (Set, +, -, *, /).	M($hp == 10, -)
>	Option: Defines a player choice and its jump target.	>Yes#OPath_A

# The Static Checker (mcode_checker.py)

The heart of StrictNov is its Python-based static analyzer. Before launching your game, run the checker to audit your dialogue.txt.

How to run:
Bash

cd dialogue
python mcode_checker.py dialogue.txt