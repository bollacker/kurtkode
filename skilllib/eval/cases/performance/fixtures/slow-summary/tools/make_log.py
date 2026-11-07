"""Write a synthetic access log for trying the summary on big input: make_log.py LINES USERS > access.log"""
import random
import sys

lines, users = int(sys.argv[1]), int(sys.argv[2])
rnd = random.Random(1)
paths = [f"/api/v1/{name}" for name in ("orders", "users", "cart", "search", "login", "items", "stats", "health")]
for i in range(lines):
    level = "ERROR" if rnd.random() < 0.03 else "INFO"
    ts = f"2026-10-{1 + i * 30 // lines:02d}T{rnd.randrange(24):02d}:{rnd.randrange(60):02d}:{rnd.randrange(60):02d}"
    print(f"{ts} {level} user=user{rnd.randrange(users)}@example.com path={rnd.choice(paths)} ms={rnd.randrange(5, 900)}")
