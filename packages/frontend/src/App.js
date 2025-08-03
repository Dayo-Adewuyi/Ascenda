import { useApp } from './AppContext';
import { Header } from './components/Header';
import { Notifications } from './components/Notifications';
import  LandingPage from './pages/LandingPage';
import  TradingPage  from './pages/TradingPage';
import  PortfolioPage from './pages/PortfolioPage';
import  AnalyticsPage  from './pages/AnalyticPage';  

const App = () => {
  const { currentPage } = useApp();

  const renderPage = () => {
    switch (currentPage) {
      case 'trading':
        return <TradingPage />;
      case 'portfolio':
        return <PortfolioPage />;
      case 'analytics':
        return <AnalyticsPage />;
      default:
        return <LandingPage />;
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <Header />
      <Notifications />
      {renderPage()}
    </div>
  );
};

export default App;
