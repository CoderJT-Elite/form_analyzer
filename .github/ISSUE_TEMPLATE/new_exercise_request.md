---
name: New Exercise Request
about: Propose a new exercise for real-time form analysis
title: '[EXERCISE] '
labels: enhancement, exercise-heuristic
assignees: ''

---

## Exercise Overview
Provide a brief description of the exercise and why it should be added to the Form Analysis Engine.

## Anatomical Landmark Indices
List the specific ML Kit pose landmarks required to track this exercise.
- [ ] Landmark A (e.g., Left Hip - 23)
- [ ] Landmark B (e.g., Left Knee - 25)
- [ ] Landmark C (e.g., Left Ankle - 27)
*Include additional triads if the exercise requires tracking multiple joints.*

## Biomechanical Thresholds
Define the critical angles required for the state machine transitions. Please justify these numbers with biomechanical or coaching standards.
- **Starting Position Angle**: [e.g., > 160°]
- **Target Depth/Execution Angle**: [e.g., 70° - 90°]
- **Safety Violation Angle**: [e.g., < 70°]

## State Machine Transitions
Describe the expected flow of states for a single successful repetition.
1. `Idle` -> `...`
2. `...` -> `Target Reached`

## Additional Context
Add any other context, research papers, or safety guidelines relevant to this exercise.
