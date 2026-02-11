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

CREATE TABLE accumulation_trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Link to the SELL transaction (exit)
    exit_transaction_id UUID NOT NULL REFERENCES transactions(id),
    -- Link to the BUY transaction (re-entry) - NULL until executed
    reentry_transaction_id UUID REFERENCES transactions(id),
    -- Asset being traded
    asset_id UUID NOT NULL REFERENCES assets(id),
    -- The key metric: old vs new coin amounts
    old_coin_amount NUMERIC(20, 18) NOT NULL,  -- Coins sold (gross_amount)
    new_coin_amount NUMERIC(20, 18),             -- Coins bought back (NULL until re-entry)
    -- Calculated: extra coins gained (or lost)
    accumulation_delta NUMERIC(20, 18) GENERATED ALWAYS AS (
        COALESCE(new_coin_amount, 0) - old_coin_amount
    ) STORED,
    -- Status tracking
    status VARCHAR(10) NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'CLOSED', 'CANCELLED')),
    -- Performance metrics
    exit_price_usd NUMERIC(20, 18) NOT NULL,      -- Price when sold
    reentry_price_usd NUMERIC(20, 18),             -- Price when bought back
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP WITH TIME ZONE,
    -- Optional notes on your prediction/reasoning
    prediction_notes TEXT
);

-- 2. Index for performance
CREATE INDEX idx_accumulation_trades_status ON accumulation_trades(status);
CREATE INDEX idx_accumulation_trades_asset ON accumulation_trades(asset_id);

--created by opencode

-- ==========================================
-- STRATEGY TABLES FOR TRADING ASSISTANT
-- ==========================================

-- 1. Sell Strategies: One threshold per coin for automatic sell alerts
CREATE TABLE sell_strategies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL REFERENCES assets(id),
    threshold_percent NUMERIC(5, 2) NOT NULL CHECK (threshold_percent > 0),  -- e.g., 4.00 for 4%
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(asset_id)  -- Only one strategy per asset
);

CREATE INDEX idx_sell_strategies_active ON sell_strategies(asset_id, is_active);

-- 2. Buy Strategies: Dip threshold and USD amount per coin for "buy the dip"
CREATE TABLE buy_strategies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL REFERENCES assets(id),
    dip_threshold_percent NUMERIC(5, 2) NOT NULL CHECK (dip_threshold_percent > 0),  -- e.g., 5.00 = buy when 5% below peak
    buy_amount_usd NUMERIC(20, 2) NOT NULL CHECK (buy_amount_usd > 0),              -- e.g., 100.00 = buy $100 worth
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(asset_id)  -- Only one strategy per asset
);

CREATE INDEX idx_buy_strategies_active ON buy_strategies(asset_id, is_active);

-- 3. Strategy Alerts: Track when strategies trigger
CREATE TABLE strategy_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL REFERENCES assets(id),
    strategy_type VARCHAR(4) NOT NULL CHECK (strategy_type IN ('BUY', 'SELL')),
    trigger_price NUMERIC(20, 8) NOT NULL,        -- Price when alert was triggered
    threshold_percent NUMERIC(5, 2) NOT NULL,     -- The threshold that was met
    reference_price NUMERIC(20, 8) NOT NULL,      -- Buy price for SELL alerts, peak price for BUY alerts
    alert_message TEXT,                           -- Human-readable description
    status VARCHAR(12) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACKNOWLEDGED', 'EXECUTED', 'DISMISSED')),
    acknowledged_at TIMESTAMP WITH TIME ZONE,
    executed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_strategy_alerts_asset ON strategy_alerts(asset_id);
CREATE INDEX idx_strategy_alerts_status ON strategy_alerts(status);
CREATE INDEX idx_strategy_alerts_pending ON strategy_alerts(asset_id, strategy_type, status) WHERE status = 'PENDING';

-- 4. Price Peaks: Track highest price since last buy for each asset
CREATE TABLE price_peaks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID NOT NULL UNIQUE REFERENCES assets(id),  -- One active peak per asset
    last_buy_transaction_id UUID REFERENCES transactions(id),  -- Reference to the last BUY
    peak_price NUMERIC(20, 8) NOT NULL,           -- Highest price observed since last buy
    peak_timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_price_peaks_asset_active ON price_peaks(asset_id, is_active);

-- ==========================================
-- VIEWS FOR STRATEGY OPPORTUNITIES
-- ==========================================

-- View: Identify SELL opportunities (transactions that exceeded their threshold)
-- Usage in Spring Boot: Query this view with current_price parameter
CREATE OR REPLACE VIEW sell_opportunities AS
SELECT 
    t.id AS transaction_id,
    a.symbol,
    a.name AS asset_name,
    t.transaction_type,
    t.unit_price_usd AS buy_price,
    t.net_amount AS coin_amount,
    ss.threshold_percent,
    -- Calculate target sell price: buy_price * (1 + threshold/100)
    t.unit_price_usd * (1 + ss.threshold_percent / 100) AS target_sell_price
FROM transactions t
JOIN assets a ON t.asset_id = a.id
JOIN sell_strategies ss ON ss.asset_id = t.asset_id AND ss.is_active = true
WHERE t.transaction_type = 'BUY'
  AND ss.threshold_percent IS NOT NULL;

-- View: Identify BUY opportunities (assets that dipped below their threshold from peak)
CREATE OR REPLACE VIEW buy_opportunities AS
SELECT 
    a.id AS asset_id,
    a.symbol,
    a.name AS asset_name,
    bs.dip_threshold_percent,
    bs.buy_amount_usd,
    pp.peak_price,
    -- Calculate target buy price: peak_price * (1 - dip_threshold/100)
    pp.peak_price * (1 - bs.dip_threshold_percent / 100) AS target_buy_price,
    pp.last_buy_transaction_id,
    pp.peak_timestamp AS last_peak_timestamp
FROM buy_strategies bs
JOIN assets a ON bs.asset_id = a.id
LEFT JOIN price_peaks pp ON pp.asset_id = bs.asset_id AND pp.is_active = true
WHERE bs.is_active = true;

-- ==========================================
-- HELPER FUNCTION
-- ==========================================

-- Function: Reset price peak when a new BUY transaction is inserted
-- Call this from your Spring Boot service after inserting a new BUY transaction
CREATE OR REPLACE FUNCTION reset_price_peak_on_buy()
RETURNS TRIGGER AS $$
BEGIN
    -- Insert or update price_peaks with the buy price as the new starting point
    INSERT INTO price_peaks (asset_id, last_buy_transaction_id, peak_price, peak_timestamp, is_active)
    VALUES (NEW.asset_id, NEW.id, NEW.unit_price_usd, NEW.transaction_date, true)
    ON CONFLICT (asset_id) 
    DO UPDATE SET
        last_buy_transaction_id = NEW.id,
        peak_price = NEW.unit_price_usd,
        peak_timestamp = NEW.transaction_date,
        is_active = true,
        updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-reset price peak on new BUY transaction
DROP TRIGGER IF EXISTS trg_reset_price_peak ON transactions;
CREATE TRIGGER trg_reset_price_peak
    AFTER INSERT ON transactions
    FOR EACH ROW
    WHEN (NEW.transaction_type = 'BUY')
    EXECUTE FUNCTION reset_price_peak_on_buy();