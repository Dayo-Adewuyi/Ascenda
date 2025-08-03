import React, { useState } from 'react';
import { useApp } from '../AppContext';
import { Button, Card, Input, Select } from '../components/Shared';


const TradingPage = () => {
  const { account, addNotification, contracts } = useApp();
  const [activeTab, setActiveTab] = useState('swap');
  const [swapData, setSwapData] = useState({
    fromToken: 'USDC',
    toToken: 'WETH',
    amount: '',
    slippage: '0.5'
  });
  const [derivativeData, setDerivativeData] = useState({
    underlying: 'AAPL',
    positionType: 'call',
    strikePrice: '',
    quantity: '',
    expiration: '',
    collateral: ''
  });

  const tokens = [
    { value: 'USDC', label: 'USD Coin (USDC)' },
    { value: 'WETH', label: 'Wrapped Ethereum (WETH)' },
    { value: 'WBTC', label: 'Wrapped Bitcoin (WBTC)' }
  ];

  const assets = [
    { value: 'AAPL', label: 'Apple Inc. (AAPL)' },
    { value: 'TSLA', label: 'Tesla Inc. (TSLA)' },
    { value: 'MTN', label: 'Vail Resorts (MTN)' },
    { value: 'SPY', label: 'SPDR S&P 500 ETF (SPY)' }
  ];

  const handleSwap = async () => {
    if (!account) {
      addNotification('Please connect your wallet first', 'error');
      return;
    }

    if (!swapData.amount) {
      addNotification('Please enter an amount', 'error');
      return;
    }

    try {
      // Here you would integrate with 1inch API
      addNotification(`Swap initiated: ${swapData.amount} ${swapData.fromToken} → ${swapData.toToken}`, 'success');
    } catch (error) {
      addNotification('Swap failed: ' + error.message, 'error');
    }
  };

  const handleDerivativeOrder = async () => {
    if (!account) {
      addNotification('Please connect your wallet first', 'error');
      return;
    }

    const { strikePrice, quantity, collateral } = derivativeData;
    if (!strikePrice || !quantity || !collateral) {
      addNotification('Please fill in all required fields', 'error');
      return;
    }

    try {
      // Here you would integrate with your smart contracts
      addNotification(`Derivative position opened: ${quantity} ${derivativeData.underlying} ${derivativeData.positionType}s`, 'success');
    } catch (error) {
      addNotification('Failed to open position: ' + error.message, 'error');
    }
  };

  const tabs = [
    { id: 'swap', label: 'Spot Trading' },
    { id: 'derivatives', label: 'Derivatives' },
    { id: 'strategies', label: 'Strategies' }
  ];

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50 py-8">
      <div className="max-w-7xl mx-auto px-4">
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Advanced Trading</h1>
          <p className="text-gray-600">Professional-grade tools with complete privacy</p>
        </div>

        <Card className="max-w-4xl mx-auto">
          {/* Tabs */}
          <div className="flex border-b border-gray-200 mb-8">
            {tabs.map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-6 py-3 font-semibold transition-colors border-b-2 ${
                  activeTab === tab.id
                    ? 'text-blue-600 border-blue-600'
                    : 'text-gray-600 border-transparent hover:text-blue-600'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          {/* Swap Tab */}
          {activeTab === 'swap' && (
            <div className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <Select
                    label="From Token"
                    options={tokens}
                    value={swapData.fromToken}
                    onChange={(e) => setSwapData({...swapData, fromToken: e.target.value})}
                  />
                </div>
                <div>
                  <Select
                    label="To Token"
                    options={tokens}
                    value={swapData.toToken}
                    onChange={(e) => setSwapData({...swapData, toToken: e.target.value})}
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <Input
                  label="Amount"
                  type="number"
                  placeholder="0.0"
                  value={swapData.amount}
                  onChange={(e) => setSwapData({...swapData, amount: e.target.value})}
                />
                <Input
                  label="Slippage (%)"
                  type="number"
                  placeholder="0.5"
                  value={swapData.slippage}
                  onChange={(e) => setSwapData({...swapData, slippage: e.target.value})}
                />
              </div>

              <Card className="bg-gray-50">
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div className="flex justify-between">
                    <span>Exchange Rate:</span>
                    <span className="font-semibold">1 USDC = 0.0003 WETH</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Price Impact:</span>
                    <span className="font-semibold">0.1%</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Network Fee:</span>
                    <span className="font-semibold">~$2.50</span>
                  </div>
                  <div className="flex justify-between">
                    <span>You'll receive:</span>
                    <span className="font-semibold">~0.15 WETH</span>
                  </div>
                </div>
              </Card>

              <Button onClick={handleSwap} className="w-full">
                Execute Swap
              </Button>
            </div>
          )}

          {/* Derivatives Tab */}
          {activeTab === 'derivatives' && (
            <div className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <Select
                  label="Underlying Asset"
                  options={assets}
                  value={derivativeData.underlying}
                  onChange={(e) => setDerivativeData({...derivativeData, underlying: e.target.value})}
                />
                <Select
                  label="Position Type"
                  options={[
                    { value: 'call', label: 'Call Option' },
                    { value: 'put', label: 'Put Option' }
                  ]}
                  value={derivativeData.positionType}
                  onChange={(e) => setDerivativeData({...derivativeData, positionType: e.target.value})}
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <Input
                  label="Strike Price ($)"
                  type="number"
                  placeholder="150.00"
                  value={derivativeData.strikePrice}
                  onChange={(e) => setDerivativeData({...derivativeData, strikePrice: e.target.value})}
                />
                <Input
                  label="Quantity"
                  type="number"
                  placeholder="1"
                  value={derivativeData.quantity}
                  onChange={(e) => setDerivativeData({...derivativeData, quantity: e.target.value})}
                />
                <Input
                  label="Collateral (USDC)"
                  type="number"
                  placeholder="1000.00"
                  value={derivativeData.collateral}
                  onChange={(e) => setDerivativeData({...derivativeData, collateral: e.target.value})}
                />
              </div>

              <Input
                label="Expiration Date"
                type="date"
                value={derivativeData.expiration}
                onChange={(e) => setDerivativeData({...derivativeData, expiration: e.target.value})}
                min={new Date().toISOString().split('T')[0]}
              />

              <Card className="bg-gray-50">
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div className="flex justify-between">
                    <span>Premium:</span>
                    <span className="font-semibold">$125.50</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Max Loss:</span>
                    <span className="font-semibold text-red-600">$1,000.00</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Max Profit:</span>
                    <span className="font-semibold text-green-600">Unlimited</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Break Even:</span>
                    <span className="font-semibold">$151.25</span>
                  </div>
                </div>
              </Card>

              <Button onClick={handleDerivativeOrder} className="w-full">
                Open Position
              </Button>
            </div>
          )}

          {/* Strategies Tab */}
          {activeTab === 'strategies' && (
            <div className="space-y-6">
              <Select
                label="Strategy Type"
                options={[
                  { value: 'bull_call_spread', label: 'Bull Call Spread' },
                  { value: 'bear_put_spread', label: 'Bear Put Spread' },
                  { value: 'iron_condor', label: 'Iron Condor' },
                  { value: 'straddle', label: 'Straddle' }
                ]}
              />

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <Select
                  label="Underlying Asset"
                  options={assets}
                />
                <Input
                  label="Strategy Expiration"
                  type="date"
                  min={new Date().toISOString().split('T')[0]}
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <Input
                  label="Lower Strike ($)"
                  type="number"
                  placeholder="145.00"
                />
                <Input
                  label="Upper Strike ($)"
                  type="number"
                  placeholder="155.00"
                />
              </div>

              <Card className="bg-gray-50">
                <h4 className="font-semibold mb-4">Strategy Analysis</h4>
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div className="flex justify-between">
                    <span>Net Premium:</span>
                    <span className="font-semibold text-green-600">+$250.00</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Max Risk:</span>
                    <span className="font-semibold text-red-600">$750.00</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Max Reward:</span>
                    <span className="font-semibold text-green-600">$250.00</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Probability of Profit:</span>
                    <span className="font-semibold">68%</span>
                  </div>
                </div>
              </Card>

              <Button className="w-full">
                Execute Strategy
              </Button>
            </div>
          )}
        </Card>
      </div>
    </div>
  );
};

export default TradingPage;