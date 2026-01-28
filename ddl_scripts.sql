CREATE TABLE btc_historic_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    day_date DATE NOT NULL UNIQUE,
    high_price NUMERIC(20, 8) NOT NULL,
    low_price NUMERIC(20, 8) NOT NULL,
    closing_price NUMERIC(20, 8) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);