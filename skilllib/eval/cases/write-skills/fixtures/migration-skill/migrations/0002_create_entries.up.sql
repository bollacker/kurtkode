CREATE TABLE entries (
    id INTEGER PRIMARY KEY,
    account_id INTEGER NOT NULL REFERENCES accounts(id),
    amount_cents INTEGER NOT NULL
);
