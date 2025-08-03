import { useApp } from '../AppContext';
import { Button, Card } from '../components/Shared';


 const LandingPage = () => {
  const { setCurrentPage } = useApp();

  const features = [
    {
      icon: '🔒',
      title: 'Fully Encrypted',
      description: 'All positions and trading activity encrypted using FHEVM technology'
    },
    {
      icon: '🌐',
      title: 'Cross-Chain',
      description: 'Atomic swaps via 1inch Fusion+ protocol across multiple chains'
    },
    {
      icon: '📈',
      title: 'Real Assets',
      description: 'Trade derivatives on AAPL, TSLA, MTN, SPY and more'
    },
    {
      icon: '⚡',
      title: 'MEV Protected',
      description: 'Built-in MEV protection via Etherlink\'s decentralized sequencing'
    }
  ];

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-purple-50">
      {/* Hero Section */}
      <section className="pt-20 pb-32 px-4">
        <div className="max-w-7xl mx-auto text-center">
          <h1 className="text-6xl font-bold mb-6 bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent">
            Privacy-First DeFi Trading
          </h1>
          <p className="text-xl text-gray-600 mb-8 max-w-3xl mx-auto">
            Trade derivatives on real-world assets with complete privacy using FHEVM encryption 
            and 1inch's advanced protocols
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center mb-16">
            <Button onClick={() => setCurrentPage('trading')} className="text-lg px-8 py-4">
              Start Trading
            </Button>
            <Button variant="secondary" className="text-lg px-8 py-4">
              Learn More
            </Button>
          </div>

       
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-8 max-w-6xl mx-auto">
            {features.map((feature, index) => (
              <Card key={index} hover className="text-center">
                <div className="text-4xl mb-4">{feature.icon}</div>
                <h3 className="text-xl font-bold mb-2">{feature.title}</h3>
                <p className="text-gray-600">{feature.description}</p>
              </Card>
            ))}
          </div>
        </div>
      </section>

 
      <section className="py-20 bg-white">
        <div className="max-w-7xl mx-auto px-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-8 text-center">
            <div>
              <div className="text-4xl font-bold text-blue-600 mb-2">$2.1B+</div>
              <div className="text-gray-600">Total Volume Traded</div>
            </div>
            <div>
              <div className="text-4xl font-bold text-blue-600 mb-2">50K+</div>
              <div className="text-gray-600">Active Traders</div>
            </div>
            <div>
              <div className="text-4xl font-bold text-blue-600 mb-2">99.9%</div>
              <div className="text-gray-600">Uptime</div>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
};

export default LandingPage;