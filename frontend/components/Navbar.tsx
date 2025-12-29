'use client';

import Link from 'next/link';

export function Navbar() {
  return (
    <nav className="flex items-center justify-between p-4 bg-gray-900 text-white border-b border-gray-800">
      <div className="flex items-center gap-6">
        <h1 className="text-xl font-bold bg-gradient-to-r from-pink-500 to-purple-500 bg-clip-text text-transparent">
          MiniSwap v2
        </h1>
        <div className="flex gap-4">
          <Link href="/" className="hover:text-pink-400 transition-colors">
            Swap
          </Link>
          <Link href="/pool" className="hover:text-pink-400 transition-colors">
            Pool
          </Link>
          <Link href="/docs" className="hover:text-pink-400 transition-colors">
            Docs
          </Link>
        </div>
      </div>
      <div>
        <ConnectWallet />
      </div>
    </nav>
  );
}

import { useConnect, useAccount, useDisconnect } from 'wagmi';
import { useState, useEffect } from 'react';

function ConnectWallet() {
  const { connectors, connect } = useConnect();
  const { address, isConnected } = useAccount();
  const { disconnect } = useDisconnect();

  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) return null;

  if (isConnected) {
    return (
      <div className="flex items-center gap-2">
        <span className="text-sm font-mono">{address?.slice(0, 6)}...{address?.slice(-4)}</span>
        <button
          onClick={() => disconnect()}
          className="px-3 py-1 bg-red-600 hover:bg-red-700 rounded text-xs"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <div className="flex gap-2">
      {connectors.map((connector) => (
        <button
          key={connector.uid}
          onClick={() => connect({ connector })}
          className="px-3 py-1 bg-blue-600 hover:bg-blue-700 rounded text-sm"
        >
          {connector.name}
        </button>
      ))}
    </div>
  );
}
