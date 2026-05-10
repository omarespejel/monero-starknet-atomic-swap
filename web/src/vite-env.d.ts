/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SWAP_API_BASE?: string;
  readonly VITE_SWAP_API_MODE?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
