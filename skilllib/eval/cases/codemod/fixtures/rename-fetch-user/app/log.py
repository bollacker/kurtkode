LINES = []


def info(msg, *args):
    LINES.append(msg % args if args else msg)
