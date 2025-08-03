import  { useState } from 'react';
import { useApp } from '../AppContext';
import { Button, Card } from '../components/Shared';



const PortfolioPage = () => {
  const { account, positions, addNotification } = useApp();
  const [loading, setLoading] = useState(false);

  const mockPositions = [
    {
      id: 1,
      underlying: 'AAPL',
      type: 'Call',
      strike: 150,
      quantity: 5,
      pnl: 250.75,
      status: 'Open',
      expiration: '2025-12-15'
    },
    {
      id: 2,
      underlying: 'TSLA',
      type: 'Put',
      strike: 200,
      quantity: 2,
      pnl: -120.50,
      status: 'Open',
      expiration: '2025-11-20'
    },
    {
      id: 3,
      underlying: 'SPY',
      type: 'Call',
      strike: 420,
      quantity: 10,
      pnl: 1250.25,
      status: 'Closed',
      expiration: '2025-10-18'
    }
  ];

  const totalPnL = mockPositions.reduce((sum, pos) => sum + pos.pnl, 0);
  const openPositions = mockPositions.filter(pos => pos.status === 'Open');

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50 py-8">
      <div className="max-w-7xl mx-auto px-4">
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Portfolio</h1>
          <p className="text-gray-600">Track your positions and performance</p>
        </div>

        {!account ? (
          <Card className="text-center py-12">
            <div className="text-6xl mb-4">🔐</div>
            <h3 className="text-2xl font-bold mb-2">Connect Your Wallet</h3>
            <p className="text-gray-600 mb-6">Connect your wallet to view your portfolio</p>
          </Card>
        ) : (
          <div className="space-y-8">
            {/* Portfolio Summary */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
              <Card>
                <div className="text-center">
                  <div className="text-2xl font-bold text-blue-600 mb-2">
                    ${Math.abs(totalPnL).toLocaleString()}
                  </div>
                  <div className={`text-sm ${totalPnL >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                    Total P&L {totalPnL >= 0 ? '↗' : '↘'}
                  </div>
                </div>
              </Card>
              <Card>
                <div className="text-center">
                  <div className="text-2xl font-bold text-blue-600 mb-2">{openPositions.length}</div>
                  <div className="text-sm text-gray-600">Open Positions</div>
                </div>
              </Card>
              <Card>
                <div className="text-center">
                  <div className="text-2xl font-bold text-blue-600 mb-2">
                    ${(Math.random() * 50000 + 10000).toLocaleString()}
                  </div>
                  <div className="text-sm text-gray-600">Total Value</div>
                </div>
              </Card>
              <Card>
                <div className="text-center">
                  <div className="text-2xl font-bold text-blue-600 mb-2">
                    {((totalPnL / 10000) * 100).toFixed(1)}%
                  </div>
                  <div className="text-sm text-gray-600">Return</div>
                </div>
              </Card>
            </div>

            {/* Positions Table */}
            <Card>
              <div className="flex justify-between items-center mb-6">
                <h3 className="text-xl font-bold">Your Positions</h3>
                <Button variant="ghost" onClick={() => setLoading(!loading)}>
                  Refresh
                </Button>
              </div>

              {loading ? (
                <div className="text-center py-12">
                  <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
                  <p className="text-gray-600">Loading positions...</p>
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead>
                      <tr className="border-b border-gray-200">
                        <th className="text-left py-3 px-4 font-semibold">Asset</th>
                        <th className="text-left py-3 px-4 font-semibold">Type</th>
                        <th className="text-left py-3 px-4 font-semibold">Strike</th>
                        <th className="text-left py-3 px-4 font-semibold">Quantity</th>
                        <th className="text-left py-3 px-4 font-semibold">Expiration</th>
                        <th className="text-left py-3 px-4 font-semibold">P&L</th>
                        <th className="text-left py-3 px-4 font-semibold">Status</th>
                        <th className="text-left py-3 px-4 font-semibold">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {mockPositions.map(position => (
                        <tr key={position.id} className="border-b border-gray-100">
                          <td className="py-4 px-4 font-semibold">{position.underlying}</td>
                          <td className="py-4 px-4">
                            <span className={`px-2 py-1 rounded-full text-xs font-semibold ${
                              position.type === 'Call' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'
                            }`}>
                              {position.type}
                            </span>
                          </td>
                          <td className="py-4 px-4">${position.strike}</td>
                          <td className="py-4 px-4">{position.quantity}</td>
                          <td className="py-4 px-4">{position.expiration}</td>
                          <td className={`py-4 px-4 font-semibold ${position.pnl >= 0 ? 'text-green-600' : 'text-red-600'}`}>
                            {position.pnl >= 0 ? '+' : ''}${position.pnl.toFixed(2)}
                          </td>
                          <td className="py-4 px-4">
                            <span className={`px-3 py-1 rounded-full text-xs font-semibold ${
                              position.status === 'Open' ? 'bg-blue-100 text-blue-800' : 'bg-gray-100 text-gray-800'
                            }`}>
                              {position.status}
                            </span>
                          </td>
                          <td className="py-4 px-4">
                            {position.status === 'Open' && (
                              <Button 
                                variant="ghost" 
                                className="text-sm px-3 py-1"
                                onClick={() => addNotification('Position closed', 'success')}
                              >
                                Close
                              </Button>
                            )}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </Card>
          </div>
        )}
      </div>
    </div>
  );
};

export default PortfolioPage;