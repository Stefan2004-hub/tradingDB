# Trading App - AI Implementation Plan

## Project Overview
Full-stack cryptocurrency trading application with portfolio tracking, swing trade management, and automated strategy alerts.

**Tech Stack:**
- **Backend:** Java 17+, Spring Boot 3.x, Spring Data JPA, Spring Security
- **Database:** PostgreSQL (Neon Cloud)
- **Frontend:** React 18+, TypeScript
- **Authentication:** Google OAuth 2.0 + JWT + Email/Password

---

## Phase 1: Project Setup & Database

### 1.1 Database Schema (Already Designed)
The PostgreSQL schema is complete with:
- `btc_historic_data` - Historical price data
- `assets` - Cryptocurrency definitions
- `exchanges` - Exchange/platform tracking
- `transactions` - Buy/sell records with fee handling
- `accumulation_trades` - Swing trade tracking (buy the dip)
- `sell_strategies` - Per-coin sell thresholds
- `buy_strategies` - Per-coin dip buy configuration
- `strategy_alerts` - Triggered strategy notifications
- `price_peaks` - Track highest prices for dip detection
- Views: `user_portfolio_performance`, `sell_opportunities`, `buy_opportunities`

**Key Design Decisions:**
- UUID primary keys throughout
- Numeric(20, 8) for crypto amounts (18 decimals for precision)
- Separate fee tracking (fee_amount + fee_currency)
- Net vs Gross amounts for accurate wallet tracking
- Realized P&L stored, unrealized calculated dynamically

### 1.2 Spring Boot Project Structure
```
trading-app/
├── src/main/java/com/trading/
│   ├── TradingApplication.java
│   ├── config/
│   │   ├── SecurityConfig.java
│   │   ├── JwtConfig.java
│   │   ├── WebConfig.java
│   │   └── DatabaseConfig.java
│   ├── domain/
│   │   ├── entity/          # JPA Entities
│   │   ├── repository/      # Spring Data Repositories
│   │   └── enums/           # TransactionType, AlertStatus, etc.
│   ├── dto/
│   │   ├── request/
│   │   └── response/
│   ├── service/
│   │   ├── auth/
│   │   ├── portfolio/
│   │   ├── trading/
│   │   └── strategy/
│   ├── controller/
│   │   ├── AuthController.java
│   │   ├── PortfolioController.java
│   │   ├── TransactionController.java
│   │   ├── StrategyController.java
│   │   └── AlertController.java
│   ├── security/
│   │   ├── JwtTokenProvider.java
│   │   ├── OAuth2SuccessHandler.java
│   │   └── UserDetailsServiceImpl.java
│   ├── mapper/
│   └── exception/
├── src/main/resources/
│   ├── application.yml
│   ├── application-dev.yml
│   └── db/migration/        # Flyway migrations
└── src/test/
```

---

## Phase 2: Authentication System

### 2.1 Authentication Architecture
**Dual Authentication:**
1. **Google OAuth 2.0** - Primary method
2. **Email/Password** - Fallback method

**Security Flow:**
```
User Login
    ├─→ Google OAuth → JWT Token
    └─→ Email/Password → Validate → JWT Token

JWT Token contains:
- userId (UUID)
- email
- roles
- issuedAt
- expiration
```

### 2.2 Database Tables for Auth
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255), -- NULL for OAuth-only users
    auth_provider VARCHAR(20) NOT NULL CHECK (auth_provider IN ('GOOGLE', 'LOCAL')),
    provider_id VARCHAR(255), -- Google sub claim
    is_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### 2.3 Spring Security Configuration
**Key Components:**
- `JwtAuthenticationFilter` - Validate JWT on each request
- `OAuth2LoginSuccessHandler` - Handle Google login, create/update user
- `PasswordEncoder` - BCrypt for local passwords
- `UserDetailsService` - Load user by email

**Authorization Rules:**
- `/api/auth/**` - Public (login, register, refresh)
- `/api/public/**` - Public
- All other endpoints - JWT required
- `/api/admin/**` - ADMIN role required

---

## Phase 3: Core Entities & Repositories

### 3.1 JPA Entities (Key Examples)

**Asset Entity:**
```java
@Entity
@Table(name = "assets")
public class Asset {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;
    
    @Column(unique = true, nullable = false, length = 10)
    private String symbol;
    
    @Column(nullable = false, length = 50)
    private String name;
    
    @OneToMany(mappedBy = "asset")
    private List<Transaction> transactions;
}
```

