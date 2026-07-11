// @trace FEAT-20260705-000000-0006
// Description: Pure goal-progress calculations shared by project and daily goals.

/// Returns the raw (unclamped) progress ratio of [current] towards [goal].
///
/// Unset or non-positive goals yield 0.0. Values above 1.0 indicate the goal
/// has been exceeded; callers that render a bar should clamp to [0, 1].
double goalProgress(int current, int? goal) {
  if (goal == null || goal <= 0) return 0.0;
  return current / goal;
}

/// Whether [current] has reached or surpassed a set [goal].
bool goalMet(int current, int? goal) {
  return goal != null && goal > 0 && current >= goal;
}
