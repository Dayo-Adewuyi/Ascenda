import { Button } from './Shared';
import { useApp } from '../AppContext';

export const Header = () => {
  const { account, connectWallet, currentPage, setCurrentPage } = useApp();

  const navItems = [
    { id: 'landing', label: 'Home' },
    { id: 'trading', label: 'Trade' },
    { id: 'portfolio', label: 'Portfolio' },
    { id: 'analytics', label: 'Analytics' }
  ];

  return (
    <header className="bg-white shadow-lg sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          <div 
            className="text-2xl font-bold bg-gradient-to-r from-blue-600 to-purple-600 bg-clip-text text-transparent cursor-pointer"
            onClick={() => setCurrentPage('landing')}
          >
            Ascenda
          </div>
          
          <nav className="hidden md:flex space-x-8">
            {navItems.map(item => (
              <button
                key={item.id}
                onClick={() => setCurrentPage(item.id)}
                className={`px-3 py-2 text-sm font-medium transition-colors ${
                  currentPage === item.id
                    ? 'text-blue-600 border-b-2 border-blue-600'
                    : 'text-gray-600 hover:text-blue-600'
                }`}
              >
                {item.label}
              </button>
            ))}
          </nav>

          <div className="flex items-center space-x-4">
            <div className="flex items-center">
              <div className={`w-3 h-3 rounded-full mr-2 ${account ? 'bg-green-500' : 'bg-red-500'}`}></div>
              <Button
                onClick={connectWallet}
                variant={account ? 'ghost' : 'primary'}
                className="text-sm"
              >
                {account ? `${account.slice(0, 6)}...${account.slice(-4)}` : 'Connect Wallet'}
              </Button>
            </div>
          </div>
        </div>
      </div>
    </header>
  );
};
