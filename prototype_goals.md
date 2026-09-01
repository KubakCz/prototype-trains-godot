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

## 3. Signals

* Lives along the rail similar to switch
* Can stop trains along the rail - green == go (clear signal), red == stop
* They are one directional - they are on the right side when traveling across the rail. (this means that signal stopping in both directions needs two signals, each on each side)
* There should be simple physical model (couple of boxes)
* We have to have UI so the signal can be seen by the player from far a way and each direction.
* todo

## 4. Rail models

## 5. Trains with wagons and better physics

## 6. Simple editor

## 7. Switch and signal locking

## 8. Block locking

## 9. Nicer editor