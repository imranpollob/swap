'use client';

import { useState } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, type Address } from 'viem'; // Removed formatEther as it is unused currently
import { ROUTER_ADDRESS, WETH_ADDRESS, FACTORY_ADDRESS } from '@/lib/addresses';
import ROUTER_ABI from '@/lib/abis/Router.json';
import PAIR_ABI from '@/lib/abis/Pair.json';
import FACTORY_ABI from '@/lib/abis/Factory.json';
import ERC20_ABI from '@/lib/abis/ERC20.json'; // unused but good to have

const TOKENS = [
  { symbol: 'WETH', address: WETH_ADDRESS as Address },
  { symbol: 'TKA', address: '0x0000000000000000000000000000000000000001' as Address }, // Mock placeholder
];

export default function PoolPage() {
  const { address } = useAccount();
  const [amountA, setAmountA] = useState('');
  const [amountB, setAmountB] = useState('');

  const tokenA = TOKENS[0];
  const tokenB = TOKENS[1];

  // Get Pair
  const { data: pairAddress } = useReadContract({
    address: FACTORY_ADDRESS as Address,
    abi: FACTORY_ABI,
    functionName: 'getPair',
    args: [tokenA.address, tokenB.address],
  });

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const handleAddLiquidity = () => {
    if (!amountA || !amountB) return;
    const deadline = Math.floor(Date.now() / 1000) + 60 * 20;

    // Approvals should differ for WETH vs Token, generally Approve Router.
    // For MVP assuming approval done or flow handled.
    // In real app, check allowance -> approve -> transaction.

    writeContract({
      address: ROUTER_ADDRESS as Address,
      abi: ROUTER_ABI,
      functionName: 'addLiquidity',
      args: [
        tokenA.address,
        tokenB.address,
        parseEther(amountA),
        parseEther(amountB),
        0n, // amountAMin (slippage 100% allowed for MVP test)
        0n, // amountBMin
        address,
        deadline
      ]
    });
  };

  return (
    <div className="max-w-md mx-auto mt-10 p-6 bg-gray-900 rounded-xl border border-gray-800">
      <h2 className="text-2xl font-bold mb-4">Add Liquidity</h2>

      <div className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">{tokenA.symbol}</label>
          <input
            type="number"
            value={amountA}
            onChange={e => setAmountA(e.target.value)}
            className="w-full bg-gray-800 p-3 rounded border border-gray-700 outline-none"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">{tokenB.symbol}</label>
          <input
            type="number"
            value={amountB}
            onChange={e => setAmountB(e.target.value)}
            className="w-full bg-gray-800 p-3 rounded border border-gray-700 outline-none"
          />
        </div>

        <button
          onClick={handleAddLiquidity}
          disabled={isPending || isConfirming || !amountA || !amountB}
          className="w-full bg-blue-600 hover:bg-blue-700 p-4 rounded-lg font-bold disabled:opacity-50"
        >
          {isPending ? 'Adding...' : isConfirming ? 'Confirming...' : 'Add Liquidity'}
        </button>

        {isSuccess && <div className="text-green-500 text-center">Liquidity Added!</div>}
      </div>

      {Boolean(pairAddress) && (pairAddress as string) !== '0x0000000000000000000000000000000000000000' && (
        <div className="mt-8 pt-4 border-t border-gray-700">
          <h3 className="text-lg font-bold">Your Position</h3>
          <p className="text-sm text-gray-400">Pair Address: {pairAddress as string}</p>
        </div>
      )}
    </div>
  );
}
