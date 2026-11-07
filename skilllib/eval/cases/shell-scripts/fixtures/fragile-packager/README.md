# notes

`tools/package.sh SRC_DIR OUT_DIR [NAME]` renders the notes in SRC_DIR and writes OUT_DIR/NAME.tar.gz (NAME
defaults to `notes`). The release job runs `tools/package.sh notes dist` and uploads `dist/notes.tar.gz`.
