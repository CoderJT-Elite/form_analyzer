# Contributing to Form Analyzer

Thank you for your interest in contributing to the Form Analyzer repository! We welcome contributions, especially those that improve our heuristic models for real-time form analysis.

## Biomechanical Standards for New Exercise Heuristics

When adding support for a new exercise, you must adhere to the following biomechanical standards to ensure our analysis remains rigorous and valid for professional and academic contexts:

1. **Anatomical Landmark Precision**:
   - All joint angles must be calculated using a 3D Vector Dot Product.
   - Reference established kinematics literature when defining joint angle thresholds for "good" vs. "bad" form.
   
2. **Phase Definition**:
   - Exercises must be broken down into clear biomechanical phases (e.g., Eccentric, Concentric, Isometric).
   - Define exact state machine transitions based on joint velocity and angle changes.

3. **Inference Considerations**:
   - Algorithms must be performant and not violate the 30 FPS target on mid-range hardware.
   - Any new processing logic must safely implement the **Asynchronous Processing Lock**.

4. **Testing**:
   - New heuristics must include robust unit tests testing the mathematical bounds and edge cases (e.g., zero vectors).
   - Ensure a complete mathematical explanation (using LaTeX) is added to the documentation for any novel calculations.

## Pull Request Process

1. Fork the repository and create your branch from `main`.
2. Ensure your code satisfies the biomechanical standards detailed above.
3. Issues must be opened before opening a pull request.
4. Update the README.md with any necessary technical math documentation.
5. Submit the pull request for review by the maintainers.
