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

## Routes

* **Main Route** (or Through Route)
  The primary track alignment.
  **Code:** a single spline.

* **Diverging Route**
  The branch path leaving the main track.
  **Code:** a spline which's end lie on another route.

## Signaling

### Signal Aspects

* **Clear** → proceed (green)
* **Danger** → stop (red)

## Blocks

A track section that can only contain one train at a time.

## Safety Logic

### Interlocking

The automatic system that prevents conflicting movements.

Interlocking ensures:

* No two conflicting routes can be set simultaneously
* No two signals can clear into the same block
* Switches cannot be moved under an approaching train
* Signals return to danger after a train passes

Signal returning to red after passage is called **Automatic signal replacement**

## Player Role Naming

* **Dispatcher** (at least for now)
* Signalman (traditional)
* Signaller (modern, gender-neutral)
