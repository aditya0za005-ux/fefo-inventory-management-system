CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 username VARCHAR(100) NOT NULL UNIQUE,
 password_hash VARCHAR(255) NOT NULL,
 role VARCHAR(20) NOT NULL CHECK (role IN ('ADMIN','STAFF')),
 active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE products (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 sku VARCHAR(100) NOT NULL UNIQUE,
 name VARCHAR(255) NOT NULL,
 description TEXT,
 active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE batches (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 product_id UUID NOT NULL REFERENCES products(id),
 batch_number VARCHAR(100) NOT NULL,
 expiry_date DATE NOT NULL,
 total_quantity BIGINT NOT NULL CHECK (total_quantity >= 0),
 available_quantity BIGINT NOT NULL CHECK (available_quantity >= 0),
 reserved_quantity BIGINT NOT NULL CHECK (reserved_quantity >= 0),
 expired BOOLEAN NOT NULL DEFAULT FALSE,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(product_id,batch_number),
 CHECK (available_quantity + reserved_quantity <= total_quantity)
);

CREATE TABLE reservations (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 reservation_number VARCHAR(100) NOT NULL UNIQUE,
 product_id UUID NOT NULL REFERENCES products(id),
 status VARCHAR(20) NOT NULL CHECK (status IN ('RESERVED','CONFIRMED','CANCELLED','EXPIRED')),
 requested_quantity BIGINT NOT NULL CHECK (requested_quantity > 0),
 expires_at TIMESTAMPTZ NOT NULL,
 created_by UUID NOT NULL REFERENCES users(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 version BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE reservation_items (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 reservation_id UUID NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
 batch_id UUID NOT NULL REFERENCES batches(id),
 quantity BIGINT NOT NULL CHECK (quantity > 0),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(reservation_id,batch_id)
);

CREATE TABLE idempotency_keys (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 idempotency_key VARCHAR(255) NOT NULL,
 endpoint VARCHAR(255) NOT NULL,
 request_hash VARCHAR(64) NOT NULL,
 response_status INTEGER,
 response_body TEXT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 expires_at TIMESTAMPTZ NOT NULL,
 UNIQUE(idempotency_key,endpoint)
);

CREATE TABLE stock_movements (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 product_id UUID NOT NULL REFERENCES products(id),
 batch_id UUID NOT NULL REFERENCES batches(id),
 reservation_id UUID REFERENCES reservations(id),
 movement_type VARCHAR(50) NOT NULL,
 quantity BIGINT NOT NULL CHECK (quantity > 0),
 actor_id UUID REFERENCES users(id),
 reason VARCHAR(500) NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 metadata JSONB
);

CREATE TABLE audit_logs (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 actor_id UUID REFERENCES users(id),
 action VARCHAR(100) NOT NULL,
 entity_type VARCHAR(100) NOT NULL,
 entity_id UUID NOT NULL,
 quantity BIGINT CHECK (quantity IS NULL OR quantity > 0),
 product_id UUID,
 batch_id UUID,
 reservation_id UUID,
 reason VARCHAR(500),
 metadata JSONB,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_batches_product_expiry ON batches(product_id,expiry_date);
CREATE INDEX idx_batches_product_available_expiry ON batches(product_id,expiry_date) WHERE available_quantity > 0 AND expired = false;
CREATE INDEX idx_batches_expiry ON batches(expiry_date);
CREATE INDEX idx_reservations_status_expiry ON reservations(status,expires_at);
CREATE INDEX idx_reservations_product ON reservations(product_id);
CREATE INDEX idx_reservation_items_reservation ON reservation_items(reservation_id);
CREATE INDEX idx_reservation_items_batch ON reservation_items(batch_id);
CREATE INDEX idx_idempotency_expiry ON idempotency_keys(expires_at);
CREATE INDEX idx_stock_movements_batch_time ON stock_movements(batch_id,created_at);
CREATE INDEX idx_stock_movements_product_time ON stock_movements(product_id,created_at);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type,entity_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at);
