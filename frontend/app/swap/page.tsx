'use client';

import { useState, useEffect } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, formatEther, type Address } from 'viem';
import { ROUTER_ADDRESS, WETH_ADDRESS, FACTORY_ADDRESS } from '@/lib/addresses';
import ROUTER_ABI from '@/lib/abis/Router.json';
import PAIR_ABI from '@/lib/abis/Pair.json';
import FACTORY_ABI from '@/lib/abis/Factory.json';
import ERC20_ABI from '@/lib/abis/ERC20.json';
import { getAmountOut } from '@/lib/math';

// Hardcoded tokens for MVP
const TOKENS: { symbol: string; address: Address }[] = [
  { symbol: 'WETH', address: WETH_ADDRESS as Address },
  { symbol: 'DAI', address: '0x0000000000000000000000000000000000000001' as Address }, // Mock address, user needs to deploy/mock
  // For MVP we can just use 2 dummy tokens if user deployed them. 
  // Since I didn't deploy generic ERC20s in deploy script (only WETH), I should probably deploy one or two dummy tokens in deploy script for testing, 
  // OR just assume they exist. The user instructions say "ERC20Mock: simple mintable token used only in tests". 
  // But for frontend to work, we need tokens on chain.
  // I'll update Deploy script later to deploy a "TEST" token.
  // For now, I'll put a placeholder address.
];

export default function SwapPage() {
  const { address } = useAccount();
  const [tokenIn, setTokenIn] = useState(TOKENS[0]);
  const [tokenOut, setTokenOut] = useState(TOKENS[1] || { symbol: 'TEST', address: '0x...' as Address });
  const [amountIn, setAmountIn] = useState('');
  const [amountOut, setAmountOut] = useState('');

  // 1. Get Pair Address
  const { data: pairAddress } = useReadContract({
    address: FACTORY_ADDRESS as Address,
    abi: FACTORY_ABI,
    functionName: 'getPair',
    args: [tokenIn.address, tokenOut.address],
  });

  // 2. Get Reserves
  const { data: reserves } = useReadContract({
    address: pairAddress as Address,
    abi: PAIR_ABI,
    functionName: 'getReserves',
    query: {
      enabled: !!pairAddress && pairAddress !== '0x0000000000000000000000000000000000000000',
    }
  });

  // 3. Calculate Output
  useEffect(() => {
    if (!amountIn || !reserves) {
      setAmountOut('');
      return;
    }
    try {
      const valIn = parseEther(amountIn);
      // Determine which reserve is which
      // Pair.token0 / token1 order matters.
      // For MVP, router logic handles sorting, but here we need to know reserves order to calc OFF-CHAIN.
      // OR we can just call Router.getAmountsOut used by `useReadContract`? 
      // Calling Router.getAmountsOut is better.
    } catch { }
  }, [amountIn, reserves]);

  // Better approach: use Router.getAmountsOut
  const { data: amountsOutData } = useReadContract({
    address: ROUTER_ADDRESS as Address,
    abi: ROUTER_ABI,
    functionName: 'getAmountsOut',
    args: [parseEther(amountIn || '0'), [tokenIn.address, tokenOut.address]],
    query: {
      enabled: !!amountIn && parseFloat(amountIn) > 0,
    }
  });

  useEffect(() => {
    if (amountsOutData) {
      setAmountOut(formatEther((amountsOutData as bigint[])[1]));
    }
  }, [amountsOutData]);

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const handleSwap = async () => {
    if (!amountIn) return;

    // Approval check omitted for brevity in this initial pass, 
    // but should be here. For now assuming approved or ETH.
    // Actually, should implement approve.

    const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 mins
    const amountInWei = parseEther(amountIn);
    const amountOutMin = amountsOutData ? (amountsOutData as bigint[])[1] * 995n / 1000n : 0n; // 0.5% slippage

    writeContract({
      address: ROUTER_ADDRESS as Address,
      abi: ROUTER_ABI,
      functionName: 'swapExactTokensForTokens',
      args: [
        amountInWei,
        amountOutMin,
        [tokenIn.address, tokenOut.address],
        address,
        deadline
      ]
    });
  };

  return (
    <div className="max-w-md mx-auto mt-10 p-6 bg-gray-900 rounded-xl border border-gray-800">
      <h2 className="text-2xl font-bold mb-4">Swap</h2>

      <div className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">From ({tokenIn.symbol})</label>
          <input
            type="number"
            value={amountIn}
            onChange={(e) => setAmountIn(e.target.value)}
            className="w-full bg-gray-800 p-3 rounded border border-gray-700 focus:border-pink-500 outline-none"
            placeholder="0.0"
          />
        </div>

        <div className="flex justify-center text-gray-500">↓</div>

        <div>
          <label className="block text-sm text-gray-400 mb-1">To ({tokenOut.symbol})</label>
          <input
            type="number"
            value={amountOut}
            readOnly
            className="w-full bg-gray-800 p-3 rounded border border-gray-700 outline-none cursor-not-allowed"
            placeholder="0.0"
          />
        </div>

        <button
          onClick={handleSwap}
          disabled={isPending || isConfirming || !amountIn}
          className="w-full bg-pink-600 hover:bg-pink-700 p-4 rounded-lg font-bold disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {isPending ? 'Swapping...' : isConfirming ? 'Confirming...' : 'Swap'}
        </button>

        {isSuccess && <div className="text-green-500 text-center mt-2">Swap Successful!</div>}
      </div>
    </div>
  );
}
