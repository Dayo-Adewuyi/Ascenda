import styled from 'styled-components';
import { useApp } from '../AppContext';
import { Button, Card } from '../components/Shared';

const Wrapper = styled.div`
  min-height: 100vh;
  background: linear-gradient(to bottom right, #eff6ff, #f5f3ff);
`;

const Section = styled.section`
  padding-top: 5rem;
  padding-bottom: 8rem;
  padding-left: 1rem;
  padding-right: 1rem;
`;

const Container = styled.div`
  max-width: 80rem;
  margin: 0 auto;
  text-align: center;
`;

const Title = styled.h1`
  font-size: 2.25rem;
  font-weight: bold;
  margin-bottom: 1.5rem;
  background: linear-gradient(to right, #2563eb, #7c3aed);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;

  @media(min-width: 768px) {
    font-size: 3.75rem;
  }
`;

const Subtitle = styled.p`
  font-size: 1.125rem;
  color: #4b5563;
  margin-bottom: 2rem;
  max-width: 48rem;
  margin-left: auto;
  margin-right: auto;

  @media(min-width: 768px) {
    font-size: 1.25rem;
  }
`;

const ButtonGroup = styled.div`
  display: flex;
  flex-direction: column;
  gap: 1rem;
  justify-content: center;
  align-items: center;
  margin-bottom: 4rem;

  @media(min-width: 640px) {
    flex-direction: row;
  }
`;

const FeaturesGrid = styled.div`
  display: grid;
  grid-template-columns: repeat(1, 1fr);
  gap: 2rem;
  max-width: 72rem;
  margin: 0 auto;

  @media(min-width: 768px) {
    grid-template-columns: repeat(2, 1fr);
  }

  @media(min-width: 1024px) {
    grid-template-columns: repeat(4, 1fr);
  }
`;

const FeatureIcon = styled.div`
  font-size: 2.5rem;
  margin-bottom: 1rem;
`;

const FeatureTitle = styled.h3`
  font-size: 1.25rem;
  font-weight: bold;
  margin-bottom: 0.5rem;
`;

const FeatureDescription = styled.p`
  color: #4b5563;
`;

const StatsSection = styled.section`
  padding: 5rem 1rem;
  background-color: #ffffff;
`;

const StatsGrid = styled.div`
  display: grid;
  grid-template-columns: repeat(1, 1fr);
  gap: 2rem;
  text-align: center;

  @media(min-width: 768px) {
    grid-template-columns: repeat(3, 1fr);
  }
`;

const StatValue = styled.div`
  font-size: 2.25rem;
  font-weight: bold;
  color: #2563eb;
  margin-bottom: 0.5rem;
`;

const StatLabel = styled.div`
  color: #4b5563;
`;

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
    <Wrapper>
      {/* Hero Section */}
      <Section>
        <Container>
          <Title>Privacy-First DeFi Trading</Title>
          <Subtitle>
            Trade derivatives on real-world assets with complete privacy using FHEVM encryption 
            and 1inch's advanced protocols
          </Subtitle>
          <ButtonGroup>
            <Button onClick={() => setCurrentPage('trading')} className="text-lg px-8 py-4">
              Start Trading
            </Button>
            <Button variant="secondary" className="text-lg px-8 py-4">
              Learn More
            </Button>
          </ButtonGroup>
       
          <FeaturesGrid>
            {features.map((feature, index) => (
              <Card key={index} hover className="text-center">
                <FeatureIcon>{feature.icon}</FeatureIcon>
                <FeatureTitle>{feature.title}</FeatureTitle>
                <FeatureDescription>{feature.description}</FeatureDescription>
              </Card>
            ))}
          </FeaturesGrid>
        </Container>
      </Section>

      {/* Stats Section */}
      <StatsSection>
        <Container>
          <StatsGrid>
            <div>
              <StatValue>$2.1B+</StatValue>
              <StatLabel>Total Volume Traded</StatLabel>
            </div>
            <div>
              <StatValue>50K+</StatValue>
              <StatLabel>Active Traders</StatLabel>
            </div>
            <div>
              <StatValue>99.9%</StatValue>
              <StatLabel>Uptime</StatLabel>
            </div>
          </StatsGrid>
        </Container>
      </StatsSection>
    </Wrapper>
  );
};

export default LandingPage;
