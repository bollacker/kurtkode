# user-service

Small HTTP API over a users database. Python 3, standard library only.

    python3 -m app.server          # serves on :8080
    python3 -m unittest discover -s tests -t .

Routes: `GET /users?sort=name|joined|id&limit=N`, `GET /search?q=TERM`, `GET /reports/<name>`,
`GET /avatars/<user id>`.
