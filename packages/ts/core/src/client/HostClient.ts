import type { HostConfig, HostFullRequestOptions, HostRequestOptions, MorphResponse } from '../types.js';
import type { MorphRuntime } from '../runtime.js';

export class HostClient {
  constructor(
    private readonly rt: MorphRuntime,
    readonly host: HostConfig,
  ) {}

  get key(): string {
    return this.host.key;
  }

  get defaultAuth(): string | undefined {
    return this.host.defaultAuth;
  }

  get<T = unknown>(path: string, opts?: HostRequestOptions): Promise<MorphResponse<T>> {
    return this.rt.http.hostFetch<T>(this.host, path, { method: 'GET', ...opts });
  }

  post<T = unknown>(path: string, body?: unknown, opts?: HostRequestOptions): Promise<MorphResponse<T>> {
    return this.rt.http.hostFetch<T>(this.host, path, { method: 'POST', body: body as RequestInit['body'], ...opts });
  }

  put<T = unknown>(path: string, body?: unknown, opts?: HostRequestOptions): Promise<MorphResponse<T>> {
    return this.rt.http.hostFetch<T>(this.host, path, { method: 'PUT', body: body as RequestInit['body'], ...opts });
  }

  patch<T = unknown>(path: string, body?: unknown, opts?: HostRequestOptions): Promise<MorphResponse<T>> {
    return this.rt.http.hostFetch<T>(this.host, path, { method: 'PATCH', body: body as RequestInit['body'], ...opts });
  }

  delete<T = unknown>(path: string, opts?: HostRequestOptions): Promise<MorphResponse<T>> {
    return this.rt.http.hostFetch<T>(this.host, path, { method: 'DELETE', ...opts });
  }

  head<T = unknown>(path: string, opts?: HostRequestOptions): Promise<MorphResponse<T>> {
    return this.rt.http.hostFetch<T>(this.host, path, { method: 'HEAD', ...opts });
  }

  options<T = unknown>(path: string, opts?: HostRequestOptions): Promise<MorphResponse<T>> {
    return this.rt.http.hostFetch<T>(this.host, path, { method: 'OPTIONS', ...opts });
  }

  request<T = unknown>(opts: HostFullRequestOptions): Promise<MorphResponse<T>> {
    const { method, path, body, ...rest } = opts;
    return this.rt.http.hostFetch<T>(this.host, path, { method, body: body as RequestInit['body'], ...rest });
  }
}
