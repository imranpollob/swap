import { http, createConfig } from 'wagmi';
import { foundry } from 'wagmi/chains';

export const wagmiConfig = createConfig({
  chains: [foundry],
  transports: {
    [foundry.id]: http(),
  },
});