**Transaction Entity:**
```java
@Entity
@Table(name = "transactions")
public class Transaction {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;
    
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "asset_id", nullable = false)
    private Asset asset;
    
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "exchange_id", nullable = false)
    private Exchange exchange;
    
    @Enumerated(EnumType.STRING)
    @Column(name = "transaction_type", nullable = false, length = 4)
    private TransactionType transactionType;
    
    @Column(name = "gross_amount", nullable = false, precision = 20, scale = 18)
    private BigDecimal grossAmount;
    
    @Column(name = "fee_amount", precision = 20, scale = 18)
    private BigDecimal feeAmount;
    
    @Column(name = "fee_currency", length = 10)
    private String feeCurrency;
    
    @Column(name = "net_amount", nullable = false, precision = 20, scale = 18)
    private BigDecimal netAmount;
    
    @Column(name = "unit_price_usd", nullable = false, precision = 20, scale = 18)
    private BigDecimal unitPriceUsd;
    
    @Column(name = "total_spent_usd", nullable = false, precision = 20, scale = 18)
    private BigDecimal totalSpentUsd;
    
    @Column(name = "realized_pnl", precision = 20, scale = 18)
    private BigDecimal realizedPnl;
    
    @Column(name = "transaction_date")
    private Instant transactionDate;
    
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;  // Multi-tenancy support
}
```

**AccumulationTrade Entity:**
```java
@Entity
@Table(name = "accumulation_trades")
public class AccumulationTrade {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;
    
    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "exit_transaction_id", nullable = false)
    private Transaction exitTransaction;
    
    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "reentry_transaction_id")
    private Transaction reentryTransaction;
    
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "asset_id", nullable = false)
    private Asset asset;
    
    @Column(name = "old_coin_amount", nullable = false, precision = 20, scale = 18)
    private BigDecimal oldCoinAmount;
    
    @Column(name = "new_coin_amount", precision = 20, scale = 18)
    private BigDecimal newCoinAmount;
    
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private AccumulationStatus status;
    
    @Column(name = "exit_price_usd", nullable = false, precision = 20, scale = 18)
    private BigDecimal exitPriceUsd;
    
    @Column(name = "reentry_price_usd", precision = 20, scale = 18)
    private BigDecimal reentryPriceUsd;
    
    @Column(name = "prediction_notes")
    private String predictionNotes;
    
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;
}
```

### 3.2 Repository Pattern
Use Spring Data JPA with custom queries:

```java
@Repository
public interface TransactionRepository extends JpaRepository<Transaction, UUID> {
    
    // Get all transactions for a user
    List<Transaction> findByUserIdOrderByTransactionDateDesc(UUID userId);
    
    // Get portfolio summary using the view
    @Query(value = """
        SELECT * FROM user_portfolio_performance 
        WHERE user_id = :userId
        """, nativeQuery = true)
    List<PortfolioSummary> getPortfolioSummary(@Param("userId") UUID userId);
    
    // Find sell opportunities with current price check
    @Query(value = """
        SELECT so.* FROM sell_opportunities so
        WHERE so.user_id = :userId
        AND so.asset_id = :assetId
        AND :currentPrice >= so.target_sell_price
        """, nativeQuery = true)
    List<SellOpportunity> findSellOpportunities(
        @Param("userId") UUID userId,
        @Param("assetId") UUID assetId,
        @Param("currentPrice") BigDecimal currentPrice
    );
}
```

---

## Phase 4: Service Layer Design

### 4.1 Transaction Service
**Responsibilities:**
- Record buy/sell transactions
- Calculate realized P&L for sells
- Handle fee logic (coin vs USD)
- Update accumulation trades on sell

**Key Method Signatures:**
```java
public interface TransactionService {
    TransactionResponse recordBuy(BuyTransactionRequest request);
    TransactionResponse recordSell(SellTransactionRequest request);
    PortfolioSummary getPortfolioSummary(UUID userId);
    BigDecimal calculateRealizedPnl(UUID sellTransactionId);
    List<TransactionResponse> getTransactionHistory(UUID userId, UUID assetId);
}
```

**Buy Transaction Logic:**
1. Validate asset and exchange exist
2. Calculate net_amount = gross_amount - fee_amount (if fee in coin)
3. Calculate total_spent_usd based on unit_price and gross_amount
4. Add USD fee if applicable
5. Save transaction
6. Trigger price peak reset (via database trigger)

