export function focus(selector) {
  document?.querySelector(selector)?.focus();
}

export function after_render(k) {
  return requestAnimationFrame(k);
}
