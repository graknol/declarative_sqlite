/**
 * Storage initialization helpers
 * Utilities for preparing storage backends and requesting permissions
 */

import { StorageCapabilities, StorageBackend } from './persistence-config';

export interface StorageInitOptions {
  /**
   * Request persistent storage to prevent eviction
   * @default true
   */
  requestPersistence?: boolean;
  
  /**
   * Preferred backend (will fallback if not available)
   */
  preferredBackend?: StorageBackend;
  
  /**
   * Verbose logging for debugging
   * @default false
   */
  verbose?: boolean;
}

export interface StorageInitResult {
  /**
   * The backend that will be used
   */
  backend: StorageBackend;
  
  /**
   * Whether persistent storage was granted
   */
  isPersistent: boolean;
  
  /**
   * Storage quota information (if available)
   */
  quota?: {
    usage: number;
    quota: number;
    percentUsed: number;
  };
  
  /**
   * Any warnings or issues encountered
   */
  warnings: string[];
}

/**
 * Initialize storage and request necessary permissions
 * Call this before creating your database adapter
 * 
 * @example
 * ```typescript
 * import { initializeStorage, AdapterFactory } from 'declarative-sqlite';
 * 
 * // Initialize storage first
 * const result = await initializeStorage({
 *   requestPersistence: true,
 *   preferredBackend: StorageBackend.OPFS,
 *   verbose: true,
 * });
 * 
 * console.log('Using backend:', result.backend);
 * console.log('Persistent storage:', result.isPersistent);
 * 
 * // Then create adapter with the detected backend
 * const adapter = await AdapterFactory.create({
 *   backend: result.backend,
 *   name: 'myapp.db',
 * });
 * ```
 */
export async function initializeStorage(
  options: StorageInitOptions = {}
): Promise<StorageInitResult> {
  const {
    requestPersistence = true,
    preferredBackend,
    verbose = false,
  } = options;
  
  const warnings: string[] = [];
  const log = (message: string) => {
    if (verbose) {
      console.log(`[Storage Init] ${message}`);
    }
  };
  
  const warn = (message: string) => {
    warnings.push(message);
    if (verbose) {
      console.warn(`[Storage Init] ${message}`);
    }
  };
  
  log('Starting storage initialization...');
  
  // Request persistent storage if in browser
  let isPersistent = false;
  if (requestPersistence && typeof navigator !== 'undefined') {
    log('Requesting persistent storage...');
    isPersistent = await StorageCapabilities.requestPersistentStorage();
    if (isPersistent) {
      log('Persistent storage granted');
    } else {
      warn('Persistent storage not granted - data may be evicted under storage pressure');
    }
  }
  
  // Get storage quota information
  let quota: StorageInitResult['quota'] | undefined;
  const quotaInfo = await StorageCapabilities.getStorageQuota();
  if (quotaInfo) {
    const percentUsed = quotaInfo.quota > 0 
      ? (quotaInfo.usage / quotaInfo.quota) * 100 
      : 0;
    
    quota = {
      usage: quotaInfo.usage,
      quota: quotaInfo.quota,
      percentUsed,
    };
    
    log(`Storage: ${formatBytes(quotaInfo.usage)} / ${formatBytes(quotaInfo.quota)} (${percentUsed.toFixed(1)}%)`);
    
    if (percentUsed > 80) {
      warn('Storage is more than 80% full - consider cleaning up data');
    }
  }
  
  // Detect best backend
  let backend: StorageBackend;
  
  if (preferredBackend && preferredBackend !== StorageBackend.Auto) {
    log(`Checking preferred backend: ${preferredBackend}`);
    const isAvailable = await StorageCapabilities.isBackendAvailable(preferredBackend);
    
    if (isAvailable) {
      backend = preferredBackend;
      log(`Using preferred backend: ${backend}`);
    } else {
      warn(`Preferred backend '${preferredBackend}' is not available, falling back to auto-detection`);
      backend = await StorageCapabilities.detectBestBackend();
      log(`Auto-detected backend: ${backend}`);
    }
  } else {
    log('Auto-detecting best backend...');
    backend = await StorageCapabilities.detectBestBackend();
    log(`Detected backend: ${backend}`);
  }
  
  // Check specific backend capabilities
  if (backend === StorageBackend.OPFS) {
    log('OPFS is available');
  } else if (backend === StorageBackend.IndexedDB) {
    log('Using IndexedDB (OPFS not available)');
  } else if (backend === StorageBackend.Memory) {
    warn('No persistent storage available - using in-memory database (data will be lost on reload)');
  }
  
  log('Storage initialization complete');
  
  return {
    backend,
    isPersistent,
    quota,
    warnings,
  };
}

/**
 * Format bytes to human-readable string
 */
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  
  return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
}

/**
 * Check if storage is available and sufficient
 * 
 * @example
 * ```typescript
 * const available = await checkStorageAvailability(10 * 1024 * 1024); // 10MB
 * if (!available.hasSpace) {
 *   alert('Not enough storage space available');
 * }
 * ```
 */
export async function checkStorageAvailability(
  requiredBytes: number = 0
): Promise<{
  available: boolean;
  hasSpace: boolean;
  usage: number;
  quota: number;
  remaining: number;
}> {
  const quotaInfo = await StorageCapabilities.getStorageQuota();
  
  if (!quotaInfo) {
    // Can't determine quota, assume it's available
    return {
      available: true,
      hasSpace: true,
      usage: 0,
      quota: 0,
      remaining: 0,
    };
  }
  
  const remaining = quotaInfo.quota - quotaInfo.usage;
  const hasSpace = requiredBytes === 0 || remaining >= requiredBytes;
  
  return {
    available: true,
    hasSpace,
    usage: quotaInfo.usage,
    quota: quotaInfo.quota,
    remaining,
  };
}