**Sell Transaction Logic:**
1. Validate sufficient balance
2. Determine fee type and amount
3. Calculate realized P&L:
   ```
   realizedPnl = (sellPrice * amount) - (avgBuyPrice * amount) - fees
   ```
4. Create accumulation_trade record if "swing trade"
5. Save transaction

### 4.2 Accumulation Trade Service
**Responsibilities:**
- Track "buy the dip" trades
- Calculate accumulation delta
- Manage swing trade lifecycle

**Key Methods:**
```java
public interface AccumulationTradeService {
    AccumulationTradeResponse initiateSwingTrade(UUID sellTransactionId, String notes);
    AccumulationTradeResponse completeSwingTrade(UUID accumulationTradeId, UUID buyTransactionId);
    List<AccumulationTradeResponse> getOpenSwingTrades(UUID userId);
    List<AccumulationTradeResponse> getCompletedSwingTrades(UUID userId);
    AccumulationStats getAccumulationStats(UUID userId, UUID assetId);
}
```

### 4.3 Strategy Service
**Responsibilities:**
- Manage sell/buy strategies per coin
- Monitor price changes and trigger alerts
- Calculate target prices

**Key Methods:**
```java
public interface StrategyService {
    SellStrategyResponse setSellStrategy(SellStrategyRequest request);
    BuyStrategyResponse setBuyStrategy(BuyStrategyRequest request);
    List<SellAlert> checkSellOpportunities(UUID userId, UUID assetId, BigDecimal currentPrice);
    List<BuyAlert> checkBuyOpportunities(UUID userId, UUID assetId, BigDecimal currentPrice);
    void processPriceUpdate(UUID assetId, BigDecimal currentPrice);
}
```

### 4.4 Portfolio Service
**Responsibilities:**
- Aggregate portfolio data
- Calculate unrealized P&L
- Track performance metrics

**Portfolio Calculation:**
```java
public PortfolioPerformance calculatePerformance(UUID userId, UUID assetId, BigDecimal currentPrice) {
    // Get holdings from view
    PortfolioSummary summary = transactionRepository.getPortfolioSummary(userId)
        .stream()
        .filter(s -> s.getAssetId().equals(assetId))
        .findFirst()
        .orElseThrow();
    
    BigDecimal currentBalance = summary.getCurrentBalance();
    BigDecimal avgBuyPrice = summary.getAvgBuyPrice();
    BigDecimal totalInvested = summary.getTotalInvestedUsd();
    
    // Unrealized P&L
    BigDecimal currentValue = currentBalance.multiply(currentPrice);
    BigDecimal unrealizedPnl = currentValue.subtract(totalInvested);
    BigDecimal unrealizedPnlPercent = unrealizedPnl
        .divide(totalInvested, 4, RoundingMode.HALF_UP)
        .multiply(BigDecimal.valueOf(100));
    
    // Get realized P&L from transactions
    BigDecimal realizedPnl = transactionRepository.sumRealizedPnlByUserAndAsset(userId, assetId);
    
    return PortfolioPerformance.builder()
        .assetId(assetId)
        .currentBalance(currentBalance)
        .avgBuyPrice(avgBuyPrice)
        .totalInvested(totalInvested)
        .currentValue(currentValue)
        .unrealizedPnl(unrealizedPnl)
        .unrealizedPnlPercent(unrealizedPnlPercent)
        .realizedPnl(realizedPnl)
        .totalPnl(unrealizedPnl.add(realizedPnl))
        .build();
}
```

---

## Phase 5: REST API Endpoints

### 5.1 Authentication Endpoints
```
POST   /api/auth/register          # Email/password registration
POST   /api/auth/login             # Email/password login
POST   /api/auth/refresh           # Refresh JWT token
POST   /api/auth/logout            # Invalidate token
POST   /api/auth/forgot-password   # Send reset email
POST   /api/auth/reset-password    # Reset with token
GET    /api/auth/oauth2/google     # Initiate Google OAuth
GET    /api/auth/oauth2/callback   # OAuth callback
```

### 5.2 Transaction Endpoints
```
GET    /api/transactions                    # List all transactions
GET    /api/transactions/{id}               # Get single transaction
POST   /api/transactions/buy                # Record buy
POST   /api/transactions/sell               # Record sell
GET    /api/transactions/asset/{assetId}    # Filter by asset
GET    /api/transactions/summary            # Portfolio summary
```

