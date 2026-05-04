import '../runtime/morph_runtime.dart';
import '../types/morph_surface.dart';
import '../types/morph_types.dart';

/// Parity: [`HostClient`](packages/core/src/client/HostClient.ts).
final class HostClient {
  HostClient(this._rt, this.host);

  final MorphRuntime _rt;
  final HostConfig host;

  String get key => host.key;

  String? get defaultAuth => host.defaultAuth;

  Future<MorphResponse<T>> get<T>(String path, [HostRequestOptions? opts]) =>
      _rt.http.hostFetch<T>(
        host,
        path,
        method: 'GET',
        auth: opts?.auth,
        headers: opts?.headers,
        queryParams: opts?.queryParams,
        timeout: opts?.timeout,
        sign: opts?.sign ?? false,
        encrypted: opts?.encrypted ?? false,
      );

  Future<MorphResponse<T>> post<T>(String path, [Object? body, HostRequestOptions? opts]) =>
      _rt.http.hostFetch<T>(
        host,
        path,
        method: 'POST',
        body: body,
        auth: opts?.auth,
        headers: opts?.headers,
        queryParams: opts?.queryParams,
        timeout: opts?.timeout,
        sign: opts?.sign ?? false,
        encrypted: opts?.encrypted ?? false,
      );

  Future<MorphResponse<T>> put<T>(String path, [Object? body, HostRequestOptions? opts]) =>
      _rt.http.hostFetch<T>(
        host,
        path,
        method: 'PUT',
        body: body,
        auth: opts?.auth,
        headers: opts?.headers,
        queryParams: opts?.queryParams,
        timeout: opts?.timeout,
        sign: opts?.sign ?? false,
        encrypted: opts?.encrypted ?? false,
      );

  Future<MorphResponse<T>> patch<T>(String path, [Object? body, HostRequestOptions? opts]) =>
      _rt.http.hostFetch<T>(
        host,
        path,
        method: 'PATCH',
        body: body,
        auth: opts?.auth,
        headers: opts?.headers,
        queryParams: opts?.queryParams,
        timeout: opts?.timeout,
        sign: opts?.sign ?? false,
        encrypted: opts?.encrypted ?? false,
      );

  Future<MorphResponse<T>> delete<T>(String path, [HostRequestOptions? opts]) =>
      _rt.http.hostFetch<T>(
        host,
        path,
        method: 'DELETE',
        auth: opts?.auth,
        headers: opts?.headers,
        queryParams: opts?.queryParams,
        timeout: opts?.timeout,
        sign: opts?.sign ?? false,
        encrypted: opts?.encrypted ?? false,
      );

  Future<MorphResponse<T>> head<T>(String path, [HostRequestOptions? opts]) =>
      _rt.http.hostFetch<T>(
        host,
        path,
        method: 'HEAD',
        auth: opts?.auth,
        headers: opts?.headers,
        queryParams: opts?.queryParams,
        timeout: opts?.timeout,
        sign: opts?.sign ?? false,
        encrypted: opts?.encrypted ?? false,
      );

  Future<MorphResponse<T>> options<T>(String path, [HostRequestOptions? opts]) =>
      _rt.http.hostFetch<T>(
        host,
        path,
        method: 'OPTIONS',
        auth: opts?.auth,
        headers: opts?.headers,
        queryParams: opts?.queryParams,
        timeout: opts?.timeout,
        sign: opts?.sign ?? false,
        encrypted: opts?.encrypted ?? false,
      );

  Future<MorphResponse<T>> request<T>(HostFullRequestOptions opts) => _rt.http.hostFetch<T>(
        host,
        opts.path,
        method: opts.method,
        body: opts.body,
        auth: opts.auth,
        headers: opts.headers,
        queryParams: opts.queryParams,
        timeout: opts.timeout,
        sign: opts.sign ?? false,
        encrypted: opts.encrypted ?? false,
      );
}
