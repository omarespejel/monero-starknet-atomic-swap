/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SWAP_API_BASE?: string;
  readonly VITE_SWAP_API_MODE?: string;
  readonly VITE_STARKNET_PRIVACY_POOL_ADDRESS?: string;
  readonly VITE_ATOMIC_SWAP_PRIVACY_HELPER_ADDRESS?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
