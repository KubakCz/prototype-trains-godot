# Railway Control Game Prototype

Your attention please: The 09:42 service to Ockley is 120 minutes late. This is due to a total lack of control by the player.

## Overview

*Note: This is full gdd. Checkout [prototype goals](prototype_goals.md) for prototype goals.*

This project is a mid-scale railway control and routing game inspired mainly by Locomania 2 game.

As a Railroad Dispatcher, your objective is to guide a constant stream of traffic to their destinations safely (and ideally on schedule). You start simply: managing a few manual switches for slow-moving passenger trains. However, as the network expands, the complexity scales. You will eventually manage high-speed corridors and sprawling freight yards where every second counts. Thankfully, the interlocking system is there to prevent disaster... usually.

**The focus is on:**

* Manual control - direct interaction with switches and signals, backed by "realistic-ish" safety safeguards to prevent head-on collisions.
* Progressive difficulty - as the network expands and traffic density increases, the difficulty increases as well.
* Efficiency under pressure - optimize the flow to minimize delays and remamber that the shortest path for one train might not be optimal for the whole network.

**Target audience:**

* Players of "train" games (Transpor Tycoon games, Train-puzzle games)
* Railway enthusiasts

**Competition:**

*TODO*

---

## Gameplay

The game is split between individual levels. Each level comes with a predefined railroad layout, and player must guide trains throughout the level.

The interaction with trains is non-direct - trains are controlled by interaction with signals and switches. The objective for each level might be slightly different, but it always forces player to dispatch trains as fast and as efficiently as possible. As player progresses trhoughout the levels, they get larger, more complex, and with more trains.

### Level Loop

* Start a level
* Read level notes - main goal, secondary goal, optional restrictions...
* Study level layout
* Play the level - manage multiple trains at once
* Success / Failure
* Repeat

### Train Management Loop

* Train arrives to the level from an outside connections
* Preplan the train route throughout the level
* Repeat:
  * Plan route to the next destination (level train station / different outbound connection)
  * (Wait until route / part of the rout is clear)
  * Set route / part of the rout
  * Dispatch the train
  * Wait until it arrives to the desired destination
* Train leaves the level

### Additional notes

* Ideally, we'll have a score system, so players can compare how efficiently they finished the level between each other

---

## Mechanics

*TODO*

---

## Level Structure

Each level has:

* Unique rail network layout
* [Goal and bonus goal](#goals) (success condition, e.g., dispatch x trains) 
* Optional [fail condition](#fail-conditions) (e.g., accumulated delay must stay bellow x minutes)
* Optional [restrictions](#restrictions) (e.g., electric trains and only partially electrized network)

### Layout

* Train routes with switches and signals
* Outgoing routes - place where trains enter/leave the current level
* Train stations - may differ for personal and freight trains
* Visual "fill" - hills, roads, houses, factories, tunnels, bridges... 

### Goals

*TODO: Think of primary and secondary goals.*

### Fail Conditions

* Train collision (if this is allowed to happen)

*TODO: Think of other possible fail conditions.*

### Restrictions

*TODO: Think of possible restrictions.*

### Level Progression

*TODO*

---

## Visuals

*TODO: expand this section*

Stylized and simplified 3D that looks like a model railroad.

---

## Story

*TODO*

---

# Naming Conventions

This section defines the core terminology used in the game.

## Track Infrastructure

### Turnout

The full assembly where one track diverges from another.

* Neutral/technical term: **Turnout**
* US term: **Switch**
* UK term: **Points**

**Code:** connection of exactly 2 splines through which the train passes.


### Turnout Positions

Each turnout has two possible positions:

* **Normal**
  The designated default position.
  In most cases aligned with the **main (through) route**.

* **Reverse**
  The diverging alignment.

**Code:** normal == the train stays on the same spline; reverse == the train switches splines.

---

## Routes

* **Main Route** (or Through Route)
  The primary track alignment.
  **Code:** a single spline.

* **Diverging Route**
  The branch path leaving the main track.
  **Code:** a spline which's end lie on another route.

---

## Signaling

### Signal Aspects

* **Clear** → proceed (green)
* **Danger** → stop (red)

---

## Blocks

A track section that can only contain one train at a time.

---

## Safety Logic


### Interlocking

The automatic system that prevents conflicting movements.

Interlocking ensures:

* No two conflicting routes can be set simultaneously
* No two signals can clear into the same block
* Switches cannot be moved under an approaching train
* Signals return to danger after a train passes

Signal returning to red after passage can be described as:

* **Automatic signal replacement**

---

## Player Role Naming

Recommended primary role:

### Dispatcher

Why:

* Scales from small layouts to large networks
* Works for both local and wide-area control
* Clear and intuitive for players

Alternative early-game flavor:

* Signalman (traditional)
* Signaller (modern, gender-neutral)

Recommended final title:
**Railway Dispatcher**

---

# Gameplay Structure

## Core Gameplay

The player must:

* Set turnout positions (Normal / Reverse)
* Set signal aspects (Clear / Danger)
* Prevent collisions
* Route trains efficiently

The game automatically:

* Prevents conflicting routes
* Prevents two trains entering the same block
* Returns signals to danger after train passage
* Locks routes while a train is approaching

This creates manual control with realistic safety enforcement.

---

## Progression Concept

### Early Game – Local Control

* Small layout
* Manual switch and signal setting
* Basic block enforcement

Player feels like a local signaller.

---

### Mid Game – Interlocked Control

* Larger stations
* Automatic conflict prevention
* Route locking
* More simultaneous trains

Player grows into a dispatcher role.

---

### Late Game – Route-Based Control

* Player sets complete routes instead of individual switches
* Turnouts align automatically along selected path
* Still manual decision-making, not full automation

Represents evolution from mechanical signaling to panel/relay control.

---

# Ideas Section

## Upgrade Path Concept

The player role can evolve:

* Junior Signalman
* Senior Signaller
* Dispatcher
* Chief Dispatcher

Upgrades may unlock:

* Faster switch throw time
* Automated route locking
* Advanced interlocking
* Traffic prioritization tools
* Network overview panel

---

## Optional Realism Enhancements

Future features could include:

* Delayed switch movement time
* Train approach locking (switches cannot move when occupied)
* Different block systems (manual vs automatic)
* Timetable-based routing challenges
* Emergency override with penalties

---

## Design Philosophy

The goal is:

* Authentic terminology
* Intuitive gameplay
* Increasing strategic depth
* Realistic safety behavior without overwhelming micromanagement

Manual control remains central, but realistic interlocking ensures fairness and prevents frustration.

---

*End of Draft*