**Buy Request:**
```json
{
  "assetId": "uuid",
  "exchangeId": "uuid",
  "grossAmount": "10.00000000",
  "unitPriceUsd": "45000.00",
  "feeAmount": "0.10000000",
  "feeCurrency": "BTC",
  "transactionDate": "2024-01-15T10:30:00Z"
}
```

### 5.3 Accumulation Trade Endpoints
```
GET    /api/accumulation-trades                    # List all
GET    /api/accumulation-trades/open               # Open swing trades
POST   /api/accumulation-trades                    # Create swing trade
PUT    /api/accumulation-trades/{id}/complete      # Complete with buy
GET    /api/accumulation-trades/{id}/delta         # Get accumulation delta
GET    /api/accumulation-trades/stats              # Statistics
```

### 5.4 Strategy Endpoints
```
# Sell Strategies
GET    /api/strategies/sell                        # List all
POST   /api/strategies/sell                        # Create/update
PUT    /api/strategies/sell/{id}                   # Update
DELETE /api/strategies/sell/{id}                   # Delete

# Buy Strategies
GET    /api/strategies/buy                         # List all
POST   /api/strategies/buy                         # Create/update
PUT    /api/strategies/buy/{id}                    # Update
DELETE /api/strategies/buy/{id}                    # Delete

# Alerts
GET    /api/strategies/alerts                      # Get all alerts
GET    /api/strategies/alerts/pending              # Get pending alerts
POST   /api/strategies/alerts/{id}/acknowledge     # Acknowledge alert
POST   /api/strategies/alerts/{id}/execute         # Execute alert
GET    /api/strategies/opportunities               # Current opportunities
```

### 5.5 Portfolio Endpoints
```
GET    /api/portfolio                              # Full portfolio
GET    /api/portfolio/asset/{assetId}              # Single asset performance
GET    /api/portfolio/performance                  # Performance metrics
GET    /api/portfolio/history                      # Historical performance
```

---

## Phase 6: Frontend Architecture (React)

### 6.1 Project Structure
```
trading-app-frontend/
├── src/
│   ├── components/
│   │   ├── common/           # Reusable components
│   │   │   ├── Button.tsx
│   │   │   ├── Input.tsx
│   │   │   ├── Card.tsx
│   │   │   └── Modal.tsx
│   │   ├── layout/           # Layout components
│   │   │   ├── Header.tsx
│   │   │   ├── Sidebar.tsx
│   │   │   └── Layout.tsx
│   │   ├── auth/             # Auth-related
│   │   │   ├── LoginForm.tsx
│   │   │   ├── GoogleButton.tsx
│   │   │   └── RegisterForm.tsx
│   │   ├── portfolio/        # Portfolio views
│   │   │   ├── PortfolioSummary.tsx
│   │   │   ├── AssetCard.tsx
│   │   │   ├── PerformanceChart.tsx
│   │   │   └── TransactionList.tsx
│   │   ├── transactions/     # Transaction forms
│   │   │   ├── BuyForm.tsx
│   │   │   ├── SellForm.tsx
│   │   │   └── TransactionTable.tsx
│   │   ├── strategies/       # Strategy management
│   │   │   ├── StrategyCard.tsx
│   │   │   ├── SellStrategyForm.tsx
│   │   │   ├── BuyStrategyForm.tsx
│   │   │   └── AlertPanel.tsx
│   │   └── accumulation/     # Swing trades
│   │       ├── SwingTradeList.tsx
│   │       ├── AccumulationStats.tsx
│   │       └── SwingTradeForm.tsx
│   ├── pages/
│   │   ├── Dashboard.tsx
│   │   ├── Portfolio.tsx
│   │   ├── Transactions.tsx
│   │   ├── Strategies.tsx
│   │   ├── Accumulation.tsx
│   │   ├── Login.tsx
│   │   └── Register.tsx
│   ├── hooks/
│   │   ├── useAuth.ts
│   │   ├── usePortfolio.ts
│   │   ├── useTransactions.ts
│   │   ├── useStrategies.ts
│   │   └── useApi.ts
│   ├── context/
│   │   ├── AuthContext.tsx
│   │   └── ThemeContext.tsx
│   ├── services/
│   │   ├── api.ts            # Axios instance
│   │   ├── auth.service.ts
│   │   ├── portfolio.service.ts
│   │   ├── transaction.service.ts
│   │   └── strategy.service.ts
│   ├── types/
│   │   ├── auth.types.ts
│   │   ├── portfolio.types.ts
│   │   ├── transaction.types.ts
│   │   └── strategy.types.ts
│   ├── utils/
│   │   ├── formatters.ts     # Number/date formatting
│   │   ├── calculations.ts   # Client-side calculations
│   │   └── validators.ts
│   ├── styles/
│   └── App.tsx
├── public/
└── package.json
```

