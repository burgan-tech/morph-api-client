/**
 * Web browser simulation of mobile device/installation identity.
 *
 * Mobile model:
 *   - deviceId       → stable per physical device (localStorage)
 *   - installationId → per app install / browser session (sessionStorage)
 *
 * Pin values for CI / demos via VITE_DEVICE_ID and VITE_INSTALLATION_ID.
 */
export class WebSimIdentity {
  static readonly DEVICE_KEY = 'morph-poc:device-id';
  static readonly INSTALL_KEY = 'morph-poc:installation-id';

  static getDeviceId(): string {
    const fromEnv = (import.meta.env.VITE_DEVICE_ID as string | undefined)?.trim();
    if (fromEnv) return fromEnv;
    if (typeof localStorage === 'undefined') return 'poc-device-anon';
    try {
      let id = localStorage.getItem(WebSimIdentity.DEVICE_KEY);
      if (!id) {
        id = crypto.randomUUID();
        localStorage.setItem(WebSimIdentity.DEVICE_KEY, id);
      }
      return id;
    } catch {
      return `poc-device-${crypto.randomUUID()}`;
    }
  }

  static getInstallationId(): string {
    const fromEnv = (import.meta.env.VITE_INSTALLATION_ID as string | undefined)?.trim();
    if (fromEnv) return fromEnv;
    if (typeof sessionStorage === 'undefined') return 'poc-install-anon';
    try {
      let id = sessionStorage.getItem(WebSimIdentity.INSTALL_KEY);
      if (!id) {
        id = crypto.randomUUID();
        sessionStorage.setItem(WebSimIdentity.INSTALL_KEY, id);
      }
      return id;
    } catch {
      return `poc-install-${crypto.randomUUID()}`;
    }
  }
}
