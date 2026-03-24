/** Normalize IPv6 loopback origins (e.g. `http://[::1]:5173`) to `http://localhost:PORT`. */
export function normalizeLoopbackOrigin(origin: string): string {
  try {
    const u = new URL(origin);
    const h = u.hostname;
    const ipv6 = h === '::1' || h === '[::1]' || h.toLowerCase() === '::ffff:127.0.0.1';
    if (ipv6) {
      const port = u.port || (u.protocol === 'https:' ? '443' : '80');
      return `${u.protocol}//localhost:${port}`;
    }
  } catch {
    /* ignore */
  }
  return origin;
}