### 6.2 Key Features Implementation

**Authentication Flow:**
1. User clicks "Login with Google"
2. Redirect to Google OAuth
3. Callback to backend `/api/auth/oauth2/callback`
4. Backend creates/updates user, generates JWT
5. Frontend receives JWT, stores in httpOnly cookie
6. All subsequent requests include JWT

**Portfolio Dashboard:**
- Real-time portfolio value (manual refresh or polling)
- Asset cards showing: balance, avg price, current price, P&L
- Performance charts (using recharts or chart.js)
- Recent transactions list
- Pending strategy alerts

**Transaction Recording:**
- Forms for buy/sell with validation
- Fee calculator (auto-calculate net amount)
- Asset and exchange selectors
- Date picker for transaction date
- Confirmation modal with summary

**Strategy Management:**
- Set per-coin thresholds
- Visual indicators for triggered strategies
- Alert panel showing opportunities
- One-click execution of strategy alerts

**Accumulation Tracking:**
- List of open swing trades
- Form to initiate swing trade (link to sell transaction)
- Form to complete swing trade (link to buy transaction)
- Statistics showing accumulation delta
- Visual indicators of successful trades

---

## Phase 7: Database Migration Strategy

### 7.1 Flyway Migration Files
```
src/main/resources/db/migration/
├── V1__init_schema.sql              # All tables from ddl_scripts.sql
├── V2__add_users_and_auth.sql       # Auth tables
├── V3__add_user_id_to_tables.sql    # Multi-tenancy
├── V4__add_indexes.sql              # Performance indexes
└── V5__seed_data.sql                # Initial assets, exchanges
```

### 7.2 Multi-Tenancy Support
Add `user_id` foreign key to all user-specific tables:
- transactions
- accumulation_trades
- sell_strategies
- buy_strategies
- strategy_alerts

Update views to include `WHERE user_id = ?`

---

## Phase 8: Testing Strategy

### 8.1 Backend Testing
```
src/test/java/com/trading/
├── unit/
│   ├── service/
│   │   ├── TransactionServiceTest.java
│   │   ├── PortfolioServiceTest.java
│   │   └── StrategyServiceTest.java
│   └── domain/
│       └── TransactionTest.java
├── integration/
│   ├── repository/
│   │   └── TransactionRepositoryTest.java
│   ├── controller/
│   │   └── TransactionControllerTest.java
│   └── security/
│       └── JwtAuthenticationTest.java
└── e2e/
    └── TradingFlowE2ETest.java
```

**Key Test Cases:**
- Transaction recording with different fee scenarios
- P&L calculations (realized and unrealized)
- Accumulation trade lifecycle
- Strategy alert generation
- Authentication flows
- Authorization rules

### 8.2 Frontend Testing
```
src/
├── __tests__/
│   ├── components/
│   │   ├── BuyForm.test.tsx
│   │   └── PortfolioSummary.test.tsx
│   ├── hooks/
│   │   └── usePortfolio.test.ts
│   └── integration/
│       └── trading-flow.test.tsx
└── e2e/
    └── trading.spec.ts
```

---

## Phase 9: Deployment & DevOps

### 9.1 Application Configuration
```yaml
# application.yml
spring:
  datasource:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}
  
  jpa:
    hibernate:
      ddl-auto: validate  # Use Flyway for migrations
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
        format_sql: true
    show-sql: false
  
  flyway:
    enabled: true
    locations: classpath:db/migration

security:
  jwt:
    secret: ${JWT_SECRET}
    expiration: 86400000  # 24 hours
    refresh-expiration: 604800000  # 7 days
  
  oauth2:
    google:
      client-id: ${GOOGLE_CLIENT_ID}
      client-secret: ${GOOGLE_CLIENT_SECRET}

cors:
  allowed-origins: ${FRONTEND_URL}
```

### 9.2 Environment Variables
```bash
# Database
DATABASE_URL=jdbc:postgresql://...neon.tech/tradingdb
DATABASE_USERNAME=...
DATABASE_PASSWORD=...

# JWT
JWT_SECRET=your-256-bit-secret

# OAuth
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...

# Frontend
FRONTEND_URL=http://localhost:3000
```

