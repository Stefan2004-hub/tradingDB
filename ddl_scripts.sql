CREATE TABLE btc_historic_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    day_date DATE NOT NULL UNIQUE,
    high_price NUMERIC(20, 8) NOT NULL,
    low_price NUMERIC(20, 8) NOT NULL,
    closing_price NUMERIC(20, 8) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 1. Create the Assets table
CREATE TABLE assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol VARCHAR(10) NOT NULL UNIQUE, -- e.g., 'BTC'
    name VARCHAR(50) NOT NULL           -- e.g., 'Bitcoin'
);

-- 2. Create the Exchanges table
CREATE TABLE exchanges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(50) NOT NULL UNIQUE    -- e.g., 'Binance'
);

CREATE TABLE transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID REFERENCES assets(id),
    exchange_id UUID REFERENCES exchanges(id),
    transaction_type VARCHAR(4) CHECK (transaction_type IN ('BUY', 'SELL')),
    
    -- Financial details
    gross_amount NUMERIC(20, 18) NOT NULL,    -- The 10 BTC you ordered
    fee_amount NUMERIC(20, 18) DEFAULT 0,    -- The 0.1 BTC fee
    fee_currency VARCHAR(10),                -- 'BTC' or 'USD'
    net_amount NUMERIC(20, 18) NOT NULL,      -- The 9.9 BTC that hit your wallet
    
    unit_price_usd NUMERIC(20, 18) NOT NULL,  -- Price of 1 coin at that moment
    total_spent_usd NUMERIC(20, 18) NOT NULL, -- Total USD out of pocket (Gross * Price + USD fees)
    
    transaction_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE VIEW user_portfolio_performance AS
SELECT 
    a.symbol,
    e.name AS exchange,
    -- Total coins currently in wallet
    SUM(CASE WHEN t.transaction_type = 'BUY' THEN t.net_amount ELSE -t.gross_amount END) AS current_balance,
    -- Total USD spent to get those coins
    SUM(CASE WHEN t.transaction_type = 'BUY' THEN t.total_spent_usd ELSE 0 END) AS total_invested_usd,
    -- Average price you paid per coin (Breakeven point)
    CASE 
        WHEN SUM(CASE WHEN t.transaction_type = 'BUY' THEN t.net_amount ELSE 0 END) > 0 
        THEN SUM(CASE WHEN t.transaction_type = 'BUY' THEN t.total_spent_usd ELSE 0 END) / 
             SUM(CASE WHEN t.transaction_type = 'BUY' THEN t.net_amount ELSE 0 END)
        ELSE 0 
    END AS avg_buy_price
FROM transactions t
JOIN assets a ON t.asset_id = a.id
JOIN exchanges e ON t.exchange_id = e.id
GROUP BY a.symbol, e.name;

ALTER TABLE transactions ADD COLUMN realized_pnl NUMERIC(20, 18);

-- Query to see your Current Profit:
-- SELECT 
--     p.symbol,
--     p.current_balance,
--     p.avg_buy_price,
--     h.closing_price AS current_market_price,
--     -- Formula: (Current Price - Avg Buy Price) * Balance
--     (h.closing_price - p.avg_buy_price) * p.current_balance AS unrealized_profit_usd
-- FROM user_portfolio_performance p
-- JOIN btc_historic_data h ON h.day_date = (SELECT MAX(day_date) FROM btc_historic_data)
-- WHERE p.symbol = 'BTC';