# Operational Directive: GSD + UI/UX Pro Max + SkillX

All development, debugging, and enhancements in this repository strictly adhere to the integrated triad of:
1. **GSD (Get Shit Done)** — Spec-driven, high-velocity execution & context engineering.
2. **UI/UX Pro Max** — Professional mobile design intelligence, design system rigor & flawless UX polish.
3. **SkillX** — Hierarchical skill execution (Strategic -> Functional -> Atomic) with continuous feedback distillation.

---

## 1. GSD Execution Engine (Get Shit Done)
* **Spec Before Code**: Never vibe-code. For non-trivial modifications, define the target state, edge cases, and verification criteria first.
* **Context Engineering**: Keep context clean and high-signal. Avoid dumping bloated logs or repetitive file outputs. Focus on exact diffs and targeted queries.
* **Atomic Step Verification**: Run static analysis (`flutter analyze`), unit tests (`flutter test`), and build checks on every logical change. 
* **Zero Fluff**: Deliver concise, actionable updates. Avoid redundant explanations when code and tests speak for themselves.

---

## 2. UI/UX Pro Max Engine
* **Design System First**: Maintain strict color harmony (Material 3 tonal palettes), consistent typography scale, and 8pt/4pt grid alignment.
* **Mobile-First Ergonomics**:
  - Full edge-to-edge compliance with explicit safe-area handling (`SafeArea`, bottom gesture nav bars, dynamic status bars).
  - Touch targets minimum 48x48dp for all interactive elements.
  - Responsive layouts that gracefully accommodate all device aspect ratios and font scaling.
* **Zero Visual Glitches**: No clipped texts, no colliding bottom sheets, no abrupt state pops, and smooth loading/shimmer indicators for network states.
* **Tactile Feedback**: Ensure interactive components have visual feedback (ripple, subtle elevation, or active state tints).

---

## 3. SkillX Execution & Knowledge Distillation
* **Three-Tier Execution Architecture**:
  1. *Strategic Layer*: Architectural soundness, concurrency, anti-bot resilience, and stream durability.
  2. *Functional Layer*: Modular services (Audio playback, stream resolution, local proxy, cache management, in-app updates).
  3. *Atomic Layer*: Clean, type-safe Dart/Kotlin code, atomic git commits, zero regression.
* **Iterative Environment Feedback**: Instantly diagnose compiler, analyzer, and runtime logs. Never repeat a failed approach; synthesize feedback into immediate solutions.
* **Continuous Knowledge Retention**: Institutionalize successful architectural and UX fixes into project documentation and tests.
