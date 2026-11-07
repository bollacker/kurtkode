#!/usr/bin/env python3
"""Makes the Go sets' hidden tests implementation-agnostic (REAL_TASKS_PLAN.md's selection rules), after build_go.sh
builds them. Run with the real-fixtures folder as the argument.

  cel02  drops common/types/timestamp_test.go: its only change is a test of the private isStrictRFC3339 against a
         private pattern; the conversion's behavior is tested through String.ConvertToType in string_test.go
  cel04  replaces TestGenRangeMaxSize, which calls the private genRange and defaultMaxRangeSize, with the same checks
         through lists.range() and the public ListsMaxRangeSize option
  opa02  drops TestCannotBeTriviallyNegated, a test of a private helper the fix renamed: without it, whatever the run
         names that helper, the file compiles
  opa06  drops TestCompilerGetRulesDynamic's cases where the parts after r6's variable narrow the result: upstream
         made the recursion check precise by narrowing the public GetRulesDynamic, which the prompt doesn't ask for,
         and a fix inside the recursion check passes every recursion and planner test without it
"""
import os, re, subprocess, sys, tempfile, shutil

os.chdir(sys.argv[1])
def edit(tgz, fn):
    d = tempfile.mkdtemp(); subprocess.run(["tar","-xzf",tgz,"-C",d],check=True); fn(d)
    subprocess.run(["tar","-czf",tgz,"-C",d,"."],check=True); shutil.rmtree(d)
def drop_func(path, name, replacement=""):
    s = open(path).read()
    m = re.search(r"(?m)^func " + name + r"\(.*?^}\n", s, re.S)
    assert m, name
    open(path,"w").write(s[:m.start()] + replacement + s[m.end():])
cel04 = '''func TestListsRangeMaxSize(t *testing.T) {
	eval := func(expr string, opts ...ListsOption) (ref.Val, error) {
		t.Helper()
		env, err := cel.NewEnv(Lists(opts...))
		if err != nil {
			t.Fatalf("cel.NewEnv() failed: %v", err)
		}
		ast, iss := env.Compile(expr)
		if iss.Err() != nil {
			t.Fatalf("Compile(%q) failed: %v", expr, iss.Err())
		}
		prg, err := env.Program(ast)
		if err != nil {
			t.Fatalf("Program(%q) failed: %v", expr, err)
		}
		out, _, err := prg.Eval(cel.NoVars())
		return out, err
	}
	if _, err := eval("lists.range(-1)"); err == nil {
		t.Error("lists.range(-1) succeeded, wanted an error")
	}
	if out, err := eval("lists.range(10).size()"); err != nil || out != types.Int(10) {
		t.Errorf("lists.range(10).size() = %v, %v, wanted 10", out, err)
	}
	if out, err := eval("lists.range(1000000).size()"); err != nil || out != types.Int(1000000) {
		t.Errorf("lists.range(1000000).size() = %v, %v, wanted 1000000 (the default limit is allowed)", out, err)
	}
	if _, err := eval("lists.range(1000001)"); err == nil {
		t.Error("lists.range(1000001) succeeded, wanted an error (over the default limit)")
	}
	if _, err := eval("lists.range(11)", ListsMaxRangeSize(10)); err == nil {
		t.Error("lists.range(11) with ListsMaxRangeSize(10) succeeded, wanted an error")
	}
	if out, err := eval("lists.range(10).size()", ListsMaxRangeSize(10)); err != nil || out != types.Int(10) {
		t.Errorf("lists.range(10).size() with ListsMaxRangeSize(10) = %v, %v, wanted 10", out, err)
	}
	if out, err := eval("lists.range(1000001).size()", ListsMaxRangeSize(0)); err != nil || out != types.Int(1000001) {
		t.Errorf("lists.range(1000001).size() with ListsMaxRangeSize(0) = %v, %v, wanted 1000001 (no limit)", out, err)
	}
}
'''
edit("cel/cel02-hidden.tgz", lambda d: os.remove(os.path.join(d, "common/types/timestamp_test.go")))
def c4(d):
    p = os.path.join(d, "ext/lists_test.go"); drop_func(p, "TestGenRangeMaxSize", cel04)
    s = open(p).read()
    if '"github.com/google/cel-go/common/types/ref"' not in s:
        s = s.replace('\t"github.com/google/cel-go/common/types"\n', '\t"github.com/google/cel-go/common/types"\n\t"github.com/google/cel-go/common/types/ref"\n', 1)
        open(p, "w").write(s)
edit("cel/cel04-hidden.tgz", c4)
edit("opa/opa02-hidden.tgz", lambda d: drop_func(os.path.join(d, "v1/topdown/eval_test.go"), "TestCannotBeTriviallyNegated"))
OPA06_NARROWING = re.compile(r'\t\t// The general refs below all share the ground prefix data.c.d.r6, so\n'
    r'\t\t// the parts after the variable have to narrow the result set.\n'
    r'((?:\t\t\{input: "data.c.d.r6(?:\[x\])?", expected: \[\]\*Rule\{rule6, rule6b, rule6c\}\},\n){2})'
    r'(?:\t\t\{input: "data.c.d.r6[^\n]*\n){5}')
def o6(d):
    p = os.path.join(d, "v1/ast/compile_test.go"); s = open(p).read()
    s, n = OPA06_NARROWING.subn(r"\1", s); assert n == 1, n
    open(p, "w").write(s)
edit("opa/opa06-hidden.tgz", o6)
