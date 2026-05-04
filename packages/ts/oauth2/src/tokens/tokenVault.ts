import type { AuthContextConfig, ProviderConfig, StorageConfig, TokenSet } from '@morph/core';
import { getJwtSubject } from '@morph/core';
import { interpolateString } from '../util/interpolate.js';

export interface PathManifest {
  accessKey: string;
  refreshKey?: string;
}

function manifestStorageConfig(accessStorage: StorageConfig, authId: string): StorageConfig {
  return {
    ...accessStorage,
    key: `morph:paths:${authId.replace(/\//g, '.')}`,
  };
}

function interpolateStorageKey(
  template: string,
  variables: Record<string, string>,
  extras: Record<string, string>,
): string {
  return interpolateString(template, variables, extras);
}

export class TokenVault {
  constructor(
    private readonly variables: Record<string, string>,
    private readonly storage: {
      read(key: string, cfg: StorageConfig): Promise<string | null>;
      write(key: string, value: string, cfg: StorageConfig): Promise<void>;
      delete(key: string, cfg: StorageConfig): Promise<void>;
    },
  ) {}

  private tokenStorageCfg(ctx: AuthContextConfig, kind: 'access' | 'refresh'): StorageConfig {
    const t = ctx.tokenTypes[kind];
    if (!t) throw new Error(`Missing tokenTypes.${kind} for context ${ctx.key}`);
    return t.storage;
  }

  private async readManifest(authId: string, ctx: AuthContextConfig): Promise<PathManifest | null> {
    const acc = this.tokenStorageCfg(ctx, 'access');
    const mcfg = manifestStorageConfig(acc, authId);
    const raw = await this.storage.read(mcfg.key, mcfg);
    if (!raw) return null;
    try {
      return JSON.parse(raw) as PathManifest;
    } catch {
      return null;
    }
  }

  private async writeManifest(authId: string, ctx: AuthContextConfig, m: PathManifest): Promise<void> {
    const acc = this.tokenStorageCfg(ctx, 'access');
    const mcfg = manifestStorageConfig(acc, authId);
    await this.storage.write(mcfg.key, JSON.stringify(m), mcfg);
  }

  private async deleteManifest(authId: string, ctx: AuthContextConfig): Promise<void> {
    const acc = this.tokenStorageCfg(ctx, 'access');
    const mcfg = manifestStorageConfig(acc, authId);
    await this.storage.delete(mcfg.key, mcfg);
  }

  private extrasForKeys(ctx: AuthContextConfig, accessToken?: string): Record<string, string> {
    const subClaim = ctx.identity?.subject ?? 'sub';
    const actClaim = ctx.identity?.actor ?? 'act';
    const subject = accessToken ? getJwtSubject(accessToken, subClaim) ?? 'unknown' : 'unknown';
    const actor = accessToken ? getJwtSubject(accessToken, actClaim) ?? subject : subject;
    return {
      key: ctx.key,
      subject,
      actor,
    };
  }

  async load(authId: string, _provider: ProviderConfig, ctx: AuthContextConfig): Promise<TokenSet | null> {
    const manifest = await this.readManifest(authId, ctx);
    if (!manifest) return null;
    const accCfg = { ...this.tokenStorageCfg(ctx, 'access'), key: manifest.accessKey };
    const rawAccess = await this.storage.read(manifest.accessKey, accCfg);
    if (!rawAccess) return null;
    let refreshToken: string | undefined;
    if (manifest.refreshKey && ctx.tokenTypes.refresh) {
      const refCfg = { ...this.tokenStorageCfg(ctx, 'refresh'), key: manifest.refreshKey };
      refreshToken = (await this.storage.read(manifest.refreshKey, refCfg)) ?? undefined;
    }
    try {
      const parsed = JSON.parse(rawAccess) as TokenSet;
      if (refreshToken) parsed.refreshToken = refreshToken;
      return parsed;
    } catch {
      return null;
    }
  }

  async save(authId: string, _provider: ProviderConfig, ctx: AuthContextConfig, tokens: TokenSet): Promise<void> {
    const extras = this.extrasForKeys(ctx, tokens.accessToken);
    const accessTemplate = ctx.tokenTypes.access.storage.key;
    const accessKey = interpolateStorageKey(accessTemplate, this.variables, extras);

    let refreshKey: string | undefined;
    if (tokens.refreshToken && ctx.tokenTypes.refresh) {
      const rt = ctx.tokenTypes.refresh.storage.key;
      refreshKey = interpolateStorageKey(rt, this.variables, extras);
    }

    const accessCfg = { ...this.tokenStorageCfg(ctx, 'access'), key: accessKey };
    const blob: TokenSet = {
      accessToken: tokens.accessToken,
      expiresAt: tokens.expiresAt,
      metadata: tokens.metadata,
    };
    await this.storage.write(accessKey, JSON.stringify(blob), accessCfg);

    if (refreshKey && tokens.refreshToken && ctx.tokenTypes.refresh) {
      const refCfg = { ...this.tokenStorageCfg(ctx, 'refresh'), key: refreshKey };
      await this.storage.write(refreshKey, tokens.refreshToken, refCfg);
    }

    await this.writeManifest(authId, ctx, {
      accessKey,
      refreshKey,
    });
  }

  async clear(authId: string, _provider: ProviderConfig, ctx: AuthContextConfig): Promise<void> {
    const manifest = await this.readManifest(authId, ctx);
    if (manifest) {
      const accCfg = { ...this.tokenStorageCfg(ctx, 'access'), key: manifest.accessKey };
      await this.storage.delete(manifest.accessKey, accCfg);
      if (manifest.refreshKey && ctx.tokenTypes.refresh) {
        const refCfg = { ...this.tokenStorageCfg(ctx, 'refresh'), key: manifest.refreshKey };
        await this.storage.delete(manifest.refreshKey, refCfg);
      }
    }
    await this.deleteManifest(authId, ctx);
  }
}
