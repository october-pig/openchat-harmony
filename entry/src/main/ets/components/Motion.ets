export const CONTROL_MOTION: AnimateParam = { duration: 180, curve: Curve.EaseInOut };
export const PRESS_EFFECT: ClickEffect = { level: ClickEffectLevel.LIGHT, scale: 0.95 };

export function fadeMotion(): TransitionEffect {
  return TransitionEffect.opacity(0).animation(CONTROL_MOTION);
}

export function panelMotion(edge?: TransitionEdge): TransitionEffect {
  const appear: AnimateParam = { duration: 260, curve: Curve.EaseOut };
  const disappear: AnimateParam = { duration: 200, curve: Curve.EaseIn };
  if (edge !== undefined) {
    return TransitionEffect.asymmetric(
      TransitionEffect.move(edge).animation(appear),
      TransitionEffect.move(edge).animation(disappear)
    );
  }
  return TransitionEffect.asymmetric(
    TransitionEffect.scale({ x: 0.97, y: 0.97 }).combine(TransitionEffect.opacity(0)).animation(appear),
    TransitionEffect.scale({ x: 0.97, y: 0.97 }).combine(TransitionEffect.opacity(0)).animation(disappear)
  );
}
