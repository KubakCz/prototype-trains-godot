# Prototype Goals

Plan of prototype implementation.

## 1. Curves and Trains *(done)*

* Explore curve implementations for godot. If none would work for this project, implement own curves. Requirements:
  * easy to edit in editor
  * snappable to surface
  * must be usable as "rails" (objects following rails with specified speed)
* Curves will be our rails
* Create a simple train
  * Just a box, that follows the curve and has constant speed
  * It has to be able to travel on the curve in both directions - this means that direction (or speed) of the train can be different than direction of the followed curve - the train has front side and if it goas forward, it must go forward independently of the direction of the underlying curve.

## 2. Turnouts *(done)*

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

## 3. Signals *(done)*

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

## 4. Compound Turnouts *(done)*

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
* Each compound turnout should have only a singular controlling element (be it text or schema). We are still keeping all the variants.

## 5. Trains with wagons and better physics *(done)*

* Train can have multiple wagons connected. The wagons follow it everywhere through turnouts.
* It takes time for the trains to stop and go. The acceleration/deceleration should be adjustable for different trains and should be also based on the length/content of the train (so full freight trains will take longer to get to speed and break longer). Still we are in a game, so the values should not be something crazy long.
* If signal is switched to stop in front of the train, the train passes it with breaks to 100% and will stop behind the stop signal as fast as possible. The train can be let go again at any point by player.
* If switch is turned under the train, the train should derail and stop.
* If two trains touch (any part of the train with any part of the other train), the trains derail and stop.
* Derailment is for now unrecoverable.
* Trains can be selected by clicking on them. This replaces selection by 'Tab'.
* Selected train has lighter blue color on the main view
* The "front marker" of the train (currently yellow box) will inform about the train state by changing color:
  * yellow - train stopped by player
  * green - train is going
  * red - train is breaking
  * blinking red - if train cannot stop in time on stop signal, blinks red until player doesn't let it go
  * black - train derailed

## 6. Meshes *(done)*

* Meshes for tracks are generated based on the curves.
* Generated in reasonable big chunks so it is efficient to render (one bigger mesh better than 1000 small ones, but camera culling also makes a difference)
* Simple metal material for tracks and simple wood material for cross ties
* Must be easy to regenerate when modifying the curves manually, but shouldn't slow down the editor
* Width must match trains - use standard gage (1435mm) and adjust train models accordingly
* Rail going through the turnout must have correct gaps for train wheel to pass when going through it in any direction, cross ties must be adjusted until the tracks are really split away from each other
* Tracks might cross each other without a turnout (e.g. crossing in the middle of a double slip switch), again, there must be correct gaps in the rail mesh and reasonable cross ties
* There is a layer of crushed stones under the rails that has trapezoidal crossection. This will smoothout track against uneaven terrain. The material should blend into the color of surrounding arrea (e.g. like if the stones were overgrowwing with grass).
* In some places it makes sense to create a bridge. Let's try to have different variants for the bridge - stone arch (arch bellow the bridge) and steel truss that have pillars if the span is too large, and wooden that have timber structure along the whole span of the bridge.
* Track might go under ground - in that case there is a tunnel opening made out of stones.

## 7. Spawnpoints and stations

* There are two types of interest points for trains - stations and outside connection points
* Each interest point has a distinct color and name; they are marked with a floating shape above (square for outside connections, circle for stations). Colors can be adjusted manually, but if you assign them, make them as distinct from each other as possible. If similar colors should be used, put them close to each other (e.g., a map with a south corridor can have entry, station, and exit with different tints of green). Allow toggling on and off the names as a debug option.
* An interest point can span several tracks (outside connection of two parallel tracks, train station with 4 tracks, train yards...)
* All interest points can serve as spawn points for trains when a map is loaded
* When a map is running, only outside connection points serve as spawn points for new trains
* Trains are spawned at random - each map can configure the maximum number of trains allowed to be present on a map at one time and minimum time between consecutive train spawns
* Each train has a route - set of interest points it has to go through
* Routes can contain 0, 1, or multiple train stations and always end on outside connection points
* Routes are randomly assigned from a predefined list - the list can be configured per train type and entry point (though one entry can be used for different entry points and train types) to make the routes a little bit realistic - i.e. passenger trains go through passenger stations in a reasonable order, freight trains stop at coal mines or factories...
* When a train passes through an assigned station, it stops automatically (even when the signal is set to clear) and waits a couple of seconds. Loadable carts can load/unload
* Engines are colored at random - either plain color or a color with a horizontal stripe (the stripe must have high enough contrast). Color options are limited to well-known colors (blue, yellow, green, pink, ...) to make them distinct and memorable. Avoid different shades of the same color.
* UI representation of the train route is not decided yet - implement two approaches that are switchable
  *   Colored icons above each train; the frontmost is the next one
  *   A list with trains and destinations - another panel like our debug menus, contains a list of trains in arrival order (one line = circle with corresponding train color + stripe, list of stations (option for only colored icons or colored icons with names for testing purposes))
 
## 8. Menu and game modes

* Point system - player receives one point per train reaching an interest point from its route list
* Game mode Endless - already present. Nothing stops you; just play forever
* Game mode Timed - get as many points in a set time
* Game mode Target Score - get a set amount of points as fast as possible
* Both time information and number of collected points are displayed next to each other in the middle-top of the screen.
* By default, when a map is opened from the editor, it starts in endless mode
* The game has a simple menu, which allows you to choose any existing map (contains "testing" subfolder) and any game mode - click on map, then select play mode

## 9. Block locking

* Connection of trains and signals together
* A block is a collection of one or more track segments directly connected to each other. The block starts and entds with a track end, unconnected turnout, or a signal.
* Simply said - if two trains have a way of colliding with each other and there is no signal that would allow to stop them, they are in the same block
* Switching turnouts can change the blocks - e.g. a double crossover can have two parallel blocks, or it can be switched to one block covering the whole turnout when the paths cross.
* If there is a train inside a block (any part of the train counts), the block is locked.
  * All signals into the block are automatically switched to stop
  * They cannot be switched to go until the block is again unlocked
  * Turnouts inside a locked block are locked as well
  * UI for signals and turnouts is overlaid with a lock icon
* Green signal into the block pre-locks it, so there cannot be two trains coming to the block at the same time
  * At any point, there can be only one green signal into the block. Clicking on another red signal will turn it green, but will turn the original green to red.
* A train cannot be let into a block if it will reach an unconnected turnout (reaching a turnout from a direction that doesn't connect to another rail) - the corresponding signal also shows a lock icon
* Blocks have visual representation - on mouse hover over signal or turnout UI, its block is highlighted - lines following rails drawn in purplish color

## 10. Simple editor

TODO

* Place a turnout by dragging its gizmo along the main rail, projecting onto the nearest point
  of the curve to set `main_distance` — step 2 deliberately kept placement numeric and left this
  here.
* Run **Align Branch To Turnout** as part of editing rather than as a manual button press.
