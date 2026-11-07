// libedit (macOS's /usr/lib/libedit) through its readline-compatible API. Its globals are set here, in C:
// Swift 6 won't touch mutable C globals.
#include <stdio.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <editline/readline.h>

/// Names the program, sets the completer, and treats @ and the usual separators as word breaks (so "@src/ma"
/// completes "src/ma"). No filename completion when the completer finds nothing.
static inline void kk_editline_setup(char *name, char **(*complete)(const char *, int, int)) {
    rl_readline_name = name;
    rl_attempted_completion_function = (CPPFunction *)complete;
    rl_basic_word_break_characters = " \t\n\"'@<>=;|&(";
    rl_completer_word_break_characters = rl_basic_word_break_characters;
}

/// Inside the completer: no fallback to filename completion.
static inline void kk_completion_over(void) { rl_attempted_completion_over = 1; }

/// The whole line being edited, inside the completer.
static inline const char *kk_line_buffer(void) { return rl_line_buffer; }

static inline void kk_completion_append(int c) { rl_completion_append_character = c; }

/// Ends a pending read at the prompt (Ctrl-C while a question waits): a newline pushed into the terminal's input, as if
/// typed. Only the process's own controlling terminal accepts it.
static inline int kk_push_newline(void) {
    char c = '\n';
    return ioctl(STDIN_FILENO, TIOCSTI, &c);
}
