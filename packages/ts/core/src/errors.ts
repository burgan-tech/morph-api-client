export class ConfigValidationError extends Error {
  readonly name = 'ConfigValidationError';
  constructor(public readonly errors: string[]) {
    super(errors.join('; '));
  }
}

export class UnknownHostError extends Error {
  readonly name = 'UnknownHostError';
  constructor(public readonly key: string) {
    super(`Unknown host: ${key}`);
  }
}

export class UnknownProviderError extends Error {
  readonly name = 'UnknownProviderError';
  constructor(public readonly key: string) {
    super(`Unknown provider: ${key}`);
  }
}

export class UnknownContextError extends Error {
  readonly name = 'UnknownContextError';
  constructor(public readonly authId: string) {
    super(`Unknown auth: ${authId}`);
  }
}

export class InvalidAuthForHostError extends Error {
  readonly name = 'InvalidAuthForHostError';
  constructor(
    public readonly hostKey: string,
    public readonly authId: string,
    public readonly allowedAuth: string[],
  ) {
    super(`Auth ${authId} is not allowed for host ${hostKey}`);
  }
}

export class AuthError extends Error {
  readonly name = 'AuthError';
  constructor(
    public readonly authId: string,
    public readonly reason: 'no_token' | 'refresh_failed' | 'delegation_required' | 'exchange_failed',
    message?: string,
  ) {
    super(message ?? reason);
  }
}

export class TokenEndpointError extends Error {
  readonly name = 'TokenEndpointError';
  constructor(
    public readonly statusCode: number,
    public readonly responseText: string,
  ) {
    super(`Token endpoint failed: ${statusCode} ${responseText}`);
  }
}

export class MorphHttpError extends Error {
  readonly name = 'MorphHttpError';
  constructor(
    public readonly statusCode: number,
    public readonly path: string,
    public readonly body: unknown,
    public readonly resolvedAuth?: string,
  ) {
    super(`HTTP ${statusCode} for ${path}`);
  }
}
