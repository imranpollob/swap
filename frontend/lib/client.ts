import { createPublicClient, createWalletClient, custom, http } from 'viem';
import { foundry } from 'viem/chains';

export const publicClient = createPublicClient({
  chain: foundry,
  transport: http(),
});

// We'll create walletClient inside components since it needs window.ethereum
