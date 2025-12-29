export default function DocsPage() {
  return (
    <div className="max-w-4xl mx-auto mt-10 p-6">
      <h1 className="text-4xl font-bold mb-6 text-pink-500">MiniSwap Documentation</h1>

      <div className="space-y-8">
        <section>
          <h2 className="text-2xl font-semibold mb-4 text-gray-200">Overview</h2>
          <p className="text-gray-400">
            MiniSwap is a decentralized protocol for automated liquidity provision on Ethereum.
            It is designed with simplicity and gas efficiency in mind, adhering to the standard Uniswap V2 core design.
          </p>
        </section>

        <section>
          <h2 className="text-2xl font-semibold mb-4 text-gray-200">Core Concepts</h2>
          <ul className="list-disc pl-5 space-y-2 text-gray-400">
            <li>
              <strong className="text-white">AMM (Automated Market Maker):</strong> Pricing is determined automatically by the constant product formula <code>x * y = k</code>.
            </li>
            <li>
              <strong className="text-white">Liquidity Pools:</strong> Users pool assets together to facilitate trading.
            </li>
            <li>
              <strong className="text-white">Swapping:</strong> Traders can swap ERC20 tokens directly against the liquidity pool.
            </li>
          </ul>
        </section>

        <section>
          <h2 className="text-2xl font-semibold mb-4 text-gray-200">Smart Contracts</h2>
          <div className="bg-gray-900 p-4 rounded-lg">
            <h3 className="text-xl font-medium mb-2 text-pink-400">Factory</h3>
            <p className="text-sm text-gray-400 mb-4">Responsible for deploying new pairs.</p>

            <h3 className="text-xl font-medium mb-2 text-pink-400">Router</h3>
            <p className="text-sm text-gray-400 mb-4">Handles interaction with pairs (adding/removing liquidity, swapping).</p>

            <h3 className="text-xl font-medium mb-2 text-pink-400">Pair</h3>
            <p className="text-sm text-gray-400">Holds the liquidity and executes the low-level swaps.</p>
          </div>
        </section>

        <section>
          <h2 className="text-2xl font-semibold mb-4 text-gray-200">How to Use</h2>
          <div className="space-y-4 text-gray-400">
            <p>
              1. <strong>Connect:</strong> Connect your wallet using the button in the top right.
            </p>
            <p>
              2. <strong>Add Liquidity:</strong> Go to the Pool tab to add WETH and Tokens to a pool.
            </p>
            <p>
              3. <strong>Swap:</strong> Use the Swap home page to trade tokens instanty.
            </p>
          </div>
        </section>
      </div>
    </div>
  );
}
