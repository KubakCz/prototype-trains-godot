# Prototype Goals

Plan of prototype implementation.

## 1. Curves and Trains

* Explore curve implementations for godot. If none would work for this project, implement own curves. Requirements:
  * easy to edit in editor
  * snappable to surface
  * must be usable as "rails" (objects following rails with specified speed)
* Curves will be our rails
* Create a simple train
  * Just a box, that follows the curve and has constant speed
  * It has to be able to travel on the curve in both directions - this means that direction (or speed) of the train can be different than direction of the followed curve - the train has front side and if it goas forward, it must go forward independently of the direction of the underlying curve.

## 2. Turnouts

* We need to connect multiple curves together with turnouts
* Turnout has two positions - normal and reverse
* Turnout connects two rails together
  * It lives on main rail - is somewhere along it and the rail goes straight through it
  * Connects main rail to secondary rail - it goes to the left or right, depending how the curve points are positioned 
* We need also direction - if the split is from curve start direction or curve end direction
* Train has to follow the turnout setup
  * If it goes from the right direction, it can get through and continue along the next part of the curve (either still on main or switched to secondary)
  * If it would go from unconnected direction (e.g. we are coming from the second direction of main and the switch is in reverse position) it has to stop and wait for the correct position
* Switch has to be operable from withing game - clicking it switches the position
* We have to have a simple debug UI layout over the switch, which clearly shows the connected tracks
* We have to have some way of setting this all up in the editor
* It must be possible to connect the turnouts into more complex setups, this will be implemented later in step 4

## 3. Signals

* Lives along the rail similar to switch
* Can stop trains along the rail - green == go (clear signal), red == stop
* By default, all signals are set to stop
* They are one directional - they are on the right side when traveling across the rail. (this means that signal for stopping trains in both directions needs two signals, each on each side of the track)
* There should be simple physical model (couple of boxes)
* We have to have UI so the signal can be seen by the player from far a way and each direction
  * The UI should be big enough so the player can interact easily
  * It must be clear which direction the UI belongs to
  * When multiple signals are close to each other, the UI should shift so it doesn't overlap
  * When too far away, the UI should colapse to a point that uncolapses when mouse is over it
* The code must count on with extensions in steps 7 and 8

## 4. Compound Turnouts

* We already have simple turnout that can be made into any shape - straight track with divert, turnout on a curve, Y shaped turnout
* More complex turnouts can be made out of the simple turnout (they are multiple connected simple turnouts), but have a single control element for the player
  * 3 way turnout 
    * one track splits into 3
    * user interaction cycles the 3 positions
  * crossover
    * two parallel tracks connected with two simple turnouts allowing a train to switch the tracks in one direction
    * user interaction cycles between parallel or cross directions
  * double crossing / slip switch
    * two parallel tracks connected with four simple switches, allowing to switch tracks in both directions
    * basically two crossovers over each other, each for one direction (they form x crossing in the middle)
    * user interaction cycles between parallel or cross directions
  * crossing 
    * two tracks the cross each other
    * train is not allowed to switch tracks, there is no user interaction, but we need to track these crossings for logic introduced by later implementation steps

## 5. Simple editor

TODO

## 6. Rail models

* Meshes generated based on the curves
* Generated in reasonable big chunks so it is efficient to render (one bigger mesh better than 1000 small ones, but camera culling also makes a difference)
* Simple metal material for tracks and simple wood material for cross ties
* Must be easy to regenerate when modifying the curves manually, but shouldn't slow down the editor
* Width must match trains - use standard gage (1435mm) and adjust train models accordingly
* Rail going through the turnout must have correct gaps for train wheel to pass when going through it in any direction, cross ties must be adjusted until the tracks are really split away from each other
* Tracks might cross each other without a turnout (e.g. crossing in the middle of a double slip switch), again, there must be correct gaps in the rail mesh and reasonable cross ties

## 7. Trains with wagons and better physics

TODO


## 8. Block locking

WIP

* Connection of trains and signals together
* A block is a collection of one or more track segments directly connected to each other. Block is surrounded by signals from each reachable direction.
* Simply said - if two trains have a way of colliding with each other and there is no signal that would allow to stop them, they are in the same block. (this means the also crossing connects the tracks to one block even though the train cannot pass between the two tracks)
* If there is a train inside a block (any part of the train counts), the block is locked.
  * All signals into the block are automatically switched to stop
  * They cannot be switched to go until the block is again unlocked
  * Turnouts inside a locked block are locked as well
* Green signal into the block pre-locks it, so there cannot be two trains coming to the block at the same time
  * At any point, there can be only one green signal into the block
* Train cannot be let into a block if it will reach an unconnected turnout (reaching turnout from a direction that doesn't connect to another rail)
* Player interaction with this automatic locking is yet to be decided

## 9. Nicer editor

TODO
