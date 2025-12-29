'use client';

import { useState, useEffect } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, useBalance, useConnect } from 'wagmi';
import { parseEther, formatEther, type Address } from 'viem';
import { ROUTER_ADDRESS, WETH_ADDRESS, FACTORY_ADDRESS, TKA_ADDRESS } from '@/lib/addresses';
import ROUTER_ABI from '@/lib/abis/Router.json';
import FACTORY_ABI from '@/lib/abis/Factory.json';
import ERC20_ABI from '@/lib/abis/ERC20.json';

// Token definitions with ETH as native
const TOKENS = [
  { symbol: 'ETH', address: 'native' as const, isNative: true },
  { symbol: 'WETH', address: WETH_ADDRESS as Address, isNative: false },
  { symbol: 'TKA', address: TKA_ADDRESS as Address, isNative: false },
];

type Token = typeof TOKENS[number];

export default function SwapPage() {
  const { address, isConnected } = useAccount();
  const { connectors, connect } = useConnect();
  const [tokenIn, setTokenIn] = useState<Token>(TOKENS[0]); // ETH
  const [tokenOut, setTokenOut] = useState<Token>(TOKENS[2]); // TKA
  const [amountIn, setAmountIn] = useState('');
  const [amountOut, setAmountOut] = useState('');
  const [slippage, setSlippage] = useState('0.5');
  const [showSettings, setShowSettings] = useState(false);

  // Get ETH balance
  const { data: ethBalance } = useBalance({
    address,
  });

  // Get token balances
  const { data: tokenInBalance } = useReadContract({
    address: tokenIn.isNative ? WETH_ADDRESS as Address : tokenIn.address as Address,
    abi: ERC20_ABI as any,
    functionName: 'balanceOf',
    args: [address],
    query: { enabled: !!address && !tokenIn.isNative }
  });

  const { data: tokenOutBalance } = useReadContract({
    address: tokenOut.isNative ? WETH_ADDRESS as Address : tokenOut.address as Address,
    abi: ERC20_ABI as any,
    functionName: 'balanceOf',
    args: [address],
    query: { enabled: !!address && !tokenOut.isNative }
  });

  // Determine path for Router (use WETH for ETH)
  const getPath = () => {
    const inAddr = tokenIn.isNative ? WETH_ADDRESS : tokenIn.address;
    const outAddr = tokenOut.isNative ? WETH_ADDRESS : tokenOut.address;
    return [inAddr, outAddr] as Address[];
  };

  // Get Amounts Out from Router
  const { data: amountsOutData } = useReadContract({
    address: ROUTER_ADDRESS as Address,
    abi: ROUTER_ABI as any,
    functionName: 'getAmountsOut',
    args: [parseEther(amountIn || '0'), getPath()],
    query: {
      enabled: !!amountIn && parseFloat(amountIn) > 0,
    }
  });

  useEffect(() => {
    if (amountsOutData) {
      setAmountOut(formatEther((amountsOutData as bigint[])[1]));
    } else {
      setAmountOut('');
    }
  }, [amountsOutData]);

  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const handleSwap = async () => {
    if (!isConnected) {
      // Auto-connect to the first available connector (usually Injected/MetaMask)
      const connector = connectors[0];
      if (connector) {
        connect({ connector });
      }
      return;
    }

    if (!amountIn || !address) return;

    const deadline = BigInt(Math.floor(Date.now() / 1000) + 60 * 20);
    const amountInWei = parseEther(amountIn);
    const slippageMultiplier = 1000n - BigInt(Math.floor(parseFloat(slippage) * 10));
    const amountOutMin = amountsOutData
      ? (amountsOutData as bigint[])[1] * slippageMultiplier / 1000n
      : 0n;

    const path = getPath();

    // Choose the right swap function based on tokens
    if (tokenIn.isNative && !tokenOut.isNative) {
      // ETH -> Token
      writeContract({
        address: ROUTER_ADDRESS as Address,
        abi: ROUTER_ABI as any,
        functionName: 'swapExactETHForTokens',
        args: [amountOutMin, path, address, deadline],
        value: amountInWei,
      });
    } else if (!tokenIn.isNative && tokenOut.isNative) {
      // Token -> ETH
      writeContract({
        address: ROUTER_ADDRESS as Address,
        abi: ROUTER_ABI as any,
        functionName: 'swapExactTokensForETH',
        args: [amountInWei, amountOutMin, path, address, deadline],
      });
    } else {
      // Token -> Token (including WETH)
      writeContract({
        address: ROUTER_ADDRESS as Address,
        abi: ROUTER_ABI as any,
        functionName: 'swapExactTokensForTokens',
        args: [amountInWei, amountOutMin, path, address, deadline],
      });
    }
  };

  const swapTokens = () => {
    const temp = tokenIn;
    setTokenIn(tokenOut);
    setTokenOut(temp);
    setAmountIn('');
    setAmountOut('');
  };

  const getBalance = (token: Token) => {
    if (token.isNative) {
      return ethBalance ? formatEther(ethBalance.value) : '0';
    }
    if (token.address === tokenIn.address && tokenInBalance) {
      return formatEther(tokenInBalance as bigint);
    }
    if (token.address === tokenOut.address && tokenOutBalance) {
      return formatEther(tokenOutBalance as bigint);
    }
    return '0';
  };

  const setMaxAmount = () => {
    const balance = getBalance(tokenIn);
    // Leave some ETH for gas if swapping ETH
    if (tokenIn.isNative) {
      const maxAmount = Math.max(0, parseFloat(balance) - 0.01);
      setAmountIn(maxAmount.toString());
    } else {
      setAmountIn(balance);
    }
  };

  return (
    <div className="max-w-md mx-auto mt-10">
      {/* Settings */}
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-2xl font-bold">Swap</h2>
        <button
          onClick={() => setShowSettings(!showSettings)}
          className="p-2 hover:bg-gray-800 rounded-lg transition-colors"
        >
          ⚙️
        </button>
      </div>

      {showSettings && (
        <div className="mb-4 p-4 bg-gray-800 rounded-xl border border-gray-700">
          <label className="block text-sm text-gray-400 mb-2">Slippage Tolerance</label>
          <div className="flex gap-2">
            {['0.1', '0.5', '1.0'].map(val => (
              <button
                key={val}
                onClick={() => setSlippage(val)}
                className={`px-3 py-1 rounded ${slippage === val ? 'bg-pink-600' : 'bg-gray-700'}`}
              >
                {val}%
              </button>
            ))}
            <input
              type="number"
              value={slippage}
              onChange={(e) => setSlippage(e.target.value)}
              className="w-20 bg-gray-700 px-2 rounded text-right"
              placeholder="0.5"
            />
            <span className="text-gray-400">%</span>
          </div>
        </div>
      )}

      <div className="p-6 bg-gray-900 rounded-xl border border-gray-800">
        <div className="space-y-2">
          {/* Token In */}
          <div className="bg-gray-800 rounded-xl p-4">
            <div className="flex justify-between items-center mb-2">
              <label className="text-sm text-gray-400">You pay</label>
              <span className="text-sm text-gray-400">
                Balance: {parseFloat(getBalance(tokenIn)).toFixed(4)}
                <button onClick={setMaxAmount} className="ml-2 text-pink-400 hover:text-pink-300">MAX</button>
              </span>
            </div>
            <div className="flex gap-2">
              <input
                type="number"
                value={amountIn}
                onChange={(e) => setAmountIn(e.target.value)}
                className="flex-1 bg-transparent text-2xl font-medium outline-none"
                placeholder="0.0"
              />
              <select
                value={tokenIn.symbol}
                onChange={(e) => {
                  const token = TOKENS.find(t => t.symbol === e.target.value);
                  if (token && token.symbol !== tokenOut.symbol) setTokenIn(token);
                }}
                className="bg-gray-700 px-3 py-2 rounded-lg font-medium cursor-pointer"
              >
                {TOKENS.map(t => (
                  <option key={t.symbol} value={t.symbol} disabled={t.symbol === tokenOut.symbol}>
                    {t.symbol}
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Swap button */}
          <div className="flex justify-center -my-2 z-10 relative">
            <button
              onClick={swapTokens}
              className="bg-gray-800 border-4 border-gray-900 rounded-xl p-2 hover:bg-gray-700 transition-colors"
            >
              ⇅
            </button>
          </div>

          {/* Token Out */}
          <div className="bg-gray-800 rounded-xl p-4">
            <div className="flex justify-between items-center mb-2">
              <label className="text-sm text-gray-400">You receive</label>
              <span className="text-sm text-gray-400">
                Balance: {parseFloat(getBalance(tokenOut)).toFixed(4)}
              </span>
            </div>
            <div className="flex gap-2">
              <input
                type="number"
                value={amountOut}
                readOnly
                className="flex-1 bg-transparent text-2xl font-medium outline-none cursor-not-allowed"
                placeholder="0.0"
              />
              <select
                value={tokenOut.symbol}
                onChange={(e) => {
                  const token = TOKENS.find(t => t.symbol === e.target.value);
                  if (token && token.symbol !== tokenIn.symbol) setTokenOut(token);
                }}
                className="bg-gray-700 px-3 py-2 rounded-lg font-medium cursor-pointer"
              >
                {TOKENS.map(t => (
                  <option key={t.symbol} value={t.symbol} disabled={t.symbol === tokenIn.symbol}>
                    {t.symbol}
                  </option>
                ))}
              </select>
            </div>
          </div>
        </div>

        {/* Price info */}
        {amountIn && amountOut && parseFloat(amountIn) > 0 && (
          <div className="mt-4 p-3 bg-gray-800 rounded-lg text-sm">
            <div className="flex justify-between text-gray-400">
              <span>Rate</span>
              <span>1 {tokenIn.symbol} = {(parseFloat(amountOut) / parseFloat(amountIn)).toFixed(6)} {tokenOut.symbol}</span>
            </div>
            <div className="flex justify-between text-gray-400">
              <span>Slippage Tolerance</span>
              <span>{slippage}%</span>
            </div>
          </div>
        )}

        {/* Swap button */}
        <button
          onClick={handleSwap}
          disabled={isPending || isConfirming || (!amountIn && isConnected)}
          className={`w-full mt-4 p-4 rounded-xl font-bold text-lg transition-all ${!isConnected
              ? 'bg-blue-600 hover:bg-blue-700'
              : 'bg-gradient-to-r from-pink-600 to-purple-600 hover:from-pink-700 hover:to-purple-700 disabled:opacity-50 disabled:cursor-not-allowed'
            }`}
        >
          {!isConnected
            ? 'Connect Wallet'
            : isPending
              ? 'Confirm in Wallet...'
              : isConfirming
                ? 'Swapping...'
                : 'Swap'}
        </button>

        {/* Status messages */}
        {isSuccess && (
          <div className="mt-4 p-3 bg-green-900/50 border border-green-500 rounded-lg text-green-400 text-center">
            ✓ Swap Successful!
          </div>
        )}
        {error && (
          <div className="mt-4 p-3 bg-red-900/50 border border-red-500 rounded-lg text-red-400 text-sm">
            Error: {error.message.slice(0, 100)}...
          </div>
        )}
      </div>
    </div>
  );
}
