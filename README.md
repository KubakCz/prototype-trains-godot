# Railway Control Game Prototype

Your attention please: The 09:42 service to Ockley is 120 minutes late. This is due to a total lack of control by the player.

## Overview

*Note: This is full gdd. Checkout [prototype goals](prototype_goals.md) for prototype goals.*

This project is a mid-scale railway control and routing game inspired mainly by Locomania 2 game.

As a Railroad Dispatcher, your objective is to guide a constant stream of traffic to their destinations safely (and ideally on schedule). You start simply: managing a few manual switches for slow-moving passenger trains. However, as the network expands, the complexity scales. You will eventually manage high-speed corridors and sprawling freight yards where every second counts. Thankfully, the interlocking system is there to prevent disaster... usually.

**The focus is on:**

* Manual control - direct interaction with switches and signals, backed by "realistic-ish" safety safeguards to prevent head-on collisions.
* Progressive difficulty - as the network expands and traffic density increases, the difficulty increases as well.
* Efficiency under pressure - optimize the flow to minimize delays and remember that the shortest path for one train might not be optimal for the whole network.

**Target audience:**

* Players of "train" games (Transpor Tycoon games, Train-puzzle games)
* Railway enthusiasts

**Competition:**

*TODO*

## Gameplay

The game is split between individual levels. Each level comes with a predefined railroad layout, and player must guide trains throughout the level.

The interaction with trains is non-direct - trains are controlled by interaction with signals and switches. The objective for each level might be slightly different, but it always forces player to dispatch trains as fast and as efficiently as possible. As player progresses throughout the levels, they get larger, more complex, and with more trains.

The player must:

* Set turnout positions by clicking them
* Set signal aspects by clicking them
* Route trains efficiently to their destination

The game automatically:

* Prevents two trains entering the same block (no collisions possible)
* Returns signals to danger after train passage
* Locks nearby signals and turnouts while a train is approaching

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

### Score System

* Ideally, we'll have a score system, so players can compare how efficiently they finished the level between each other
* *TODO think more about how this should work*

## Mechanics

*TODO*

## Level Structure

Each level has:

* Unique rail network layout
* [Goal and bonus goal](#goals) (success condition, e.g., dispatch x trains) 
* Optional [fail condition](#fail-conditions) (e.g., accumulated delay must stay bellow x minutes)
* Optional [restrictions](#restrictions) (e.g., electric trains and only partially electrified network)

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

#### Early Game – Local Control

* Small layout
* Manual switch and signal setting
* Basic block enforcement

Player feels like a local signaller.

#### Mid Game – Interlocked Control

* Larger maps
* More simultaneous trains
* Route locking
  * Plan a route through multiple blocks by clicking a sequence of signals and turnouts
  * Whole route gets locked, so player doesn't accidentally block a train when planning a second route

Player grows into a dispatcher role.

#### Late Game – Route-Based Control

* Large map with lot of trains
* Player sets complete routes instead of individual switches
  * Player creates waypoints for a train
  * Signals automatically change to green in front of a train
  * Turnouts align automatically along selected path
* Still manual decision-making, not full automation

Represents evolution from mechanical signaling to panel/relay control.

## Visuals

*TODO: expand this section*

Stylized and simplified 3D that looks like a model railroad.

## Story

*TODO*

## Ideas Section

* Delayed switch movement time
* Different block systems (manual vs automatic)
* Timetable-based routing challenges
* Emergency override with penalties