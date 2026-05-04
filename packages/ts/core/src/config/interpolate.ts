/**
 * Replaces `$variable` tokens in a string using the provided map (and optional extras).
 */
export function interpolateString(
  template: string,
  variables: Record<string, string>,
  extras?: Record<string, string>,
): string {
  const map = { ...variables, ...extras };
  return template.replace(/\$([a-zA-Z_][a-zA-Z0-9_]*)/g, (_, name: string) => {
    const v = map[name];
    if (v === undefined) throw new Error(`Missing variable: $${name} in "${template}"`);
    return v;
  });
}

export function interpolateRecord(
  record: Record<string, string> | undefined,
  variables: Record<string, string>,
  extras?: Record<string, string>,
): Record<string, string> | undefined {
  if (!record) return undefined;
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(record)) {
    out[k] = interpolateString(v, variables, extras);
  }
  return out;
}
