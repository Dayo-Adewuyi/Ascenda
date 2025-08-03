import React, { useState, createContext, useContext } from 'react';

const AppContext = createContext();

export const useApp = () => {
  const context = useContext(AppContext);
  if (!context) {
    throw new Error('useApp must be used within AppProvider');
  }
  return context;
};

export const AppProvider = ({ children }) => {
  const [account, setAccount] = useState(null);
  const [web3, setWeb3] = useState(null);
  const [chainId, setChainId] = useState(null);
  const [currentPage, setCurrentPage] = useState('landing');
  const [loading, setLoading] = useState(false);
  const [positions, setPositions] = useState([]);
  const [notifications, setNotifications] = useState([]);

  const contracts = {
    CONFIDENTIAL_COLLATERAL: '0x06639333dB05FfC223165f6e3B76a11Dba4c4b3a',
    ORACLE: '0xC079AF4d6c8A439333Fa682654f1367860153b0f',
    DERIVATIVES_ENGINE: '0x17a15e5Dc89bb4bA3F322853b259a0737cB3b6Cf'
  };

  const connectWallet = async () => {
    if (typeof window.ethereum !== 'undefined') {
      try {
        setLoading(true);
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        const web3Instance = new (await import('web3')).default(window.ethereum);
        
        setAccount(accounts[0]);
        setWeb3(web3Instance);
        setChainId(await web3Instance.eth.getChainId());
        
        addNotification('Wallet connected successfully!', 'success');
      } catch (error) {
        addNotification('Failed to connect wallet', 'error');
      } finally {
        setLoading(false);
      }
    } else {
      addNotification('Please install MetaMask', 'error');
    }
  };

  const addNotification = (message, type = 'info') => {
    const id = Date.now();
    setNotifications(prev => [...prev, { id, message, type }]);
    setTimeout(() => {
      setNotifications(prev => prev.filter(n => n.id !== id));
    }, 5000);
  };

  const value = {
    account,
    web3,
    chainId,
    currentPage,
    setCurrentPage,
    loading,
    setLoading,
    positions,
    setPositions,
    notifications,
    addNotification,
    connectWallet,
    contracts
  };

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>;
};