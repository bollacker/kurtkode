from dataclasses import dataclass


@dataclass
class Note:
    id: int
    text: str
    created: str
