const UNIT_MS: Record<string, number> = {
  ms: 1,
  s: 1000,
  m: 60_000,
  h: 3_600_000,
  d: 86_400_000,
};

/**
 * Parses strings like "200ms", "10s", "5m", "30d" into milliseconds.
 */
export function parseDurationMs(input: string | undefined, fallbackMs?: number): number {
  if (input === undefined || input === '') {
    if (fallbackMs !== undefined) return fallbackMs;
    throw new Error('Missing duration');
  }
  const m = String(input).trim().match(/^(\d+(?:\.\d+)?)(ms|s|m|h|d)$/i);
  if (!m) throw new Error(`Invalid duration: ${input}`);
  const n = Number(m[1]);
  const u = m[2].toLowerCase();
  const mult = UNIT_MS[u];
  if (mult === undefined) throw new Error(`Invalid duration unit: ${input}`);
  return Math.round(n * mult);
}
