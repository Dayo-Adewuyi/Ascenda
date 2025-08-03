import React from 'react';
import { useApp } from '../AppContext';
import { Card } from '../components/Shared';


const AnalyticsPage = () => {
  const { account } = useApp();

  const metrics = [
    { label: 'Win Rate', value: '68%', change: '+5%', positive: true },
    { label: 'Avg Return', value: '12.4%', change: '+2.1%', positive: true },
    { label: 'Best Trade', value: '$2,450', change: '', positive: true },
    { label: 'Worst Trade', value: '-$890', change: '', positive: false }
  ];

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50 py-8">
      <div className="max-w-7xl mx-auto px-4">
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Analytics</h1>
          <p className="text-gray-600">Detailed performance analysis and insights</p>
        </div>

        {!account ? (
          <Card className="text-center py-12">
            <div className="text-6xl mb-4">📊</div>
            <h3 className="text-2xl font-bold mb-2">Connect Your Wallet</h3>
            <p className="text-gray-600 mb-6">Connect your wallet to view analytics</p>
          </Card>
        ) : (
          <div className="space-y-8">
            {/* Key Metrics */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
              {metrics.map((metric, index) => (
                <Card key={index}>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-gray-900 mb-2">{metric.value}</div>
                    <div className="text-sm text-gray-600 mb-1">{metric.label}</div>
                    {metric.change && (
                      <div className={`text-xs ${metric.positive ? 'text-green-600' : 'text-red-600'}`}>
                        {metric.change}
                      </div>
                    )}
                  </div>
                </Card>
              ))}
            </div>

            {/* Charts Placeholder */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
              <Card>
                <h3 className="text-xl font-bold mb-4">Performance Over Time</h3>
                <div className="h-64 bg-gray-100 rounded-lg flex items-center justify-center">
                  <div className="text-center">
                    <div className="text-4xl mb-2">📈</div>
                    <p className="text-gray-600">Performance chart would go here</p>
                  </div>
                </div>
              </Card>

              <Card>
                <h3 className="text-xl font-bold mb-4">Asset Allocation</h3>
                <div className="h-64 bg-gray-100 rounded-lg flex items-center justify-center">
                  <div className="text-center">
                    <div className="text-4xl mb-2">🥧</div>
                    <p className="text-gray-600">Allocation chart would go here</p>
                  </div>
                </div>
              </Card>
            </div>

            {/* Recent Activity */}
            <Card>
              <h3 className="text-xl font-bold mb-4">Recent Activity</h3>
              <div className="space-y-4">
                {[
                  { action: 'Opened', asset: 'AAPL Call', details: '5 contracts @ $150 strike', time: '2 hours ago' },
                  { action: 'Closed', asset: 'TSLA Put', details: '2 contracts @ $200 strike', time: '1 day ago' },
                  { action: 'Executed', asset: 'Bull Call Spread', details: 'SPY $420-430', time: '3 days ago' }
                ].map((activity, index) => (
                  <div key={index} className="flex items-center justify-between py-3 border-b border-gray-100 last:border-b-0">
                    <div>
                      <div className="font-semibold">{activity.action} {activity.asset}</div>
                      <div className="text-sm text-gray-600">{activity.details}</div>
                    </div>
                    <div className="text-sm text-gray-500">{activity.time}</div>
                  </div>
                ))}
              </div>
            </Card>
          </div>
        )}
      </div>
    </div>
  );
};

export default AnalyticsPage;