### 9.3 Deployment Options
**Backend:**
- Docker container (Dockerfile + docker-compose)
- Railway/Render/Heroku for easy deployment
- AWS ECS/Fargate for production scale

**Frontend:**
- Static hosting: Vercel/Netlify/AWS S3
- Environment-specific builds

**Database:**
- Neon PostgreSQL (already chosen)
- Connection pooling (HikariCP)

---

## Phase 10: Implementation Roadmap

### Sprint 1: Foundation (Weeks 1-2)
- [ ] Project setup (Spring Boot + React)
- [ ] Database schema migration with Flyway
- [ ] Basic entities and repositories
- [ ] Docker setup for local development

### Sprint 2: Authentication (Weeks 3-4)
- [ ] Google OAuth integration
- [ ] Email/password authentication
- [ ] JWT token handling
- [ ] Frontend auth context
- [ ] Protected routes

### Sprint 3: Core Trading (Weeks 5-6)
- [ ] Transaction recording (buy/sell)
- [ ] Portfolio summary view
- [ ] Transaction history
- [ ] Basic frontend dashboard

### Sprint 4: Advanced Features (Weeks 7-8)
- [ ] Accumulation trade tracking
- [ ] Swing trade lifecycle
- [ ] Fee calculation logic
- [ ] P&L calculations

### Sprint 5: Strategies (Weeks 9-10)
- [ ] Sell strategy management
- [ ] Buy strategy management
- [ ] Alert generation system
- [ ] Price monitoring service

### Sprint 6: Polish (Weeks 11-12)
- [ ] Charts and visualizations
- [ ] Performance optimization
- [ ] Testing (unit + integration)
- [ ] Documentation
- [ ] Deployment

---

## Critical Implementation Notes

### 1. Precision Handling
Always use `BigDecimal` for monetary values. Never use `double` or `float`.
```java
BigDecimal amount = new BigDecimal("10.00000000");
BigDecimal result = amount.multiply(price).setScale(8, RoundingMode.HALF_UP);
```

### 2. Transaction Boundaries
Use `@Transactional` for multi-step operations:
```java
@Transactional
public AccumulationTradeResponse completeSwingTrade(UUID tradeId, UUID buyTxId) {
    // 1. Update accumulation trade
    // 2. Link buy transaction
    // 3. Calculate delta
    // All or nothing
}
```

### 3. Fee Logic
Distinguish between fee types clearly:
- **Buy with coin fee**: Net = Gross - Fee (fee taken from coins received)
- **Sell with USD fee**: Gross is sold, fee deducted from proceeds

### 4. Time Zones
Store all timestamps in UTC, convert to user timezone in frontend.

### 5. Security
- Never expose database credentials
- Use environment variables for secrets
- Enable CSRF protection for non-API routes
- Rate limit authentication endpoints
- Validate all user inputs

### 6. Performance
- Add indexes on frequently queried columns
- Use pagination for transaction lists
- Cache portfolio summaries (short TTL)
- Database connection pooling

---

## Appendix: Useful SQL Queries

### Get Portfolio Summary with Current Value
```sql
SELECT 
    p.symbol,
    p.current_balance,
    p.avg_buy_price,
    h.closing_price AS current_price,
    p.current_balance * h.closing_price AS current_value,
    (p.current_balance * h.closing_price) - p.total_invested_usd AS unrealized_pnl
FROM user_portfolio_performance p
JOIN btc_historic_data h ON h.day_date = (SELECT MAX(day_date) FROM btc_historic_data)
WHERE p.user_id = ?;
```

### Get Accumulation Success Rate
```sql
SELECT 
    at.asset_id,
    COUNT(*) as total_swings,
    SUM(CASE WHEN at.accumulation_delta > 0 THEN 1 ELSE 0 END) as successful_swings,
    AVG(at.accumulation_delta) as avg_delta
FROM accumulation_trades at
WHERE at.user_id = ?
AND at.status = 'CLOSED'
GROUP BY at.asset_id;
```

### Check Active Alerts
```sql
SELECT * FROM strategy_alerts
WHERE user_id = ?
AND status = 'PENDING'
ORDER BY created_at DESC;
```

---

## Conclusion

This plan provides a complete roadmap for building your trading application. The key is to:
1. Start with the database schema and migrations
2. Build authentication first (security foundation)
3. Implement core transaction recording
4. Add advanced features (accumulation, strategies)
5. Polish with UI/UX and testing

Focus on correctness over complexity—especially for financial calculations. Test thoroughly before deploying to production.
