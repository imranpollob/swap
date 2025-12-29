'use client';

import { useState, useEffect } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, useBalance } from 'wagmi';
import { parseEther, formatEther, type Address } from 'viem';
import { ROUTER_ADDRESS, WETH_ADDRESS, FACTORY_ADDRESS, TKA_ADDRESS } from '@/lib/addresses';
import ROUTER_ABI from '@/lib/abis/Router.json';
import PAIR_ABI from '@/lib/abis/Pair.json';
import FACTORY_ABI from '@/lib/abis/Factory.json';
import ERC20_ABI from '@/lib/abis/ERC20.json';

export default function PoolPage() {
  const { address, isConnected } = useAccount();
  const [activeTab, setActiveTab] = useState<'add' | 'remove'>('add');
  const [amountETH, setAmountETH] = useState('');
  const [amountToken, setAmountToken] = useState('');
  const [removePercent, setRemovePercent] = useState(50);

  // Get ETH balance  
  const { data: ethBalance } = useBalance({ address });

  // Get TKA balance
  const { data: tkaBalance } = useReadContract({
    address: TKA_ADDRESS as Address,
    abi: ERC20_ABI as any,
    functionName: 'balanceOf',
    args: [address],
    query: { enabled: !!address }
  });

  // Get Pair Address
  const { data: pairAddress } = useReadContract({
    address: FACTORY_ADDRESS as Address,
    abi: FACTORY_ABI as any,
    functionName: 'getPair',
    args: [WETH_ADDRESS, TKA_ADDRESS],
  });

  // Get LP token balance
  const { data: lpBalance } = useReadContract({
    address: pairAddress as Address,
    abi: PAIR_ABI as any,
    functionName: 'balanceOf',
    args: [address],
    query: { enabled: !!pairAddress && pairAddress !== '0x0000000000000000000000000000000000000000' && !!address }
  });

  // Get reserves
  const { data: reserves } = useReadContract({
    address: pairAddress as Address,
    abi: PAIR_ABI as any,
    functionName: 'getReserves',
    query: { enabled: !!pairAddress && pairAddress !== '0x0000000000000000000000000000000000000000' }
  }) as { data: readonly [bigint, bigint, number] | undefined };

  // Get total supply
  const { data: totalSupply } = useReadContract({
    address: pairAddress as Address,
    abi: PAIR_ABI as any,
    functionName: 'totalSupply',
    query: { enabled: !!pairAddress && pairAddress !== '0x0000000000000000000000000000000000000000' }
  });

  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  // Calculate share of pool
  const poolShare = lpBalance && totalSupply
    ? (Number(lpBalance) / Number(totalSupply) * 100).toFixed(2)
    : '0';

  const handleAddLiquidityETH = () => {
    if (!amountETH || !amountToken || !address) return;
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 60 * 20);

    writeContract({
      address: ROUTER_ADDRESS as Address,
      abi: ROUTER_ABI as any,
      functionName: 'addLiquidityETH',
      args: [
        TKA_ADDRESS,
        parseEther(amountToken),
        0n, // amountTokenMin (0 for simplicity)
        0n, // amountETHMin
        address,
        deadline
      ],
      value: parseEther(amountETH),
    });
  };

  const handleRemoveLiquidityETH = () => {
    if (!lpBalance || !address) return;
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 60 * 20);
    const removeAmount = (BigInt(lpBalance as bigint) * BigInt(removePercent)) / 100n;

    writeContract({
      address: ROUTER_ADDRESS as Address,
      abi: ROUTER_ABI as any,
      functionName: 'removeLiquidityETH',
      args: [
        TKA_ADDRESS,
        removeAmount,
        0n, // amountTokenMin
        0n, // amountETHMin
        address,
        deadline
      ],
    });
  };

  const handleApproveLPToken = () => {
    if (!pairAddress) return;
    writeContract({
      address: pairAddress as Address,
      abi: ERC20_ABI as any,
      functionName: 'approve',
      args: [ROUTER_ADDRESS, BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')],
    });
  };

  const handleApproveToken = () => {
    writeContract({
      address: TKA_ADDRESS as Address,
      abi: ERC20_ABI as any,
      functionName: 'approve',
      args: [ROUTER_ADDRESS, BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')],
    });
  };

  return (
    <div className="max-w-lg mx-auto mt-10">
      {/* Tabs */}
      <div className="flex mb-4 bg-gray-800 rounded-xl p-1">
        <button
          onClick={() => setActiveTab('add')}
          className={`flex-1 py-2 rounded-lg font-medium transition-colors ${activeTab === 'add' ? 'bg-blue-600' : 'hover:bg-gray-700'
            }`}
        >
          Add Liquidity
        </button>
        <button
          onClick={() => setActiveTab('remove')}
          className={`flex-1 py-2 rounded-lg font-medium transition-colors ${activeTab === 'remove' ? 'bg-red-600' : 'hover:bg-gray-700'
            }`}
        >
          Remove Liquidity
        </button>
      </div>

      <div className="p-6 bg-gray-900 rounded-xl border border-gray-800">
        {activeTab === 'add' ? (
          <div className="space-y-4">
            <h2 className="text-xl font-bold mb-4">Add Liquidity (ETH + TKA)</h2>

            {/* ETH Input */}
            <div className="bg-gray-800 rounded-xl p-4">
              <div className="flex justify-between mb-2">
                <label className="text-sm text-gray-400">ETH Amount</label>
                <span className="text-sm text-gray-400">
                  Balance: {ethBalance ? parseFloat(formatEther(ethBalance.value)).toFixed(4) : '0'} ETH
                </span>
              </div>
              <input
                type="number"
                value={amountETH}
                onChange={e => setAmountETH(e.target.value)}
                className="w-full bg-transparent text-2xl font-medium outline-none"
                placeholder="0.0"
              />
            </div>

            {/* Token Input */}
            <div className="bg-gray-800 rounded-xl p-4">
              <div className="flex justify-between mb-2">
                <label className="text-sm text-gray-400">TKA Amount</label>
                <span className="text-sm text-gray-400">
                  Balance: {tkaBalance ? parseFloat(formatEther(tkaBalance as bigint)).toFixed(4) : '0'} TKA
                </span>
              </div>
              <input
                type="number"
                value={amountToken}
                onChange={e => setAmountToken(e.target.value)}
                className="w-full bg-transparent text-2xl font-medium outline-none"
                placeholder="0.0"
              />
            </div>

            <div className="flex gap-2">
              <button
                onClick={handleApproveToken}
                disabled={isPending || isConfirming}
                className="flex-1 bg-gray-700 hover:bg-gray-600 p-3 rounded-xl font-medium disabled:opacity-50"
              >
                Approve TKA
              </button>
              <button
                onClick={handleAddLiquidityETH}
                disabled={isPending || isConfirming || !amountETH || !amountToken || !isConnected}
                className="flex-1 bg-blue-600 hover:bg-blue-700 p-3 rounded-xl font-bold disabled:opacity-50"
              >
                {isPending ? 'Confirming...' : isConfirming ? 'Adding...' : 'Add Liquidity'}
              </button>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            <h2 className="text-xl font-bold mb-4">Remove Liquidity</h2>

            <div className="bg-gray-800 rounded-xl p-4">
              <label className="block text-sm text-gray-400 mb-4">Amount to Remove</label>
              <div className="text-4xl font-bold text-center mb-4">{removePercent}%</div>
              <input
                type="range"
                min="0"
                max="100"
                value={removePercent}
                onChange={e => setRemovePercent(parseInt(e.target.value))}
                className="w-full"
              />
              <div className="flex justify-between mt-2">
                {[25, 50, 75, 100].map(val => (
                  <button
                    key={val}
                    onClick={() => setRemovePercent(val)}
                    className={`px-3 py-1 rounded ${removePercent === val ? 'bg-red-600' : 'bg-gray-700'}`}
                  >
                    {val}%
                  </button>
                ))}
              </div>
            </div>

            <div className="bg-gray-800 rounded-xl p-4">
              <div className="text-sm text-gray-400">Your LP Tokens</div>
              <div className="text-xl font-medium">
                {lpBalance ? parseFloat(formatEther(lpBalance as bigint)).toFixed(6) : '0'} LP
              </div>
            </div>

            <div className="flex gap-2">
              <button
                onClick={handleApproveLPToken}
                disabled={isPending || isConfirming}
                className="flex-1 bg-gray-700 hover:bg-gray-600 p-3 rounded-xl font-medium disabled:opacity-50"
              >
                Approve LP
              </button>
              <button
                onClick={handleRemoveLiquidityETH}
                disabled={isPending || isConfirming || !lpBalance || removePercent === 0 || !isConnected}
                className="flex-1 bg-red-600 hover:bg-red-700 p-3 rounded-xl font-bold disabled:opacity-50"
              >
                {isPending ? 'Confirming...' : isConfirming ? 'Removing...' : 'Remove Liquidity'}
              </button>
            </div>
          </div>
        )}

        {/* Status messages */}
        {isSuccess && (
          <div className="mt-4 p-3 bg-green-900/50 border border-green-500 rounded-lg text-green-400 text-center">
            ✓ Transaction Successful!
          </div>
        )}
        {error && (
          <div className="mt-4 p-3 bg-red-900/50 border border-red-500 rounded-lg text-red-400 text-sm">
            Error: {error.message.slice(0, 100)}...
          </div>
        )}
      </div>

      {/* Pool Info */}
      {Boolean(pairAddress) && (pairAddress as string) !== '0x0000000000000000000000000000000000000000' && (
        <div className="mt-6 p-6 bg-gray-900 rounded-xl border border-gray-800">
          <h3 className="text-lg font-bold mb-4">Your Position</h3>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-gray-400">Pair Address</span>
              <span className="font-mono">{(pairAddress as string).slice(0, 10)}...</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Your LP Tokens</span>
              <span>{lpBalance ? parseFloat(formatEther(lpBalance as bigint)).toFixed(6) : '0'}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-400">Pool Share</span>
              <span>{poolShare}%</span>
            </div>
            {reserves && (
              <>
                <div className="flex justify-between">
                  <span className="text-gray-400">Pool WETH</span>
                  <span>{formatEther((reserves as [bigint, bigint, number])[0])}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Pool TKA</span>
                  <span>{formatEther((reserves as [bigint, bigint, number])[1])}</span>
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
